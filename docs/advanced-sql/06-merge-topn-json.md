---
tags: [stage-2, sql, merge, json, pagination]
---

# 2.6 MERGE, Top-N, pagination, JSON

!!! abstract "Chapter card"
    **Stage:** 2 · **Prerequisites:** 2.5 · **Time:** 4 hours · **Applies to:** 19c+ (23ai items marked)

## At a glance

| Subtopic | What it is for |
|---|---|
| `MERGE` | Insert-or-update ("upsert") in one statement |
| Multi-table insert, `RETURNING` | Write to several tables; get values back |
| Top-N and `FETCH FIRST` | "The 5 best ..." |
| Pagination | Page 2 of the product list, efficiently |
| JSON in SQL | Produce, store, query and index JSON |
| Modern SQL shortcuts | 23ai conveniences that shorten everyday SQL |

## 1. MERGE

`MERGE` compares a source to a target and, per row, updates the match or
inserts the miss. Typical use: applying a supplier's price file.

```sql
MERGE INTO products t
USING (SELECT 'DAI-MLK-001' AS sku, 70 AS new_price FROM dual
       UNION ALL
       SELECT 'BAK-BUN-001', 30 FROM dual) s
ON    (t.sku = s.sku)
WHEN MATCHED THEN
    UPDATE SET t.unit_price = s.new_price
    WHERE  t.unit_price <> s.new_price            -- skip no-op updates
WHEN NOT MATCHED THEN
    INSERT (sku, product_name, category_id, supplier_id, unit_price, unit_of_measure)
    VALUES (s.sku, 'Burger Buns 4 pack', 5, 3, s.new_price, 'PACK');
-- 2 rows merged: Milk 68 -> 70, and one new product.
ROLLBACK;
```

Rules and behavior:

- The `ON` columns cannot be updated in the `UPDATE` branch.
- If two source rows match one target row: `ORA-30926: unable to get a stable set of rows`. Deduplicate the source first.
- A `DELETE WHERE` clause inside `WHEN MATCHED` deletes rows it has just updated when the condition holds.
- `MERGE` is one statement, so it is atomic and takes one read-consistent view of the target. It is **not** a concurrency guarantee: two sessions merging the same new key can both take the insert branch, and one fails on the unique constraint. Handle `DUP_VAL_ON_INDEX` and retry.
- Use `LOG ERRORS INTO err$_table REJECT LIMIT UNLIMITED` (table created by `DBMS_ERRLOG`) to skip and record bad rows in bulk loads.

## 2. Multi-table insert and RETURNING

```sql
-- Route rows from one source into several tables in one pass
INSERT ALL
    WHEN total_amount >= 700 THEN INTO big_orders   (order_id, total_amount) VALUES (order_id, total_amount)
    WHEN status = 'CANCELLED' THEN INTO cancel_audit (order_id)               VALUES (order_id)
SELECT order_id, total_amount, status FROM orders;

-- Get changed values back without a second query
UPDATE inventory SET qty_reserved = qty_reserved + 1
WHERE  warehouse_id = 1 AND product_id = 5
RETURNING qty_on_hand - qty_reserved INTO :available;
```

:material-tag: **23ai+** `RETURNING OLD col, NEW col` returns both the previous and the new value.

## 3. Top-N

```sql
SELECT product_name, unit_price
FROM   products
ORDER  BY unit_price DESC
FETCH  FIRST 3 ROWS ONLY;            -- Basmati Rice 650, Wheat Flour 260, Apple 180
```

| Clause | Meaning |
|---|---|
| `FETCH FIRST n ROWS ONLY` | Exactly n rows |
| `FETCH FIRST n ROWS WITH TIES` | n rows plus any that tie with the last |
| `FETCH FIRST 10 PERCENT ROWS ONLY` | A percentage (needs a full count: costly) |
| `OFFSET m ROWS FETCH NEXT n ROWS ONLY` | Skip m, then take n |

For "top N **per group**" use `ROW_NUMBER()` ([2.5](05-window-functions.md)) or
`CROSS APPLY` ([2.1](01-joins.md)).

## 4. Pagination

=== "OFFSET (simple)"

    ```sql
    SELECT product_id, product_name, unit_price
    FROM   products
    WHERE  is_active = 'Y'
    ORDER  BY product_name, product_id
    OFFSET :offset ROWS FETCH NEXT :page_size ROWS ONLY;
    ```

    Page 2 with a page size of 5 (`:offset = 5`) returns the 6th to 10th
    products by name: Full Cream Milk 1L, Onion 1kg, Orange Juice 1L,
    Paneer 200g, Tomato 1kg.

    Cost grows with the offset: to show page 1,000 Oracle still produces and
    discards 999 pages.

