-- ORDER_PKG: the transactional core of FreshMart.
--
-- Design rules used in this package:
--   * No COMMIT or ROLLBACK inside: the caller (application service or script)
--     owns the transaction boundary.
--   * Inventory rows are always touched in PRODUCT_ID order, so two concurrent
--     orders cannot lock the same rows in opposite order (deadlock prevention).
--   * Stock is reserved with a single conditional UPDATE: no read-then-write gap.
--   * Business failures raise named application errors (-20001 .. -20099).

CREATE OR REPLACE PACKAGE order_pkg AUTHID DEFINER AS

    c_free_delivery_from CONSTANT NUMBER := 700;
    c_delivery_fee       CONSTANT NUMBER := 30;

    e_cart_not_active     EXCEPTION;
    e_insufficient_stock  EXCEPTION;
    e_invalid_coupon      EXCEPTION;
    e_order_not_cancellable EXCEPTION;
    PRAGMA EXCEPTION_INIT(e_cart_not_active,       -20001);
    PRAGMA EXCEPTION_INIT(e_insufficient_stock,    -20002);
    PRAGMA EXCEPTION_INIT(e_invalid_coupon,        -20003);
    PRAGMA EXCEPTION_INIT(e_order_not_cancellable, -20004);

    -- Units that can still be sold from one warehouse.
    FUNCTION available_qty (
        p_warehouse_id IN inventory.warehouse_id%TYPE,
        p_product_id   IN inventory.product_id%TYPE
    ) RETURN NUMBER;

    -- Discount for a coupon on a given subtotal and date.
    -- Raises e_invalid_coupon when the coupon cannot be used.
    FUNCTION coupon_discount (
        p_coupon_code IN coupons.coupon_code%TYPE,
        p_subtotal    IN NUMBER,
        p_on_date     IN DATE DEFAULT SYSDATE
    ) RETURN NUMBER;

    -- Converts an ACTIVE cart into an order and reserves stock.
    PROCEDURE place_order (
        p_cart_id      IN  carts.cart_id%TYPE,
        p_address_id   IN  addresses.address_id%TYPE,
        p_warehouse_id IN  warehouses.warehouse_id%TYPE,
        p_coupon_code  IN  coupons.coupon_code%TYPE DEFAULT NULL,
        p_order_id     OUT orders.order_id%TYPE
    );

    -- Cancels a PLACED or PACKED order and releases its reserved stock.
    PROCEDURE cancel_order (
        p_order_id IN orders.order_id%TYPE
    );

END order_pkg;
/

