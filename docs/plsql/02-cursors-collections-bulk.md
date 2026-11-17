---
tags: [stage-2, plsql, bulk]
---

# 2.8 Cursors, collections, bulk SQL

!!! abstract "Chapter card"
    **Stage:** 2 · **Prerequisites:** 2.7 · **Time:** 5 hours · **Applies to:** 19c+

## At a glance

| Subtopic | In one line |
|---|---|
| Implicit and explicit cursors | A cursor is a handle on a query's result |
| Cursor FOR loop | The simplest safe way to read rows |
| `REF CURSOR` | A cursor you can pass to a client or another program |
| Collections | In-memory arrays: associative arrays, nested tables, VARRAYs |
| `BULK COLLECT` | Fetch many rows in one context switch |
| `FORALL` | Send many DML rows in one context switch |
| Pipelined functions | Produce rows for a query, one at a time |

## 1. Cursors

A **cursor** is a pointer to the private memory area where Oracle processes a
statement. Every SQL statement uses one.

| Kind | Declared by | Typical use |
|---|---|---|
| Implicit | Oracle, for each `SELECT INTO` and DML | Single-row lookups, DML |
| Cursor FOR loop | `FOR r IN (SELECT ...)` | Reading rows, moderate volumes |
| Explicit | `CURSOR c IS ...` then `OPEN` / `FETCH` / `CLOSE` | Fine control, bulk fetch with `LIMIT` |
| Cursor variable | `SYS_REFCURSOR` | Returning a result set to a caller |

### Explicit cursor with a parameter

```sql
DECLARE
    CURSOR c_orders (p_customer_id orders.customer_id%TYPE) IS
        SELECT order_id, order_date, total_amount
        FROM   orders
        WHERE  customer_id = p_customer_id
        ORDER  BY order_date;
    r c_orders%ROWTYPE;
BEGIN
    OPEN c_orders(102);
    LOOP
        FETCH c_orders INTO r;
        EXIT WHEN c_orders%NOTFOUND;
        DBMS_OUTPUT.PUT_LINE(r.order_id || ' ' || TO_CHAR(r.order_date, 'YYYY-MM-DD')
                             || ' ' || r.total_amount);
    END LOOP;
    CLOSE c_orders;
END;
/
```

```text
1002 2025-03-03 720
1006 2025-04-02 420
```

Attributes: `%FOUND`, `%NOTFOUND`, `%ISOPEN`, `%ROWCOUNT`. A cursor's result is
**read-consistent as of `OPEN`**: rows committed by others afterwards are not seen.

The cursor FOR loop does the same in three lines and cannot leak an open cursor.
Prefer it unless you need `BULK COLLECT ... LIMIT`.

### SELECT FOR UPDATE and WHERE CURRENT OF

```sql
CURSOR c IS SELECT * FROM inventory WHERE warehouse_id = 1 FOR UPDATE OF qty_on_hand;
...
UPDATE inventory SET qty_on_hand = qty_on_hand - 1 WHERE CURRENT OF c;
```

`FOR UPDATE` locks the rows at `OPEN`. A `COMMIT` inside the loop releases the
locks and the next fetch fails with `ORA-01002: fetch out of sequence`.

### REF CURSOR

```sql
CREATE OR REPLACE FUNCTION get_customer_orders (p_customer_id IN NUMBER)
    RETURN SYS_REFCURSOR
IS
    l_rc SYS_REFCURSOR;
BEGIN
    OPEN l_rc FOR
        SELECT order_id, order_date, status, total_amount
        FROM   orders
        WHERE  customer_id = p_customer_id
        ORDER  BY order_date DESC;
    RETURN l_rc;            -- the caller fetches and closes it
END;
/
```

JDBC reads it as a `ResultSet`. The **caller** must close it; leaked ref cursors
end in `ORA-01000: maximum open cursors exceeded`.

## 2. Collections

