---
tags: [stage-2, plsql, packages, triggers]
---

# 2.9 Procedures, functions, packages, triggers

!!! abstract "Chapter card"
    **Stage:** 2 · **Prerequisites:** 2.8 · **Time:** 5 hours · **Applies to:** 19c+

## At a glance

| Subtopic | In one line |
|---|---|
| Procedure | A named block that performs an action |
| Function | A named block that returns a value; callable from SQL |
| Parameters | `IN`, `OUT`, `IN OUT`, defaults, named notation |
| Package | A specification (the contract) plus a body (the code) |
| Definer and invoker rights | Whose privileges the code runs with |
| Triggers | Code that fires on DML, DDL or database events |
| Compound triggers | One trigger with several timing points |

## 1. Procedures and functions

```sql
CREATE OR REPLACE PROCEDURE deactivate_product (
    p_product_id IN products.product_id%TYPE
) IS
BEGIN
    UPDATE products SET is_active = 'N' WHERE product_id = p_product_id;
    IF SQL%ROWCOUNT = 0 THEN
        RAISE_APPLICATION_ERROR(-20010, 'Product ' || p_product_id || ' not found');
    END IF;
END deactivate_product;
/

CREATE OR REPLACE FUNCTION order_item_count (
    p_order_id IN orders.order_id%TYPE
) RETURN PLS_INTEGER IS
    l_count PLS_INTEGER;
BEGIN
    SELECT COUNT(*) INTO l_count FROM order_items WHERE order_id = p_order_id;
    RETURN l_count;
END order_item_count;
/

SELECT order_id, order_item_count(order_id) AS lines FROM orders WHERE order_id <= 1002;
-- 1001 3 / 1002 2
```

| | Procedure | Function |
|---|---|---|
| Returns | Nothing (may have `OUT` parameters) | One value via `RETURN` |
| Called from | PL/SQL, `CALL`, `EXEC` | PL/SQL and SQL expressions |
| Use for | Actions that change state | Computing a value; should have no side effects |

### Parameters

| Mode | Direction | Passed | Notes |
|---|---|---|---|
| `IN` (default) | Caller to subprogram | By reference, read-only | May have a `DEFAULT` |
| `OUT` | Subprogram to caller | By value (copied back on success) | Starts as `NULL` |
| `IN OUT` | Both | By value | |
| `... NOCOPY` | Hint | By reference | Avoids copying large collections; values may be half-changed if an exception occurs |

Call with **named notation** when there are more than two parameters:
`order_pkg.place_order(p_cart_id => 1, p_address_id => 203, p_warehouse_id => 3, p_order_id => l_id);`

### Functions called from SQL

Each call from SQL is a context switch, and the function's own queries are
**not** read-consistent with the calling statement. Options to reduce the cost:

| Technique | Effect |
|---|---|
| `DETERMINISTIC` | Declares same input → same output; allows caching within a fetch and use in function-based indexes |
| `RESULT_CACHE` | Caches results in the SGA across sessions; invalidated when referenced tables change. For rarely changing lookups |
| `PRAGMA UDF` | Compiles the function for cheaper calls from SQL (12.1+) |
| Scalar subquery wrapper: `(SELECT f(x) FROM dual)` | Uses scalar subquery caching |
| SQL macro (`SQL_MACRO`) | The function returns SQL text that is merged into the query: no context switch at run time (:material-tag: **21c+**; table macros in 19c) |

## 2. Packages

A package groups related subprograms, types and constants. It has two parts:

- **Specification**: what callers can see and use.
- **Body**: the implementation, plus private helpers.

The complete FreshMart package is `sql/plsql/03_order_pkg.sql`. Its
specification:

```sql
--8<-- "sql/plsql/03_order_pkg.sql:11:53"
```

### Why packages