=== "Keyset (scales)"

    ```sql
    SELECT product_id, product_name, unit_price
    FROM   products
    WHERE  is_active = 'Y'
    AND    (product_name > :last_name
            OR (product_name = :last_name AND product_id > :last_id))
    ORDER  BY product_name, product_id
    FETCH  FIRST :page_size ROWS ONLY;
    ```

    The client sends the last row it saw. With an index on
    `(product_name, product_id)` every page costs the same. Trade-off: no
    "jump to page 57".

Pagination rules: the `ORDER BY` must be **unique** (add the primary key), or
rows can repeat or vanish between pages; and do not run `COUNT(*)` on every page
request for large results.

## 5. JSON in SQL

Oracle stores JSON in a native `JSON` column (:material-tag: **21c+**) or, on
19c, in `VARCHAR2`/`CLOB`/`BLOB` with an `IS JSON` check constraint.

### Generate JSON from relational data

```sql
SELECT JSON_OBJECT(
           'orderId'  VALUE o.order_id,
           'customer' VALUE c.customer_name,
           'total'    VALUE o.total_amount,
           'items'    VALUE (SELECT JSON_ARRAYAGG(
                                        JSON_OBJECT('product' VALUE p.product_name,
                                                    'qty'     VALUE oi.quantity)
                                        ORDER BY oi.line_no)
                             FROM   order_items oi
                             JOIN   products p ON p.product_id = oi.product_id
                             WHERE  oi.order_id = o.order_id)) AS order_json
FROM   orders o
JOIN   customers c ON c.customer_id = o.customer_id
WHERE  o.order_id = 1002;
```

```json
{"orderId":1002,"customer":"Priya Nair","total":720,
 "items":[{"product":"Basmati Rice 5kg","qty":1},{"product":"Assam Tea 250g","qty":1}]}
```

### Store and query JSON

```sql
CREATE TABLE product_attributes (
    product_id NUMBER(10) PRIMARY KEY REFERENCES products (product_id),
    attrs      JSON                                  -- 19c: CLOB CHECK (attrs IS JSON)
);

INSERT INTO product_attributes VALUES
    (9, '{"brand":"SipWell","organic":false,"nutrition":{"kcal":45,"sugar_g":9},"tags":["juice","breakfast"]}');

SELECT pa.attrs.brand.string()                              AS brand,     -- dot notation
       JSON_VALUE(pa.attrs, '$.nutrition.kcal' RETURNING NUMBER) AS kcal,  -- one scalar
       JSON_QUERY(pa.attrs, '$.tags')                       AS tags       -- object or array
FROM   product_attributes pa
WHERE  JSON_EXISTS(pa.attrs, '$.tags[*]?(@ == "juice")');
```

| BRAND | KCAL | TAGS |
|---|---:|---|
| SipWell | 45 | ["juice","breakfast"] |

| Function | Returns |
|---|---|
| `JSON_VALUE` | One scalar value as a SQL type |
| `JSON_QUERY` | A JSON fragment (object or array) |
| `JSON_EXISTS` | True if the path matches |
| `JSON_TABLE` | Rows and columns from a document (shred arrays) |
| `JSON_OBJECT`, `JSON_ARRAY`, `JSON_OBJECTAGG`, `JSON_ARRAYAGG` | Build JSON |
| `JSON_MERGEPATCH`, `JSON_TRANSFORM` (21c+) | Modify part of a document |
| `JSON_SERIALIZE` | Text (optionally `PRETTY`) from binary JSON |

```sql
-- Shred the tags array into rows
SELECT pa.product_id, jt.tag
FROM   product_attributes pa,
       JSON_TABLE(pa.attrs, '$.tags[*]' COLUMNS (tag VARCHAR2(30) PATH '$')) jt;
-- 9 juice / 9 breakfast
```

### Indexing JSON

| Index | Use |
|---|---|
| Function-based on `JSON_VALUE(...)` | One known scalar path, used in equality or range filters |
| Multivalue index (:material-tag: **21c+**) | Values inside arrays |
| JSON search index | Ad hoc paths and full-text search inside documents |

### When to use JSON in a relational schema

Use it for genuinely variable attributes (product specifications that differ
per category) and for payloads you store as received. Do **not** use it for
data you join on, constrain, or aggregate every day: columns are faster,
typed and enforceable. :material-tag: **23ai+** JSON Relational Duality views
expose normalized tables as updatable documents, removing the need to choose
([4.7](../oracle-26ai/01-oracle-26ai.md)).

## 6. Modern SQL shortcuts :material-tag: **23ai+**

