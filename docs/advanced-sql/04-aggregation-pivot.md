---
tags: [stage-2, sql, aggregation]
---

# 2.4 Advanced aggregation and PIVOT

!!! abstract "Chapter card"
    **Stage:** 2 · **Prerequisites:** 1.10 · **Time:** 3 hours · **Applies to:** 19c+

All results in this chapter use non-cancelled orders. Base figures (verified):

| Warehouse | March 2025 | April 2025 | Total |
|---|---:|---:|---:|
| 1 Mumbai Central FC | 1063 | 1129 | 2192 |
| 2 Bengaluru South FC | 720 | 420 | 1140 |
| 3 Delhi NCR FC | 356 | | 356 |
| **Total** | **2139** | **1549** | **3688** |

## 1. ROLLUP: subtotals and a grand total

`ROLLUP(a, b)` groups by `(a, b)`, then `(a)`, then `()`.

```sql
SELECT warehouse_id,
       TO_CHAR(order_date, 'YYYY-MM') AS month,
       SUM(total_amount)              AS total
FROM   orders
WHERE  status <> 'CANCELLED'
GROUP  BY ROLLUP (warehouse_id, TO_CHAR(order_date, 'YYYY-MM'))
ORDER  BY warehouse_id, month;
```

| WAREHOUSE_ID | MONTH | TOTAL |
|---:|---|---:|
| 1 | 2025-03 | 1063 |
| 1 | 2025-04 | 1129 |
| 1 | *(null)* | 2192 |
| 2 | 2025-03 | 720 |
| 2 | 2025-04 | 420 |
| 2 | *(null)* | 1140 |
| 3 | 2025-03 | 356 |
| 3 | *(null)* | 356 |
| *(null)* | *(null)* | 3688 |

The nulls mark subtotal rows. Since a real column value could also be null, use
`GROUPING()` to tell them apart:

```sql
SELECT CASE GROUPING(warehouse_id) WHEN 1 THEN 'ALL' ELSE TO_CHAR(warehouse_id) END AS warehouse,
       ...
```

`GROUPING(col)` returns 1 when the row is a subtotal over that column.
`GROUPING_ID(a, b)` packs the flags into one number (0 detail, 1 subtotal by a,
3 grand total).

## 2. CUBE: every combination

`CUBE(a, b)` groups by `(a, b)`, `(a)`, `(b)` and `()`. It adds the per-month
totals that `ROLLUP` did not produce: 2025-03 → 2139, 2025-04 → 1549. With `n`
columns `CUBE` produces 2^n^ groupings, so keep `n` small.

## 3. GROUPING SETS: exactly the groupings you want

```sql
SELECT warehouse_id,
       TO_CHAR(order_date, 'YYYY-MM') AS month,
       SUM(total_amount)              AS total
FROM   orders
WHERE  status <> 'CANCELLED'
GROUP  BY GROUPING SETS ((warehouse_id), (TO_CHAR(order_date, 'YYYY-MM')), ())
ORDER  BY warehouse_id, month;
```

| WAREHOUSE_ID | MONTH | TOTAL |
|---:|---|---:|
| 1 | *(null)* | 2192 |
| 2 | *(null)* | 1140 |
| 3 | *(null)* | 356 |
| *(null)* | 2025-03 | 2139 |
| *(null)* | 2025-04 | 1549 |
| *(null)* | *(null)* | 3688 |

One pass over the table replaces three queries glued with `UNION ALL`.

## 4. PIVOT: rows to columns

```sql
SELECT *
FROM  (SELECT warehouse_id,
              TO_CHAR(order_date, 'YYYY-MM') AS month,
              total_amount
       FROM   orders
       WHERE  status <> 'CANCELLED')
PIVOT (SUM(total_amount) FOR month IN ('2025-03' AS mar_2025, '2025-04' AS apr_2025))
ORDER  BY warehouse_id;
```

| WAREHOUSE_ID | MAR_2025 | APR_2025 |
|---:|---:|---:|
| 1 | 1063 | 1129 |
| 2 | 720 | 420 |
| 3 | 356 | *(null)* |

How it works: every column of the source that is **not** named in the `PIVOT`
clause becomes an implicit `GROUP BY` column. That is why the inline view
selects only the three columns needed; selecting `*` from `orders` would group
by `order_id` and return one row per order.

The `IN` list must be literal. For a column list not known in advance, generate
the statement with dynamic SQL, or return rows and pivot in the reporting tool.

The portable equivalent is conditional aggregation:

```sql
SELECT warehouse_id,
       SUM(CASE WHEN TO_CHAR(order_date, 'YYYY-MM') = '2025-03' THEN total_amount END) AS mar_2025,
       SUM(CASE WHEN TO_CHAR(order_date, 'YYYY-MM') = '2025-04' THEN total_amount END) AS apr_2025
FROM   orders
WHERE  status <> 'CANCELLED'
GROUP  BY warehouse_id;
```

## 5. UNPIVOT: columns to rows

```sql
SELECT order_id, component, amount
FROM   orders
UNPIVOT (amount FOR component IN (subtotal, discount_amount, delivery_fee))
WHERE  order_id = 1002;
```

| ORDER_ID | COMPONENT | AMOUNT |
|---:|---|---:|
| 1002 | SUBTOTAL | 800 |
| 1002 | DISCOUNT_AMOUNT | 80 |
| 1002 | DELIVERY_FEE | 0 |

`UNPIVOT` drops null values unless you write `UNPIVOT INCLUDE NULLS`.

## 6. LISTAGG: string aggregation

