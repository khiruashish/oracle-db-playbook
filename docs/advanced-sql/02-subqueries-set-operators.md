---
tags: [stage-2, sql, subqueries]
---

# 2.2 Subqueries and set operators

!!! abstract "Chapter card"
    **Stage:** 2 · **Prerequisites:** 2.1 · **Time:** 3 hours · **Applies to:** 19c+

## At a glance

A subquery is a query inside a statement; set operators combine the results of whole queries.

| Subtopic | In one line |
|---|---|
| Scalar, row, multi-row subqueries | One value, one row, many rows |
| ANY and ALL | Comparing with a set |
| Correlated subqueries | Depend on the outer row; usually unnested |
| Inline views | A subquery as a table |
| UNION, UNION ALL, INTERSECT, MINUS | Combining result sets |
| Choosing a form | EXISTS, joins, window functions, CTEs |

## 1. Kinds of subquery

| Kind | Returns | Where it goes |
|---|---|---|
| **Scalar** | One row, one column | Anywhere a value is allowed |
| **Row** | One row, several columns | `WHERE (a, b) = (SELECT ...)` |
| **Multi-row** | Many rows, one column | With `IN`, `ANY`, `ALL` |
| **Inline view** | A table | In `FROM` |
| **Correlated** | Depends on the outer row | Re-evaluated (logically) per outer row |

## 2. Scalar and multi-row subqueries

```sql
-- Orders above the average order value (average is 494.75)
SELECT order_id, total_amount
FROM   orders
WHERE  total_amount > (SELECT AVG(total_amount) FROM orders)
ORDER  BY order_id;
```

*Verified result:*

| ORDER_ID | TOTAL_AMOUNT |
|---:|---:|
| 1001 | 639 |
| 1002 | 720 |
| 1007 | 736 |

A scalar subquery that returns more than one row raises `ORA-01427`. If it
returns no row, its value is `NULL`.

### ANY and ALL

```sql
-- Dearer than EVERY dairy product (dairy prices: 68, 84, 95)
SELECT product_name, unit_price FROM products
WHERE  unit_price > ALL (SELECT unit_price FROM products WHERE category_id = 4);
-- 5 rows: Apple 180, Orange Juice 120, Assam Tea 150, Basmati Rice 650, Wheat Flour 260

-- Dearer than AT LEAST ONE dairy product (that is, above 68)
SELECT COUNT(*) FROM products
WHERE  unit_price > ANY (SELECT unit_price FROM products WHERE category_id = 4);
-- 7
```

`> ALL` means greater than the maximum; `> ANY` means greater than the minimum.
`= ANY` is the same as `IN`. If the subquery is empty, `ALL` is true for every
row and `ANY` is false: write `> (SELECT MAX(...))` when that is what you mean,
but note it yields null (no rows) on an empty set.

### Multi-column comparison

```sql
-- The stock rows with the largest quantity in each warehouse
SELECT warehouse_id, product_id, qty_on_hand
FROM   inventory
WHERE  (warehouse_id, qty_on_hand) IN (SELECT warehouse_id, MAX(qty_on_hand)
                                       FROM   inventory GROUP BY warehouse_id)
ORDER  BY warehouse_id;
```

| WAREHOUSE_ID | PRODUCT_ID | QTY_ON_HAND |
|---:|---:|---:|
| 1 | 5 | 200 |
| 2 | 1 | 60 |
| 3 | 4 | 110 |

## 3. Correlated subqueries

```sql
-- Each customer's most recent order
SELECT o.customer_id, o.order_id, o.order_date
FROM   orders o
WHERE  o.order_date = (SELECT MAX(o2.order_date)
                       FROM   orders o2
                       WHERE  o2.customer_id = o.customer_id)
ORDER  BY o.customer_id;
```

| CUSTOMER_ID | ORDER_ID | ORDER_DATE |
|---:|---:|---|
| 101 | 1007 | 2025-04-05 |
| 102 | 1006 | 2025-04-02 |
| 103 | 1004 | 2025-03-15 |
| 104 | 1005 | 2025-03-18 |
| 105 | 1008 | 2025-04-08 |

