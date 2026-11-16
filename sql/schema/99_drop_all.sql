-- DESTRUCTIVE: drops every FreshMart table and its data. PURGE bypasses the
-- recycle bin, so Flashback Drop cannot bring the tables back.
-- Use only in a learning or test schema. Never run against production.

BEGIN
    FOR t IN (
        SELECT table_name
        FROM   user_tables
        WHERE  table_name IN (
            'AUDIT_LOG', 'REVIEWS', 'RETURNS', 'SHIPMENTS', 'PAYMENTS', 'ORDER_ITEMS',
            'ORDERS', 'COUPONS', 'PROMOTIONS', 'CART_ITEMS', 'CARTS', 'STOCK_MOVEMENTS',
            'INVENTORY', 'ADDRESSES', 'CUSTOMERS', 'EMPLOYEES', 'WAREHOUSES', 'PRODUCTS',
            'SUPPLIERS', 'CATEGORIES')
    ) LOOP
        EXECUTE IMMEDIATE 'DROP TABLE "' || t.table_name || '" CASCADE CONSTRAINTS PURGE';
    END LOOP;
END;
/