```sql
SELECT o.order_id,
       LISTAGG(p.product_name, ', ') WITHIN GROUP (ORDER BY oi.line_no) AS products
FROM   orders o
JOIN   order_items oi ON oi.order_id  = o.order_id
JOIN   products p     ON p.product_id = oi.product_id
WHERE  o.customer_id = 102
GROUP  BY o.order_id
ORDER  BY o.order_id;
```

| ORDER_ID | PRODUCTS |
|---:|---|
| 1002 | Basmati Rice 5kg, Assam Tea 250g |
| 1006 | Apple Royal Gala 1kg, Orange Juice 1L, Whole Wheat Bread 400g |

| Variant | Release | Purpose |
|---|---|---|
| `LISTAGG(x, ',' ON OVERFLOW TRUNCATE '...' WITH COUNT)` | 12.2+ | Avoid `ORA-01489` when the result exceeds the `VARCHAR2` limit |
| `LISTAGG(DISTINCT x, ',')` | 19c+ | Remove duplicates |
| `JSON_ARRAYAGG`, `XMLAGG` | | When the result may be large: they can return a `CLOB` |

## 7. Other aggregate tools

| Feature | Example | Use |
|---|---|---|
| `COUNT(DISTINCT x)` | `COUNT(DISTINCT customer_id)` | Exact distinct count (5 customers have orders) |
| `APPROX_COUNT_DISTINCT(x)` | | Much faster on huge data, about 2% error (12.1+) |
| `MIN(x) KEEP (DENSE_RANK FIRST ORDER BY y)` | See below | "The x of the row with the smallest y" |
| `MEDIAN`, `PERCENTILE_CONT`, `STDDEV`, `VARIANCE` | | Statistics |
| `ANY_VALUE(x)` | | A value from the group without the cost of `MIN`/`MAX` (19c+) |
| `SUM(x) FILTER (WHERE ...)` | | Standard filtered aggregate; reported for :material-tag: **26ai** release updates. Earlier: `SUM(CASE WHEN ... THEN x END)` |
| `GROUP BY` alias or position | `GROUP BY month` | :material-tag: **23ai+** (position needs `group_by_position_enabled`) |

### FIRST / LAST (KEEP)

*Best-selling product name per category.* Aggregate per product first, then keep the top row per category:

```sql
WITH prod AS (
    SELECT p.category_id, p.product_name, SUM(oi.line_total) AS revenue
    FROM   order_items oi
    JOIN   orders o   ON o.order_id   = oi.order_id
    JOIN   products p ON p.product_id = oi.product_id
    WHERE  o.status <> 'CANCELLED'
    GROUP  BY p.category_id, p.product_name)
SELECT category_id,
       MAX(product_name) KEEP (DENSE_RANK FIRST ORDER BY revenue DESC) AS top_product,
       MAX(revenue)                                                    AS top_revenue
FROM   prod
GROUP  BY category_id
ORDER  BY category_id;
```

*Verified result:*

| CATEGORY_ID | TOP_PRODUCT | TOP_REVENUE |
|---:|---|---:|
| 2 | Apple Royal Gala 1kg | 540 |
| 3 | Tomato 1kg | 120 |
| 4 | Full Cream Milk 1L | 476 |
| 5 | Whole Wheat Bread 400g | 180 |
| 6 | Assam Tea 250g | 300 |
| 7 | Basmati Rice 5kg | 1300 |

## 8. Performance considerations

- `ROLLUP`, `CUBE` and `GROUPING SETS` scan the data once; the equivalent `UNION ALL` scans once per grouping.
- Aggregation uses `HASH GROUP BY` (no order) or `SORT GROUP BY`. Never rely on `GROUP BY` to sort output.
- Large aggregations need PGA work area memory and spill to the temporary tablespace when it runs out.
- Frequently run summaries over large tables are candidates for materialized views with query rewrite ([2.14](../database-objects/01-database-objects.md)) or the In-Memory column store ([4.4](../performance-engineering/04-scalability-features.md)).

## 9. Common mistakes

- Reading subtotal nulls as data. Use `GROUPING()`.
- `PIVOT` over `SELECT *`, which groups by every other column.
- `LISTAGG` overflow in production because test data was small.
- `COUNT(DISTINCT)` on several columns in one query forcing multiple sorts on very large sets.
- Filtering in `HAVING` what belongs in `WHERE`.

## 10. Check yourself

??? question "Interview questions"
    1. **(Intermediate)** `ROLLUP` versus `CUBE`? *ROLLUP gives hierarchical subtotals (n+1 groupings); CUBE gives all 2^n combinations.*
    2. **(Intermediate)** How do you distinguish a subtotal null from a data null? *`GROUPING()` / `GROUPING_ID()`.*
    3. **(Senior)** How do you pivot when the column values are not known in advance? *Dynamic SQL that builds the `IN` list (with validated values), a polymorphic table function, or pivot in the client.*
    4. **(Senior)** What does `KEEP (DENSE_RANK FIRST ...)` do? *Restricts the aggregate to the rows ranked first by another ordering.*
    5. **(Architect)** A dashboard runs twenty `GROUP BY` queries on a 2-billion-row table every minute. Options? *Materialized view with fast refresh, In-Memory column store, a reporting replica (Active Data Guard), or a purpose-built mart. Decide by freshness needs and licence cost.*

??? example "Exercises"
    1. Orders and total by status, with a grand total row labelled "ALL". *Grand total: 8 orders, 3958.*
    2. Pivot successful payment amounts by method into columns. *UPI 1063, CARD 1456, WALLET 420, NETBANKING 393 (verified).*
    3. For each customer, a comma-separated list of distinct products bought (19c+).

## 11. Related

Next: [2.5 Window functions](05-window-functions.md).