| Benefit | Explanation |
|---|---|
| Encapsulation | Callers depend on the specification only. You can rewrite the body without invalidating them |
| Fewer invalidations | Standalone procedures calling each other invalidate in chains when one changes |
| Private code and state | Helpers and variables in the body are invisible outside |
| Overloading | Several subprograms with one name and different parameter types |
| Loading | The package is loaded into memory once, on first use |

**Package state**: a variable declared at package level lives for the session.
If the body is recompiled while a session holds state, that session's next call
gets `ORA-04068: existing state of packages has been discarded`. With connection
pools, session state is also shared between unrelated requests. Keep packages
stateless (constants are fine), or mark them `PRAGMA SERIALLY_REUSABLE`.

### Definer and invoker rights

| | `AUTHID DEFINER` (default) | `AUTHID CURRENT_USER` |
|---|---|---|
| Runs with privileges of | The owner | The caller |
| Unqualified names resolve in | Owner's schema | Caller's schema |
| Roles | Disabled | Enabled |
| Use for | Application APIs: grant `EXECUTE`, not table access | Utilities that act on the caller's own objects |

In a definer-rights unit, privileges granted to the owner **through a role** do
not apply. A statement that works in SQL*Plus and fails with `ORA-00942` inside
a procedure nearly always has this cause: grant the privilege directly.

Use `ACCESSIBLE BY (pkg1, pkg2)` to restrict which units may call a package.

### Dependencies and invalidation

Oracle tracks what each unit references. Since 11g tracking is fine-grained:
adding a column to a table does not invalidate code that does not use it.
Invalid units recompile automatically on next use; after a deployment, check
`USER_OBJECTS WHERE status = 'INVALID'` and run `UTL_RECOMP` or
`DBMS_UTILITY.COMPILE_SCHEMA`.

## 3. Triggers

A trigger runs automatically when an event happens.

| Type | Fires on |
|---|---|
| DML trigger | `INSERT`, `UPDATE`, `DELETE` on a table |
| `INSTEAD OF` trigger | DML on a view |
| DDL trigger | `CREATE`, `ALTER`, `DROP` in a schema or database |
| System trigger | `LOGON`, `LOGOFF`, `STARTUP`, `SERVERERROR` |

```sql
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
```

- **Timing**: `BEFORE` (can change `:NEW`) or `AFTER` (for auditing and derived writes).
- **Level**: `FOR EACH ROW` fires per row and sees `:OLD` / `:NEW`; a statement trigger fires once.
- **Firing order**: before statement, before each row, after each row, after statement. Triggers of the same type fire in undefined order unless you use `FOLLOWS`.

### Mutating table error and compound triggers

A row-level trigger may not query the table that is being changed
(`ORA-04091: table is mutating`). A **compound trigger** collects keys per row
and does the work once at the end of the statement:

```sql
CREATE OR REPLACE TRIGGER trg_order_items_subtotal
FOR INSERT OR UPDATE OR DELETE ON order_items
COMPOUND TRIGGER
    TYPE t_ids IS TABLE OF BOOLEAN INDEX BY PLS_INTEGER;
    g_order_ids t_ids;

    AFTER EACH ROW IS
    BEGIN
        g_order_ids(NVL(:NEW.order_id, :OLD.order_id)) := TRUE;
    END AFTER EACH ROW;

    AFTER STATEMENT IS
        l_id PLS_INTEGER := g_order_ids.FIRST;
    BEGIN
        WHILE l_id IS NOT NULL LOOP
            UPDATE orders o
            SET    o.subtotal     = (SELECT NVL(SUM(line_total), 0) FROM order_items WHERE order_id = l_id),
                   o.total_amount = (SELECT NVL(SUM(line_total), 0) FROM order_items WHERE order_id = l_id)
                                    - o.discount_amount + o.delivery_fee
            WHERE  o.order_id = l_id;
            l_id := g_order_ids.NEXT(l_id);
        END LOOP;
    END AFTER STATEMENT;
END;
/
```

This trigger is shown to teach the pattern. FreshMart does **not** install it:
totals are maintained in `order_pkg`, where the logic is explicit.