| | Associative array | Nested table | VARRAY |
|---|---|---|---|
| Declaration | `TABLE OF t INDEX BY PLS_INTEGER` or `VARCHAR2(n)` | `TABLE OF t` | `VARRAY(n) OF t` |
| Index | Any integer or string; sparse | 1..n, can become sparse after `DELETE` | 1..n, always dense |
| Size limit | None | None | Fixed maximum |
| Needs constructor / `EXTEND` | No | Yes | Yes |
| Usable as a SQL type / table column | No (PL/SQL only) | Yes (`CREATE TYPE`) | Yes |
| Typical use | Lookup caches, bulk fetch targets | Passing sets to SQL with `TABLE()` | Small fixed lists |

```sql
DECLARE
    TYPE t_price_by_sku IS TABLE OF products.unit_price%TYPE INDEX BY VARCHAR2(30);
    l_prices t_price_by_sku;
    l_sku    VARCHAR2(30);
BEGIN
    FOR r IN (SELECT sku, unit_price FROM products WHERE category_id = 4) LOOP
        l_prices(r.sku) := r.unit_price;
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('Count: ' || l_prices.COUNT);              -- Count: 3
    DBMS_OUTPUT.PUT_LINE('Milk:  ' || l_prices('DAI-MLK-001'));     -- Milk:  68

    l_sku := l_prices.FIRST;                 -- iterate a sparse / string-indexed array
    WHILE l_sku IS NOT NULL LOOP
        DBMS_OUTPUT.PUT_LINE(l_sku || ' = ' || l_prices(l_sku));
        l_sku := l_prices.NEXT(l_sku);
    END LOOP;
END;
/
```

Methods: `COUNT`, `FIRST`, `LAST`, `NEXT(i)`, `PRIOR(i)`, `EXISTS(i)`,
`EXTEND`, `DELETE`, `TRIM`, `LIMIT`. Reading a missing element of an associative
array raises `NO_DATA_FOUND`.

:material-tag: **18c+** qualified expressions build collections inline:
`l_list := t_ids(1 => 101, 2 => 102);`

### Collections in SQL

```sql
CREATE TYPE t_id_list IS TABLE OF NUMBER;
/
-- Bind a whole list to one statement (no dynamic IN-list)
SELECT * FROM products WHERE product_id IN (SELECT column_value FROM TABLE(:id_list));
```

## 3. BULK COLLECT

Fetches many rows into a collection with one context switch.

```sql
DECLARE
    TYPE t_orders IS TABLE OF orders%ROWTYPE;
    l_orders t_orders;
BEGIN
    SELECT * BULK COLLECT INTO l_orders FROM orders WHERE status = 'DELIVERED';
    DBMS_OUTPUT.PUT_LINE(l_orders.COUNT || ' delivered orders');     -- 5 delivered orders
END;
/
```

- `BULK COLLECT` never raises `NO_DATA_FOUND`; an empty result gives `COUNT = 0`.
- Collections live in session memory (PGA). An unbounded `BULK COLLECT` of ten million rows can exhaust it. For unknown volumes, fetch in batches:

```sql
OPEN c;
LOOP
    FETCH c BULK COLLECT INTO l_rows LIMIT 1000;
    EXIT WHEN l_rows.COUNT = 0;          -- not c%NOTFOUND: the last batch may be partial
    -- process l_rows
END LOOP;
CLOSE c;
```

A cursor FOR loop is already array-fetched 100 rows at a time by the compiler
(at `PLSQL_OPTIMIZE_LEVEL` 2 or higher). Explicit `BULK COLLECT` is needed when
you want the rows in a collection, typically to feed `FORALL`.

## 4. FORALL

Sends one DML statement with all the collection's values in a single context switch.

```sql
DECLARE
    TYPE t_ids  IS TABLE OF inventory.product_id%TYPE;
    TYPE t_qtys IS TABLE OF inventory.qty_on_hand%TYPE;
    l_ids  t_ids  := t_ids(1, 2, 5);
    l_qtys t_qtys := t_qtys(10, 20, 30);
BEGIN
    FORALL i IN 1 .. l_ids.COUNT
        UPDATE inventory
        SET    qty_on_hand = qty_on_hand + l_qtys(i)
        WHERE  warehouse_id = 1 AND product_id = l_ids(i);

    DBMS_OUTPUT.PUT_LINE(SQL%ROWCOUNT || ' rows updated');           -- 3 rows updated
    ROLLBACK;
END;
/
```

