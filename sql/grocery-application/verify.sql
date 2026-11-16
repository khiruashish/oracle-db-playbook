-- Verifies the loaded sample data against the numbers used in the documentation.
-- Every check must print PASS.

SET SERVEROUTPUT ON

DECLARE
    PROCEDURE chk (p_name VARCHAR2, p_actual NUMBER, p_expected NUMBER) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE(
            CASE WHEN p_actual = p_expected THEN 'PASS ' ELSE 'FAIL ' END
            || RPAD(p_name, 40) || ' actual=' || p_actual || ' expected=' || p_expected);
    END;
    n NUMBER;
BEGIN
    SELECT COUNT(*) INTO n FROM customers;                         chk('customers', n, 6);
    SELECT COUNT(*) INTO n FROM products;                          chk('products', n, 12);
    SELECT COUNT(*) INTO n FROM orders;                            chk('orders', n, 8);
    SELECT COUNT(*) INTO n FROM order_items;                       chk('order_items', n, 20);
    SELECT COUNT(*) INTO n FROM inventory;                         chk('inventory rows', n, 19);
    SELECT SUM(line_total) INTO n
    FROM   order_items oi JOIN orders o ON o.order_id = oi.order_id
    WHERE  o.status <> 'CANCELLED';                                chk('net merchandise value', n, 3668);
    SELECT SUM(total_amount) INTO n FROM orders
    WHERE  status <> 'CANCELLED';                                  chk('net order total', n, 3688);
    SELECT COUNT(*) INTO n
    FROM   orders o
    WHERE  o.subtotal <> (SELECT SUM(line_total) FROM order_items oi
                          WHERE oi.order_id = o.order_id);         chk('orders with wrong subtotal', n, 0);
    SELECT COUNT(*) INTO n FROM inventory
    WHERE  qty_on_hand - qty_reserved <= reorder_level;            chk('low-stock rows', n, 3);
END;
/