### How Oracle really runs them

The phrase "executed once per outer row" describes the *meaning*, not the plan.
The optimizer applies **query transformations**:

| Transformation | Effect |
|---|---|
| **Subquery unnesting** | Turns `IN` / `EXISTS` into a semi join, `NOT EXISTS` into an anti join, and correlated aggregates into a join with a grouped view |
| **View merging** | Merges an inline view into the outer query so joins can be reordered |
| **Predicate pushing** | Pushes outer filters into a view that cannot be merged |
| **Scalar subquery caching** | Remembers results per distinct input value within one execution |

When unnesting is not possible, the plan shows a `FILTER` operation that does
run the subquery repeatedly (once per distinct correlation value, thanks to
caching).

### Scalar subqueries in the select list

```sql
SELECT c.customer_name,
       (SELECT COUNT(*) FROM orders o WHERE o.customer_id = c.customer_id) AS orders
FROM   customers c;
```

Convenient for one value. For several values from the same child table, use a
join to a grouped inline view or `OUTER APPLY`, otherwise each subquery visits
the child table separately.

## 4. Inline views

```sql
SELECT c.customer_name, s.net_spend
FROM   customers c
JOIN  (SELECT customer_id, SUM(total_amount) AS net_spend
       FROM   orders WHERE status <> 'CANCELLED'
       GROUP  BY customer_id) s ON s.customer_id = c.customer_id
ORDER  BY s.net_spend DESC;
```

*Verified result:*

| CUSTOMER_NAME | NET_SPEND |
|---|---:|
| Rahul Sharma | 1799 |
| Priya Nair | 1140 |
| Karan Mehta | 393 |
| Amit Verma | 356 |

Sneha is absent (her only order was cancelled) and so is Neha (no orders).

## 5. Set operators

Set operators combine the results of whole queries. The queries must return the
same number of columns with compatible types; column names come from the first.

| Operator | Result | Duplicates |
|---|---|---|
| `UNION` | Rows in either | Removed (needs a sort or hash) |
| `UNION ALL` | Rows in either | Kept (cheapest) |
| `INTERSECT` | Rows in both | Removed |
| `MINUS` | Rows in the first but not the second | Removed |
| `EXCEPT` | Same as `MINUS` (standard spelling) | :material-tag: **21c+** |
| `INTERSECT ALL`, `MINUS ALL`, `EXCEPT ALL` | Multiset versions | :material-tag: **21c+** |

```sql
SELECT customer_id FROM orders WHERE order_date <  DATE '2025-04-01'   -- March: 101,102,103,104
INTERSECT
SELECT customer_id FROM orders WHERE order_date >= DATE '2025-04-01';  -- April: 101,102,105
```

| Operator between the two queries | Result |
|---|---|
| `INTERSECT` | 101, 102 (ordered in both months) |
| `MINUS` | 103, 104 (March only) |
| `UNION` | 101, 102, 103, 104, 105 |
| `UNION ALL` | 8 rows (one per order) |

Rules to remember:

- Set operators treat **nulls as equal** to each other, unlike `=`.
- `ORDER BY` is allowed once, at the very end.
- Precedence: Oracle evaluates set operators left to right; the standard gives `INTERSECT` higher precedence. Use parentheses when mixing them.
- Use `UNION ALL` unless you need duplicate removal. `UNION` on large sets is a common hidden sort.

### Data reconciliation with set operators

```sql
-- Rows that differ between a table and its copy (run both directions)
(SELECT * FROM products MINUS SELECT * FROM products_copy)
UNION ALL
(SELECT * FROM products_copy MINUS SELECT * FROM products);
```

## 6. Choosing between forms