### When to use triggers

| Reasonable | Avoid |
|---|---|
| Audit columns and audit trails | Business workflows hidden in triggers |
| Derived technical values | Cross-row validation (not safe under concurrency without locking) |
| `INSTEAD OF` on views | Calling external services, sending email (not transactional) |
| Logon checks | `COMMIT` in a trigger (illegal unless autonomous) |

Triggers make single-row DML slower, turn bulk DML into row-by-row work, and
surprise the next developer. Prefer constraints, defaults, virtual columns and
package APIs. Auditing of access is better done with Unified Auditing
([3.5](../security/01-security.md)).

## 4. Production recommendations

- One package per business area; table access only through packages for write paths.
- No `COMMIT` inside reusable procedures: the caller owns the transaction.
- Version the package specification like an API. Add, do not change, parameters.
- For zero-downtime PL/SQL releases use Edition-Based Redefinition ([4.9](../database-devops/01-devops.md)).
- Recompile and check for invalid objects as the last step of every deployment.

## 5. Common mistakes

- Functions with side effects called from SQL (they may run more or fewer times than you expect).
- Row triggers that query their own table.
- Privileges granted via roles to the owner of definer-rights code.
- Session state in packages behind a connection pool.
- Dropping and recreating a package instead of `CREATE OR REPLACE`, which loses grants.

## FreshMart example

=== "Scenario"

    Amit (customer 103) has an active cart: 1 Apple and 1 Assam Tea. He checks
    out to his Delhi address from the Delhi warehouse.

=== "PL/SQL"

    ```sql
    SET SERVEROUTPUT ON
    DECLARE
        l_order_id orders.order_id%TYPE;
    BEGIN
        order_pkg.place_order(
            p_cart_id      => 1,
            p_address_id   => 203,
            p_warehouse_id => 3,
            p_order_id     => l_order_id);
        DBMS_OUTPUT.PUT_LINE('Order ' || l_order_id || ' placed');
        COMMIT;
    EXCEPTION
        WHEN order_pkg.e_insufficient_stock THEN
            ROLLBACK;
            DBMS_OUTPUT.PUT_LINE('Cannot place order: ' || SQLERRM);
    END;
    /
    ```

=== "Result"

    ```text
    Cannot place order: ORA-20002: Insufficient stock for Apple Royal Gala 1kg
    ```

    Derived from the sample data: the Delhi warehouse (3) stocks only products
    3, 4, 5 and 12. Change `p_warehouse_id` to 1 and the call succeeds: subtotal
    330, delivery fee 30, total 360, with one unit each reserved in warehouse 1.
    `ROLLBACK` afterwards to keep the sample data unchanged.

=== "Takeaway"

    The caller sees one call and one named exception. The package guarantees
    that stock is reserved, the order written and the cart closed together, or
    not at all, and the caller decides when to commit.

## Check yourself

??? question "Interview questions"
    1. **(Intermediate)** Procedure versus function?
    2. **(Intermediate)** Why use packages instead of standalone procedures?
    3. **(Senior)** What causes `ORA-04091` and how do you fix it? *A row trigger reading or changing its own table; use a compound trigger or move the logic out of triggers.*
    4. **(Senior)** A procedure fails with `ORA-00942` although the owner can query the table interactively. Why? *The privilege comes through a role; definer-rights code ignores roles.*
    5. **(Architect)** How do you deploy a changed package to a system that cannot stop? *Edition-Based Redefinition, or backward-compatible specifications with stateless packages and a rolling application release.*

??? example "Exercises"
    1. Write a function `customer_tier(p_customer_id)` returning GOLD / SILVER / BRONZE.
    2. Add a procedure `order_pkg.mark_packed(p_order_id)` that only allows PLACED → PACKED.
    3. Write a trigger that prevents deleting rows from `audit_log`.

## Related

Next: [2.10 Exceptions, dynamic SQL, advanced](04-exceptions-dynamic-advanced.md).
