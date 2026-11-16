-- =============================================================================
-- FreshMart: 20 business queries. Bind variables (:name) mark application input.
-- The "-- --8<--" markers let the documentation include each query by name.
-- Statements that change data are meant to be followed by ROLLBACK in the lab.
-- =============================================================================

-- --8<-- [start:q01]
-- 1. Customer registration
INSERT INTO customers (customer_name, email, phone, city)
VALUES (:name, LOWER(:email), :phone, :city)
RETURNING customer_id INTO :customer_id;
-- --8<-- [end:q01]

-- --8<-- [start:q02]
-- 2. Product catalog: one keyset page of active products
SELECT p.product_id, p.product_name, p.unit_price, p.unit_of_measure, c.category_name
FROM   products p
JOIN   categories c ON c.category_id = p.category_id
WHERE  p.is_active = 'Y'
AND    (:last_name IS NULL
        OR p.product_name > :last_name
        OR (p.product_name = :last_name AND p.product_id > :last_id))
ORDER  BY p.product_name, p.product_id
FETCH  FIRST 5 ROWS ONLY;
-- --8<-- [end:q02]

-- --8<-- [start:q03]
-- 3. Product search: case-insensitive prefix (uses ix_products_name_upper)
SELECT product_id, product_name, unit_price
FROM   products
WHERE  UPPER(product_name) LIKE UPPER(:term) || '%'
AND    is_active = 'Y'
ORDER  BY product_name;
-- --8<-- [end:q03]

-- --8<-- [start:q04]
-- 4. Category browsing: a category and all of its subcategories
SELECT p.product_id, p.product_name, p.unit_price
FROM   products p
WHERE  p.category_id IN (SELECT category_id
                         FROM   categories
                         START  WITH category_id = :category_id
                         CONNECT BY PRIOR category_id = parent_category_id)
AND    p.is_active = 'Y'
ORDER  BY p.product_name;
-- --8<-- [end:q04]

-- --8<-- [start:q05]
-- 5. Shopping cart contents with line and cart totals
SELECT p.product_name, ci.quantity, p.unit_price,
       ci.quantity * p.unit_price                 AS line_total,
       SUM(ci.quantity * p.unit_price) OVER ()    AS cart_total
FROM   carts k
JOIN   cart_items ci ON ci.cart_id   = k.cart_id
JOIN   products p    ON p.product_id = ci.product_id
WHERE  k.customer_id = :customer_id
AND    k.status = 'ACTIVE'
ORDER  BY p.product_name;
-- --8<-- [end:q05]

-- --8<-- [start:q06]
-- 6. Add to cart (insert, or increase the quantity) and remove from cart
MERGE INTO cart_items t
USING (SELECT :cart_id AS cart_id, :product_id AS product_id, :qty AS qty FROM dual) s
ON    (t.cart_id = s.cart_id AND t.product_id = s.product_id)
WHEN MATCHED THEN UPDATE SET t.quantity = t.quantity + s.qty
WHEN NOT MATCHED THEN INSERT (cart_id, product_id, quantity) VALUES (s.cart_id, s.product_id, s.qty);

DELETE FROM cart_items WHERE cart_id = :cart_id AND product_id = :product_id;
-- --8<-- [end:q06]

-- --8<-- [start:q07]
-- 7. Order placement: one call, one transaction (see sql/plsql/03_order_pkg.sql)
BEGIN
    order_pkg.place_order(
        p_cart_id      => :cart_id,
        p_address_id   => :address_id,
        p_warehouse_id => :warehouse_id,
        p_coupon_code  => :coupon_code,
        p_order_id     => :order_id);
    COMMIT;
END;
/
-- --8<-- [end:q07]

-- --8<-- [start:q08]
-- 8. Inventory reservation: atomic check-and-reserve
UPDATE inventory
SET    qty_reserved = qty_reserved + :qty
WHERE  warehouse_id = :warehouse_id
AND    product_id   = :product_id
AND    qty_on_hand - qty_reserved >= :qty;
-- 1 row updated = reserved; 0 rows = insufficient stock
-- --8<-- [end:q08]

