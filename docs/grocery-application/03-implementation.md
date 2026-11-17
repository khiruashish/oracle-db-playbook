---
tags: [freshmart, implementation, plsql]
---

# FreshMart 3: Implementation

Everything on this page is in the repository under `sql/`. Install it with
`sql/grocery-application/install.sql` ([setup](../getting-started/setup.md)).
The scripts were written for 19c and later and **have not been executed** in
this repository's build environment: run the install in your lab and check the
`PASS` lines.

## Tables

The complete DDL is `sql/schema/01_tables.sql` (20 tables, 23 secondary
indexes). Two representative tables:

```sql
--8<-- "sql/schema/01_tables.sql:210:253"
```

Design points visible above:

| Feature | Where | Why |
|---|---|---|
| Identity key | `order_id` | Generated, gap-tolerant, no trigger |
| Named constraints | Every one | Errors identify the rule |
| Check on a derived total | `ck_orders_total` | The denormalized total cannot drift |
| Composite primary key | `order_items (order_id, line_no)` | Weak entity; lines cluster under their order in the index |
| Extra unique key | `uq_order_items_product` | One line per product per order (rule R10) |
| Virtual column | `line_total` | Derived, zero storage, always consistent |
| Price snapshot | `order_items.unit_price` | History does not change when the catalog does |

### Index strategy

| Index | Serves |
|---|---|
| Primary and unique constraint indexes | Key lookups, integrity |
| One index per foreign key | Joins from parent; no child-table locks on parent DML |
| `ix_orders_cust_date (customer_id, order_date DESC)` | "My orders", newest first, without a sort |
| `ix_orders_status_date (status, order_date)` | Fulfilment work queue |
| `ix_products_name_upper (UPPER(product_name))` | Case-insensitive prefix search |
| `ix_stock_mov_wh_prod (warehouse_id, product_id, moved_at)` | Stock history; also covers the composite foreign key |
| `ix_audit_log_tab_time (table_name, changed_at)` | Audit queries by object and period |

## Views

`sql/plsql/01_views.sql` defines `v_order_summary`, `v_product_sales` and
`v_low_stock`: the agreed definitions of "an order", "product revenue"
(cancelled orders excluded) and "low stock". Reports use the views so that the
definitions exist once.

## Triggers

`sql/plsql/02_triggers.sql`. Triggers are limited to technical concerns:

| Trigger | Purpose |
|---|---|
| `trg_products_bu`, `trg_orders_bu` | Maintain `updated_at` |
| `trg_customers_bu`, `trg_inventory_bu` | Maintain `updated_at` and increment `row_version` |
| `trg_orders_audit` | Log status changes and deletes to `audit_log` |
| `trg_products_price_audit` | Log price changes |

Business logic is deliberately not in triggers
([2.9](../plsql/03-subprograms-packages-triggers.md)).

## The order package

`sql/plsql/03_order_pkg.sql`. Specification:

```sql
--8<-- "sql/plsql/03_order_pkg.sql:11:53"
```

### place_order, step by step

| Step | Statement | Protects against |
|---|---|---|
| 1 | `SELECT ... FROM carts WHERE status = 'ACTIVE' FOR UPDATE` | The same cart being converted twice |
| 2 | For each cart item **in product id order**: conditional `UPDATE inventory` | Overselling; deadlocks between concurrent orders |
| 3 | `coupon_discount`, then `UPDATE coupons SET used_count = used_count + 1 WHERE used_count < max_uses` | Invalid coupons; exceeding the usage limit under concurrency |
| 4 | `INSERT INTO orders ... RETURNING order_id` | |
| 5 | `INSERT INTO order_items` with the catalog price copied | Later price changes |
| 6 | `UPDATE carts SET status = 'CONVERTED'` | |

Any failure raises an exception; the caller rolls back and nothing remains. No
`COMMIT` occurs inside the package.

### Using it

```sql
SET SERVEROUTPUT ON
DECLARE
    l_order_id orders.order_id%TYPE;
BEGIN
    order_pkg.place_order(p_cart_id => 1, p_address_id => 203,
                          p_warehouse_id => 1, p_order_id => l_order_id);
    DBMS_OUTPUT.PUT_LINE('Order ' || l_order_id);
END;
/
SELECT order_id, status, subtotal, discount_amount, delivery_fee, total_amount
FROM   orders WHERE customer_id = 103 ORDER BY order_id;

SELECT product_id, qty_on_hand, qty_reserved FROM inventory
WHERE  warehouse_id = 1 AND product_id IN (1, 10);

ROLLBACK;     -- keep the sample data unchanged
```