| Feature | Example |
|---|---|
| `SELECT` without `FROM` | `SELECT SYSDATE;` |
| Table value constructor | `SELECT * FROM (VALUES (1,'A'), (2,'B')) t (id, code);` |
| Join in `UPDATE` / `DELETE` | `UPDATE order_items oi SET oi.unit_price = p.unit_price FROM products p WHERE p.product_id = oi.product_id AND ...;` |
| `GROUP BY` alias | `SELECT TO_CHAR(order_date,'YYYY-MM') AS m, COUNT(*) FROM orders GROUP BY m;` |
| `BOOLEAN` | `WHERE is_confirmed` |
| `IF [NOT] EXISTS` | `DROP TABLE IF EXISTS t;` |
| Aggregation over `INTERVAL` | `SUM(delivered_at - shipped_at)` |
| `DEFAULT ON NULL FOR INSERT AND UPDATE` | Column default applied when an update sets null |

On 19c each of these has a longer equivalent shown in the chapter where the
feature belongs. Code that must run on both should avoid them.

## 7. Performance and production notes

- `MERGE` with a join on indexed keys is far faster than a PL/SQL loop of "update, if none then insert".
- `FETCH FIRST` with a matching index gives a `COUNT STOPKEY` / `WINDOW NOSORT STOPKEY` plan that reads only the rows returned.
- Deep `OFFSET` pagination is a common cause of slow APIs; move to keyset.
- `JSON_VALUE` in a `WHERE` clause needs a matching function-based index (same path and `RETURNING` type) to avoid a full scan.

## 8. Common mistakes

- Duplicate keys in the `MERGE` source (`ORA-30926`).
- Believing `MERGE` prevents duplicate inserts under concurrency.
- Paginating on a non-unique sort key.
- `JSON_VALUE` on a path that returns an object or array: it returns null by default. Use `JSON_QUERY`, or add `ERROR ON ERROR` while developing.

## FreshMart example

=== "Scenario"

    The nightly stock feed from each warehouse lists counted quantities. Known
    (warehouse, product) pairs must be updated; new pairs must be created; the
    mobile app then needs each warehouse's five lowest-stock items as JSON.

=== "SQL"

    ```sql
    -- 1. Apply the feed (staged in STOCK_FEED: warehouse_id, product_id, counted_qty)
    MERGE INTO inventory i
    USING stock_feed f
    ON    (i.warehouse_id = f.warehouse_id AND i.product_id = f.product_id)
    WHEN MATCHED THEN
        UPDATE SET i.qty_on_hand = f.counted_qty
        WHERE  i.qty_on_hand <> f.counted_qty
    WHEN NOT MATCHED THEN
        INSERT (warehouse_id, product_id, qty_on_hand, reorder_level)
        VALUES (f.warehouse_id, f.product_id, f.counted_qty, 10);

    -- 2. Lowest available stock for warehouse 1, as one JSON array
    SELECT JSON_ARRAYAGG(
               JSON_OBJECT('product' VALUE product_name, 'available' VALUE available)
               ORDER BY available) AS low_stock
    FROM  (SELECT p.product_name, i.qty_on_hand - i.qty_reserved AS available
           FROM   inventory i JOIN products p ON p.product_id = i.product_id
           WHERE  i.warehouse_id = 1
           ORDER  BY available, p.product_id
           FETCH  FIRST 3 ROWS ONLY);
    ```

=== "Result"

    With the unchanged sample data (no feed applied), step 2 returns:

    ```json
    [{"product":"Paneer 200g","available":15},
     {"product":"Orange Juice 1L","available":25},
     {"product":"Basmati Rice 5kg","available":29}]
    ```

    Derived from the sample data: Paneer 15, Orange Juice 25, Rice 30 - 1 reserved = 29.

=== "Takeaway"

    One `MERGE` replaces a loop of lookups; the `WHERE` in the update branch
    avoids rewriting unchanged rows (less redo, no pointless trigger firing).
    Building JSON in the database returns one row instead of N+1 round trips.

## Check yourself

??? question "Interview questions"
    1. **(Intermediate)** What causes `ORA-30926` in a `MERGE`? *More than one source row matching a target row.*
    2. **(Intermediate)** Offset versus keyset pagination? *Offset is simple but O(offset); keyset is constant cost but sequential only.*
    3. **(Senior)** Is `MERGE` safe as an upsert under concurrency? *No. Concurrent sessions can both insert; rely on the unique constraint and retry.*
    4. **(Senior)** `JSON_VALUE` versus `JSON_QUERY`? *Scalar versus fragment.*
    5. **(Architect)** A team wants to store all order data as one JSON document. Response? *Ask which queries, constraints and reports it must support. Keep relational storage for integrity and analytics and expose documents through generated JSON or duality views.*

??? example "Exercises"
    1. Write a `MERGE` that upserts a review (one per customer and product).
    2. Page 3 (size 4) of orders, newest first, using keyset pagination.
    3. Produce one JSON document per customer with an array of their order ids.

## Related

Next: [2.7 PL/SQL fundamentals](../plsql/01-fundamentals.md).