CREATE OR REPLACE PACKAGE BODY order_pkg AS

    FUNCTION available_qty (
        p_warehouse_id IN inventory.warehouse_id%TYPE,
        p_product_id   IN inventory.product_id%TYPE
    ) RETURN NUMBER IS
        l_qty NUMBER;
    BEGIN
        SELECT qty_on_hand - qty_reserved
        INTO   l_qty
        FROM   inventory
        WHERE  warehouse_id = p_warehouse_id
        AND    product_id   = p_product_id;
        RETURN l_qty;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RETURN 0;   -- product is not stocked in this warehouse
    END available_qty;

    FUNCTION coupon_discount (
        p_coupon_code IN coupons.coupon_code%TYPE,
        p_subtotal    IN NUMBER,
        p_on_date     IN DATE DEFAULT SYSDATE
    ) RETURN NUMBER IS
        l_type  promotions.discount_type%TYPE;
        l_value promotions.discount_value%TYPE;
    BEGIN
        SELECT p.discount_type, p.discount_value
        INTO   l_type, l_value
        FROM   coupons c
        JOIN   promotions p ON p.promotion_id = c.promotion_id
        WHERE  c.coupon_code = p_coupon_code
        AND    c.is_active = 'Y'
        AND    c.used_count < c.max_uses
        AND    p_on_date BETWEEN c.valid_from AND c.valid_to
        AND    p_subtotal >= c.min_order_amount;

        RETURN CASE l_type
                   WHEN 'PERCENT' THEN ROUND(p_subtotal * l_value / 100, 2)
                   ELSE LEAST(l_value, p_subtotal)
               END;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20003,
                'Coupon ' || p_coupon_code || ' is not valid for this order');
    END coupon_discount;

    PROCEDURE place_order (
        p_cart_id      IN  carts.cart_id%TYPE,
        p_address_id   IN  addresses.address_id%TYPE,
        p_warehouse_id IN  warehouses.warehouse_id%TYPE,
        p_coupon_code  IN  coupons.coupon_code%TYPE DEFAULT NULL,
        p_order_id     OUT orders.order_id%TYPE
    ) IS
        l_customer_id carts.customer_id%TYPE;
        l_subtotal    NUMBER := 0;
        l_discount    NUMBER := 0;
        l_fee         NUMBER;
        l_coupon_id   coupons.coupon_id%TYPE;
        l_line_no     PLS_INTEGER := 0;
    BEGIN
        -- 1. Lock the cart so that two requests cannot convert it twice.
        BEGIN
            SELECT customer_id
            INTO   l_customer_id
            FROM   carts
            WHERE  cart_id = p_cart_id
            AND    status  = 'ACTIVE'
            FOR UPDATE;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(-20001, 'Cart ' || p_cart_id || ' is not active');
        END;

        -- 2. Reserve stock, lowest product_id first (consistent lock order).
        FOR r IN (SELECT ci.product_id, ci.quantity, p.unit_price, p.product_name
                  FROM   cart_items ci
                  JOIN   products p ON p.product_id = ci.product_id
                  WHERE  ci.cart_id = p_cart_id
                  ORDER  BY ci.product_id)
        LOOP
            UPDATE inventory
            SET    qty_reserved = qty_reserved + r.quantity
            WHERE  warehouse_id = p_warehouse_id
            AND    product_id   = r.product_id
            AND    qty_on_hand - qty_reserved >= r.quantity;

            IF SQL%ROWCOUNT = 0 THEN
                RAISE_APPLICATION_ERROR(-20002,
                    'Insufficient stock for ' || r.product_name);
            END IF;

            l_subtotal := l_subtotal + r.quantity * r.unit_price;
        END LOOP;

        IF l_subtotal = 0 THEN
            RAISE_APPLICATION_ERROR(-20001, 'Cart ' || p_cart_id || ' is empty');
        END IF;

        -- 3. Coupon: validate, then consume one use.
        IF p_coupon_code IS NOT NULL THEN
            l_discount := coupon_discount(p_coupon_code, l_subtotal);

            UPDATE coupons
            SET    used_count = used_count + 1
            WHERE  coupon_code = p_coupon_code
            AND    used_count < max_uses
            RETURNING coupon_id INTO l_coupon_id;

            IF SQL%ROWCOUNT = 0 THEN
                RAISE_APPLICATION_ERROR(-20003, 'Coupon ' || p_coupon_code || ' is exhausted');
            END IF;
        END IF;

        l_fee := CASE WHEN l_subtotal >= c_free_delivery_from THEN 0 ELSE c_delivery_fee END;

        -- 4. Order header.
        INSERT INTO orders (customer_id, address_id, warehouse_id, coupon_id,
                            status, subtotal, discount_amount, delivery_fee, total_amount)
        VALUES (l_customer_id, p_address_id, p_warehouse_id, l_coupon_id,
                'PLACED', l_subtotal, l_discount, l_fee, l_subtotal - l_discount + l_fee)
        RETURNING order_id INTO p_order_id;

        -- 5. Order lines: price is copied (snapshot) from the catalog.
        FOR r IN (SELECT ci.product_id, ci.quantity, p.unit_price
                  FROM   cart_items ci
                  JOIN   products p ON p.product_id = ci.product_id
                  WHERE  ci.cart_id = p_cart_id
                  ORDER  BY ci.product_id)
        LOOP
            l_line_no := l_line_no + 1;
            INSERT INTO order_items (order_id, line_no, product_id, quantity, unit_price)
            VALUES (p_order_id, l_line_no, r.product_id, r.quantity, r.unit_price);
        END LOOP;

        -- 6. Close the cart.
        UPDATE carts SET status = 'CONVERTED' WHERE cart_id = p_cart_id;
    END place_order;

    PROCEDURE cancel_order (
        p_order_id IN orders.order_id%TYPE
    ) IS
        l_status       orders.status%TYPE;
        l_warehouse_id orders.warehouse_id%TYPE;
    BEGIN
        BEGIN
            SELECT status, warehouse_id
            INTO   l_status, l_warehouse_id
            FROM   orders
            WHERE  order_id = p_order_id
            FOR UPDATE;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(-20004, 'Order ' || p_order_id || ' does not exist');
        END;

        IF l_status NOT IN ('PLACED', 'PACKED') THEN
            RAISE_APPLICATION_ERROR(-20004,
                'Order ' || p_order_id || ' is ' || l_status || ' and cannot be cancelled');
        END IF;

        FOR r IN (SELECT product_id, quantity
                  FROM   order_items
                  WHERE  order_id = p_order_id
                  ORDER  BY product_id)
        LOOP
            UPDATE inventory
            SET    qty_reserved = qty_reserved - r.quantity
            WHERE  warehouse_id = l_warehouse_id
            AND    product_id   = r.product_id;
        END LOOP;

        UPDATE orders   SET status = 'CANCELLED' WHERE order_id = p_order_id;
        UPDATE payments SET status = 'REFUNDED'
        WHERE  order_id = p_order_id AND status = 'SUCCESS';
    END cancel_order;

END order_pkg;
/

SHOW ERRORS
