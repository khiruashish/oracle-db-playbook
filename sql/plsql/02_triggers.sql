-- FreshMart triggers.
-- Triggers are used here only for cross-cutting technical concerns
-- (timestamps, audit). Business logic lives in ORDER_PKG, where it is visible
-- and testable.

CREATE OR REPLACE TRIGGER trg_products_bu
BEFORE UPDATE ON products
FOR EACH ROW
BEGIN
    :NEW.updated_at := SYSTIMESTAMP;
END;
/

CREATE OR REPLACE TRIGGER trg_customers_bu
BEFORE UPDATE ON customers
FOR EACH ROW
BEGIN
    :NEW.updated_at  := SYSTIMESTAMP;
    :NEW.row_version := :OLD.row_version + 1;
END;
/

CREATE OR REPLACE TRIGGER trg_inventory_bu
BEFORE UPDATE ON inventory
FOR EACH ROW
BEGIN
    :NEW.updated_at  := SYSTIMESTAMP;
    :NEW.row_version := :OLD.row_version + 1;
END;
/

CREATE OR REPLACE TRIGGER trg_orders_bu
BEFORE UPDATE ON orders
FOR EACH ROW
BEGIN
    :NEW.updated_at := SYSTIMESTAMP;
END;
/

-- Audit every order status change and every order delete.
CREATE OR REPLACE TRIGGER trg_orders_audit
AFTER UPDATE OF status OR DELETE ON orders
FOR EACH ROW
BEGIN
    IF UPDATING AND :OLD.status <> :NEW.status THEN
        INSERT INTO audit_log (table_name, operation, pk_value, old_values, new_values)
        VALUES ('ORDERS', 'UPDATE', TO_CHAR(:OLD.order_id),
                'status=' || :OLD.status, 'status=' || :NEW.status);
    ELSIF DELETING THEN
        INSERT INTO audit_log (table_name, operation, pk_value, old_values, new_values)
        VALUES ('ORDERS', 'DELETE', TO_CHAR(:OLD.order_id),
                'status=' || :OLD.status || ',total=' || :OLD.total_amount, NULL);
    END IF;
END;
/

-- Audit catalog price changes.
CREATE OR REPLACE TRIGGER trg_products_price_audit
AFTER UPDATE OF unit_price ON products
FOR EACH ROW
WHEN (OLD.unit_price <> NEW.unit_price)
BEGIN
    INSERT INTO audit_log (table_name, operation, pk_value, old_values, new_values)
    VALUES ('PRODUCTS', 'UPDATE', TO_CHAR(:OLD.product_id),
            'unit_price=' || :OLD.unit_price, 'unit_price=' || :NEW.unit_price);
END;
/