`FORALL` is not a loop: it holds exactly one DML statement. Per-element row
counts are in `SQL%BULK_ROWCOUNT(i)`.

### Continue past failing rows

```sql
DECLARE
    e_bulk_errors EXCEPTION;
    PRAGMA EXCEPTION_INIT(e_bulk_errors, -24381);
BEGIN
    FORALL i IN 1 .. l_rows.COUNT SAVE EXCEPTIONS
        INSERT INTO reviews VALUES l_rows(i);
EXCEPTION
    WHEN e_bulk_errors THEN
        FOR j IN 1 .. SQL%BULK_EXCEPTIONS.COUNT LOOP
            DBMS_OUTPUT.PUT_LINE('Row ' || SQL%BULK_EXCEPTIONS(j).ERROR_INDEX || ': '
                || SQLERRM(-SQL%BULK_EXCEPTIONS(j).ERROR_CODE));
        END LOOP;
END;
```

For sparse collections use `FORALL i IN INDICES OF l_rows`.

### How much faster

Illustrative, not measured here: moving from row-by-row DML to `FORALL` commonly
gives an order-of-magnitude reduction in elapsed time for tens of thousands of
rows, because the cost removed is the per-row context switch. Measure your own
case with `DBMS_UTILITY.GET_TIME` or SQL trace; and remember that a single
`INSERT ... SELECT` or `MERGE`, when the logic allows it, beats both.

| Approach | Context switches for N rows | Use when |
|---|---|---|
| One SQL statement | 1 | The logic can be expressed in SQL |
| `BULK COLLECT` + `FORALL` | About 2 per batch | Per-row procedural logic is unavoidable |
| Row-by-row loop | 2N | Small N only |

## 5. Pipelined table functions

A pipelined function returns rows as it produces them, so a query can consume
them without the whole set being built in memory.

```sql
CREATE TYPE t_date_tab IS TABLE OF DATE;
/
CREATE OR REPLACE FUNCTION date_range (p_from DATE, p_to DATE)
    RETURN t_date_tab PIPELINED
IS
BEGIN
    FOR i IN 0 .. p_to - p_from LOOP
        PIPE ROW (p_from + i);
    END LOOP;
    RETURN;
END;
/
SELECT column_value AS d FROM TABLE(date_range(DATE '2025-03-01', DATE '2025-03-03'));
-- 2025-03-01, 2025-03-02, 2025-03-03
```

Uses: generators, wrapping complex transformations for ETL, exposing
PL/SQL-computed data to reports. The optimizer guesses the row count of a table
function (a fixed default), which can produce poor join plans; SQL macros
(:material-tag: **21c+**, table macros backported to 19c) avoid that by
expanding into plain SQL.

## 6. Production recommendations

| DO | DON'T |
|---|---|
| Prefer set-based SQL, then bulk PL/SQL | Fetch a row, run three statements, repeat |
| Use `LIMIT` on bulk fetches of unknown size | `BULK COLLECT` an unbounded query |
| Close explicit and ref cursors on every path, including exceptions | Leak cursors |
| Use `SAVE EXCEPTIONS` or DML error logging for loads | Abort a million-row load on one bad row |
| Commit per business unit, with a restart design | Commit every N rows across an open `FOR UPDATE` cursor |

## FreshMart example

=== "Scenario"

    A nightly job reprices products from a staging table `price_updates
    (sku, new_price)`. A price may change by at most 50% in one run; larger
    changes go to a rejects table for a person to review. The file has up to
    200,000 rows.