Expected (derived from the sample data and the package logic):

| ORDER_ID | STATUS | SUBTOTAL | DISCOUNT_AMOUNT | DELIVERY_FEE | TOTAL_AMOUNT |
|---:|---|---:|---:|---:|---:|
| 1004 | SHIPPED | 326 | 0 | 30 | 356 |
| 1009 | PLACED | 330 | 0 | 30 | 360 |

| PRODUCT_ID | QTY_ON_HAND | QTY_RESERVED |
|---:|---:|---:|
| 1 | 120 | 1 |
| 10 | 50 | 1 |

The new order id is 1009 if the identity reset script has run and no other
order was created; identity values consumed by rolled-back attempts are not
reused, so your number may be higher.

## Feature map

Where each advanced technique is demonstrated with FreshMart objects:

| Technique | Location |
|---|---|
| Stored procedures, functions, packages | `order_pkg`; [2.9](../plsql/03-subprograms-packages-triggers.md) |
| Triggers, audit logging | `sql/plsql/02_triggers.sql`; `audit_log` |
| Bulk processing | Price feed example in [2.8](../plsql/02-cursors-collections-bulk.md) |
| Dynamic SQL | `search_orders` in [2.10](../plsql/04-exceptions-dynamic-advanced.md) |
| Error handling | Named exceptions in `order_pkg`; mapping in [4.8](../spring-boot-integration/01-spring-boot.md) |
| Transaction management, locking | [2.11](../transactions/01-transactions-concurrency.md) |
| Analytical SQL | [2.5](../advanced-sql/05-window-functions.md), [business queries](04-business-queries.md) |
| Materialized views | `mv_daily_sales` in [2.14](../database-objects/01-database-objects.md) |
| Partitioning | `orders_p` in [2.13](../partitioning/01-partitioning.md) |
| Advanced indexes | [2.12](../indexing/01-indexing.md) |
| Flashback, backup and recovery | [3.4](../backup-recovery/01-backup-recovery.md) |
| Security | [3.5](../security/01-security.md) |
| Performance tuning | [2.15](../performance-engineering/01-execution-plans.md), [incidents](../performance-incidents/01-incidents.md) |

## Accounts and privileges

| Account | Purpose | Privileges |
|---|---|---|
| `FRESHMART` | Schema owner | Object creation; used only by the deployment pipeline; no interactive login in production |
| `FM_APP` | Application connection pool | `CREATE SESSION`; `EXECUTE` on `order_pkg`; DML on cart tables; `SELECT` on catalog and order views |
| `FM_REPORT` | Reporting | `CREATE SESSION`; `SELECT` on the `v_` views |
| Named personal accounts | Support, DBAs | Role-based, audited |

```sql
CREATE ROLE fm_app_role;
GRANT EXECUTE ON freshmart.order_pkg TO fm_app_role;
GRANT SELECT ON freshmart.products TO fm_app_role;
GRANT SELECT ON freshmart.categories TO fm_app_role;
GRANT SELECT ON freshmart.v_order_summary TO fm_app_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON freshmart.carts TO fm_app_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON freshmart.cart_items TO fm_app_role;
GRANT SELECT, INSERT ON freshmart.customers TO fm_app_role;
GRANT UPDATE (customer_name, phone, city) ON freshmart.customers TO fm_app_role;
```

The application cannot update `orders` or `inventory` directly: those changes
go through the package.

## Check yourself

??? example "Exercises"
    1. Place an order for cart 2 (Neha, 2 × Bread) from warehouse 2, where only 10 loaves are available. What happens and what are the totals? *Succeeds: subtotal 90, fee 30, total 120; bread reserved 2.*
    2. Change the quantity in cart 2 to 11 and try again. *`ORA-20002 Insufficient stock for Whole Wheat Bread 400g`.*
    3. Call `cancel_order(1001)`. *`ORA-20004`: the order is DELIVERED.*
    4. Add `order_pkg.mark_shipped` that sets the status, creates the shipment row and converts reserved stock into a decrement of `qty_on_hand` plus a `SALE` movement.

Next: [Business queries](04-business-queries.md).