-- --8<-- [start:q09]
-- 9. Payment record: idempotent on the gateway reference
INSERT INTO payments (order_id, payment_method, amount, status, txn_reference)
VALUES (:order_id, :method, :amount, :status, :txn_reference);
-- A retry with the same txn_reference raises ORA-00001 (uq_payments_txn): treat as already recorded.

SELECT o.order_id, o.total_amount,
       NVL(SUM(CASE WHEN p.status = 'SUCCESS' THEN p.amount END), 0) AS paid,
       COUNT(CASE WHEN p.status = 'FAILED' THEN 1 END)               AS failed_attempts
FROM   orders o
LEFT   JOIN payments p ON p.order_id = o.order_id
WHERE  o.order_id = :order_id
GROUP  BY o.order_id, o.total_amount;
-- --8<-- [end:q09]

-- --8<-- [start:q10]
-- 10. Order cancellation
BEGIN
    order_pkg.cancel_order(p_order_id => :order_id);
    COMMIT;
END;
/
-- --8<-- [end:q10]

-- --8<-- [start:q11]
-- 11. Refunds: money returned per order (cancelled orders and refunded returns)
SELECT o.order_id, o.status,
       NVL((SELECT SUM(p.amount) FROM payments p
            WHERE  p.order_id = o.order_id AND p.status = 'REFUNDED'), 0)          AS payment_refunded,
       NVL((SELECT SUM(r.refund_amount) FROM returns r
            WHERE  r.order_id = o.order_id AND r.status = 'REFUNDED'), 0)          AS return_refunded
FROM   orders o
WHERE  EXISTS (SELECT 1 FROM payments p WHERE p.order_id = o.order_id AND p.status = 'REFUNDED')
OR     EXISTS (SELECT 1 FROM returns  r WHERE r.order_id = o.order_id AND r.status = 'REFUNDED')
ORDER  BY o.order_id;
-- --8<-- [end:q11]

-- --8<-- [start:q12]
-- 12. Returns: request a return, and list open requests
INSERT INTO returns (order_id, line_no, quantity, reason, refund_amount)
SELECT oi.order_id, oi.line_no, :qty, :reason, :qty * oi.unit_price
FROM   order_items oi
JOIN   orders o ON o.order_id = oi.order_id
WHERE  oi.order_id = :order_id AND oi.line_no = :line_no
AND    o.status = 'DELIVERED'
AND    :qty <= oi.quantity - NVL((SELECT SUM(r.quantity) FROM returns r
                                  WHERE  r.order_id = oi.order_id AND r.line_no = oi.line_no
                                  AND    r.status <> 'REJECTED'), 0);

SELECT r.return_id, r.order_id, p.product_name, r.quantity, r.reason, r.refund_amount
FROM   returns r
JOIN   order_items oi ON oi.order_id = r.order_id AND oi.line_no = r.line_no
JOIN   products p     ON p.product_id = oi.product_id
WHERE  r.status = 'REQUESTED'
ORDER  BY r.requested_at;
-- --8<-- [end:q12]

-- --8<-- [start:q13]
-- 13. Shipment tracking
SELECT o.order_id, o.status AS order_status, s.carrier, s.tracking_number,
       s.status AS shipment_status, s.shipped_at, s.delivered_at, e.employee_name AS delivered_by
FROM   orders o
LEFT   JOIN shipments s ON s.order_id = o.order_id
LEFT   JOIN employees e ON e.employee_id = s.delivered_by
WHERE  o.customer_id = :customer_id
ORDER  BY o.order_date DESC;
-- --8<-- [end:q13]

-- --8<-- [start:q14]
-- 14. Coupon validation: returns the discount, or raises ORA-20003
SELECT order_pkg.coupon_discount(:coupon_code, :subtotal, :on_date) AS discount FROM dual;
-- --8<-- [end:q14]