=== "PL/SQL"

    ```sql
    DECLARE
        CURSOR c IS
            SELECT p.product_id, p.unit_price AS old_price, u.new_price
            FROM   price_updates u
            JOIN   products p ON p.sku = u.sku
            WHERE  p.unit_price <> u.new_price;

        TYPE t_rows IS TABLE OF c%ROWTYPE;
        TYPE t_ids  IS TABLE OF products.product_id%TYPE INDEX BY PLS_INTEGER;
        TYPE t_nums IS TABLE OF NUMBER INDEX BY PLS_INTEGER;

        l_rows    t_rows;
        l_ok_ids  t_ids;   l_ok_prices  t_nums;
        l_bad_ids t_ids;   l_bad_prices t_nums;
    BEGIN
        OPEN c;
        LOOP
            FETCH c BULK COLLECT INTO l_rows LIMIT 1000;
            EXIT WHEN l_rows.COUNT = 0;

            l_ok_ids.DELETE;  l_ok_prices.DELETE;
            l_bad_ids.DELETE; l_bad_prices.DELETE;

            FOR i IN 1 .. l_rows.COUNT LOOP
                IF ABS(l_rows(i).new_price - l_rows(i).old_price) <= 0.5 * l_rows(i).old_price THEN
                    l_ok_ids(l_ok_ids.COUNT + 1)       := l_rows(i).product_id;
                    l_ok_prices(l_ok_prices.COUNT + 1) := l_rows(i).new_price;
                ELSE
                    l_bad_ids(l_bad_ids.COUNT + 1)       := l_rows(i).product_id;
                    l_bad_prices(l_bad_prices.COUNT + 1) := l_rows(i).new_price;
                END IF;
            END LOOP;

            FORALL i IN 1 .. l_ok_ids.COUNT
                UPDATE products SET unit_price = l_ok_prices(i) WHERE product_id = l_ok_ids(i);

            FORALL i IN 1 .. l_bad_ids.COUNT
                INSERT INTO price_update_rejects (product_id, new_price, rejected_at)
                VALUES (l_bad_ids(i), l_bad_prices(i), SYSTIMESTAMP);
        END LOOP;
        CLOSE c;
        COMMIT;      -- one business unit: the whole file
    END;
    /
    ```

=== "Result"

    With a staging table holding `('DAI-MLK-001', 70)` and
    `('STA-RIC-001', 1500)`:

    | Product | Old | New | Outcome |
    |---|---:|---:|---|
    | Full Cream Milk 1L | 68 | 70 | Updated (change of 2.9%) |
    | Basmati Rice 5kg | 650 | 1500 | Rejected (change of 131%) |

    Illustrative: staging and rejects tables are not part of the installed schema.

=== "Takeaway"

    Batches of 1,000 keep memory flat; two `FORALL` statements per batch replace
    up to 1,000 single-row statements. And note the honest alternative: this
    particular rule fits in SQL (`MERGE` with a `WHERE`, plus one
    `INSERT ... SELECT` for rejects). Use the bulk pattern when the per-row rule
    truly needs procedural code.

## Check yourself

??? question "Interview questions"
    1. **(Intermediate)** Implicit versus explicit cursor?
    2. **(Intermediate)** The three collection types and one use for each?
    3. **(Senior)** Why `EXIT WHEN l_rows.COUNT = 0` and not `c%NOTFOUND` with `LIMIT`? *`%NOTFOUND` becomes true on the last partial batch, which would be skipped.*
    4. **(Senior)** What does `SAVE EXCEPTIONS` do? *Lets `FORALL` continue past failed elements and raises ORA-24381 at the end with details in `SQL%BULK_EXCEPTIONS`.*
    5. **(Architect)** A batch job commits every 500 rows "to avoid undo problems" and cannot restart cleanly. Redesign? *Make each commit unit a business unit, record progress in a control table so reruns are idempotent, size undo for the workload, and prefer one set-based statement where possible.*

??? example "Exercises"
    1. Bulk collect all product names into a nested table and print the count. *12.*
    2. Use `FORALL` to insert three rows into `audit_log` from collections.
    3. Write a pipelined function returning the low-stock rows of a given warehouse.

## Related

Next: [2.9 Procedures, packages, triggers](03-subprograms-packages-triggers.md).
