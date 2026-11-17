-- FreshMart views. Views store a query, not data.

CREATE OR REPLACE VIEW v_order_summary AS
SELECT o.order_id,
       o.order_date,
       o.status,
       c.customer_id,
       c.customer_name,
       w.warehouse_name,
       (SELECT COUNT(*) FROM order_items oi WHERE oi.order_id = o.order_id) AS item_lines,
       o.subtotal,
       o.discount_amount,
       o.delivery_fee,
       o.total_amount
FROM   orders o
JOIN   customers  c ON c.customer_id  = o.customer_id
JOIN   warehouses w ON w.warehouse_id = o.warehouse_id;

CREATE OR REPLACE VIEW v_product_sales AS
SELECT p.product_id,
       p.product_name,
       cat.category_name,
       NVL(SUM(CASE WHEN o.status <> 'CANCELLED' THEN oi.quantity   END), 0) AS units_sold,
       NVL(SUM(CASE WHEN o.status <> 'CANCELLED' THEN oi.line_total END), 0) AS revenue
FROM   products p
JOIN   categories cat ON cat.category_id = p.category_id
LEFT   JOIN order_items oi ON oi.product_id = p.product_id
LEFT   JOIN orders o       ON o.order_id    = oi.order_id
GROUP  BY p.product_id, p.product_name, cat.category_name;

CREATE OR REPLACE VIEW v_low_stock AS
SELECT w.warehouse_name,
       p.product_name,
       i.qty_on_hand,
       i.qty_reserved,
       i.qty_on_hand - i.qty_reserved AS qty_available,
       i.reorder_level
FROM   inventory i
JOIN   warehouses w ON w.warehouse_id = i.warehouse_id
JOIN   products   p ON p.product_id   = i.product_id
WHERE  i.qty_on_hand - i.qty_reserved <= i.reorder_level;