| Need | Prefer |
|---|---|
| Existence test | `EXISTS` |
| Non-existence | `NOT EXISTS` |
| One aggregate per outer row | Scalar subquery or grouped join |
| Top N per group | Window function ([2.5](05-window-functions.md)) or `CROSS APPLY` |
| Compare with a group statistic | Window function avoids a second visit of the table |
| Reuse a derived result several times | CTE ([2.3](03-cte-hierarchical.md)) |

The correlated "most recent order" query above reads `orders` twice. The
analytic version reads it once:

```sql
SELECT customer_id, order_id, order_date
FROM  (SELECT o.*, RANK() OVER (PARTITION BY customer_id ORDER BY order_date DESC) AS rk
       FROM   orders o)
WHERE  rk = 1;
```

## 7. Common mistakes

- Scalar subquery returning several rows (`ORA-01427`) because a uniqueness assumption was wrong.
- `NOT IN` with nullable results.
- `UNION` where `UNION ALL` is correct and cheaper.
- A correlated subquery that references the wrong alias and silently becomes uncorrelated. Always qualify columns.
- `ORDER BY` inside a subquery expecting it to order the outer result.

## FreshMart example

=== "Scenario"

    Marketing wants to promote dairy to customers who buy staples (rice, flour) but have never bought anything from Dairy and Eggs.

=== "SQL"

    ```sql
    SELECT c.customer_id, c.customer_name
    FROM   customers c
    WHERE  EXISTS (SELECT 1
                   FROM   orders o
                   JOIN   order_items oi ON oi.order_id  = o.order_id
                   JOIN   products p     ON p.product_id = oi.product_id
                   WHERE  o.customer_id = c.customer_id
                   AND    o.status <> 'CANCELLED' AND p.category_id = 7)
    AND    NOT EXISTS (SELECT 1
                   FROM   orders o
                   JOIN   order_items oi ON oi.order_id  = o.order_id
                   JOIN   products p     ON p.product_id = oi.product_id
                   WHERE  o.customer_id = c.customer_id
                   AND    o.status <> 'CANCELLED' AND p.category_id = 4);
    ```

=== "Result"

    | CUSTOMER_ID | CUSTOMER_NAME |
    |---:|---|
    | 102 | Priya Nair |

    Derived from the sample data: staples were bought by 101 and 102; dairy by
    101, 103 and 105.

=== "Takeaway"

    One semi join and one anti join state the business sentence directly, return each customer once, and are safe with nulls. The same question as two set queries: staples buyers `MINUS` dairy buyers.

## 8. Check yourself

??? question "Interview questions"
    1. **(Intermediate)** `UNION` versus `UNION ALL`?
    2. **(Intermediate)** What is a correlated subquery? Is it always slow? *It refers to the outer query; no, it is usually unnested into a join.*
    3. **(Senior)** What does a `FILTER` operation with two children mean in a plan? *The subquery could not be unnested and runs as a per-row probe.*
    4. **(Senior)** How do you find the second-highest order total? *`DENSE_RANK() = 2`, or `MAX(total) WHERE total < (SELECT MAX(total) ...)`. Result here: 720.*
    5. **(Architect)** How would you reconcile two billion-row tables across databases? *Not with `MINUS` over a database link. Compare hashes per key range or partition (`STANDARD_HASH`, `ORA_HASH` aggregates), then drill into mismatching ranges; or use GoldenGate Veridata.*

??? example "Exercises"
    1. Products priced above their category's average.
       ```sql
       SELECT p.product_name, p.unit_price FROM products p
       WHERE  p.unit_price > (SELECT AVG(p2.unit_price) FROM products p2
                              WHERE p2.category_id = p.category_id);
       ```
       *Apple (category average 120), Tomato (37.5), Eggs and Paneer (82.33), Assam Tea (135), Basmati Rice (455).*
    2. Customers who reviewed a product they never bought. *None in the sample data; verify with `NOT EXISTS`.*
    3. Cities that have customers but no warehouse, using `MINUS`. *None: Mumbai, Bengaluru and Delhi all have warehouses.*

## 9. Related

Next: [2.3 CTEs and hierarchical queries](03-cte-hierarchical.md).