-- --8<-- [start:q15]
-- 15. Product recommendations: bought together with a given product
SELECT p.product_id, p.product_name, COUNT(*) AS times_bought_together
FROM   order_items a
JOIN   order_items b ON b.order_id = a.order_id AND b.product_id <> a.product_id
JOIN   orders o      ON o.order_id = a.order_id AND o.status <> 'CANCELLED'
JOIN   products p    ON p.product_id = b.product_id
WHERE  a.product_id = :product_id
GROUP  BY p.product_id, p.product_name
ORDER  BY times_bought_together DESC, p.product_name
FETCH  FIRST 5 ROWS ONLY;
-- --8<-- [end:q15]

-- --8<-- [start:q16]
-- 16. Low-stock report
SELECT w.warehouse_name, p.product_name,
       i.qty_on_hand - i.qty_reserved                       AS qty_available,
       i.reorder_level,
       2 * i.reorder_level - (i.qty_on_hand - i.qty_reserved) AS suggested_order_qty
FROM   inventory i
JOIN   warehouses w ON w.warehouse_id = i.warehouse_id
JOIN   products   p ON p.product_id   = i.product_id
WHERE  i.qty_on_hand - i.qty_reserved <= i.reorder_level
ORDER  BY w.warehouse_name, p.product_name;
-- --8<-- [end:q16]

-- --8<-- [start:q17]
-- 17. Sales report: orders and revenue per month with month-over-month change
SELECT month, orders, revenue,
       revenue - LAG(revenue) OVER (ORDER BY month) AS change_vs_previous
FROM  (SELECT TO_CHAR(order_date, 'YYYY-MM') AS month,
              COUNT(*)                       AS orders,
              SUM(total_amount)              AS revenue
       FROM   orders
       WHERE  status <> 'CANCELLED'
       GROUP  BY TO_CHAR(order_date, 'YYYY-MM'))
ORDER  BY month;
-- --8<-- [end:q17]

-- --8<-- [start:q18]
-- 18. Customer purchase history
SELECT o.order_id, o.order_date, o.status, o.total_amount,
       LISTAGG(p.product_name || ' x' || oi.quantity, ', ')
           WITHIN GROUP (ORDER BY oi.line_no) AS items
FROM   orders o
JOIN   order_items oi ON oi.order_id  = o.order_id
JOIN   products p     ON p.product_id = oi.product_id
WHERE  o.customer_id = :customer_id
GROUP  BY o.order_id, o.order_date, o.status, o.total_amount
ORDER  BY o.order_date DESC;
-- --8<-- [end:q18]

-- --8<-- [start:q19]
-- 19. Best-selling products by revenue
SELECT p.product_name,
       SUM(oi.quantity)   AS units_sold,
       SUM(oi.line_total) AS revenue,
       RANK() OVER (ORDER BY SUM(oi.line_total) DESC) AS revenue_rank
FROM   order_items oi
JOIN   orders o   ON o.order_id   = oi.order_id
JOIN   products p ON p.product_id = oi.product_id
WHERE  o.status <> 'CANCELLED'
GROUP  BY p.product_name
ORDER  BY revenue_rank, p.product_name
FETCH  FIRST 5 ROWS ONLY;
-- --8<-- [end:q19]

-- --8<-- [start:q20]
-- 20. Warehouse inventory report
SELECT w.warehouse_name,
       COUNT(*)                            AS products_stocked,
       SUM(i.qty_on_hand)                  AS units_on_hand,
       SUM(i.qty_reserved)                 AS units_reserved,
       SUM(i.qty_on_hand * p.unit_price)   AS stock_value
FROM   inventory i
JOIN   warehouses w ON w.warehouse_id = i.warehouse_id
JOIN   products   p ON p.product_id   = i.product_id
GROUP  BY w.warehouse_name
ORDER  BY w.warehouse_name;
-- --8<-- [end:q20]
