---
tags: [stage-2, sql, joins]
---

# 2.1 Joins in depth

!!! abstract "Chapter card"
    **Stage:** 2 · **Prerequisites:** 1.10 · **Time:** 3 hours · **Applies to:** 19c+

## 1. The complete join family

| Join | Returns | Standard? |
|---|---|---|
| `INNER JOIN` | Matching pairs | Standard |
| `LEFT / RIGHT OUTER JOIN` | Matching pairs plus unmatched rows of one side | Standard |
| `FULL OUTER JOIN` | Matching pairs plus unmatched rows of both sides | Standard |
| `CROSS JOIN` | Every pair (Cartesian product) | Standard |
| `NATURAL JOIN` | Equi-join on all same-named columns | Standard; avoid |
| `JOIN ... USING (col)` | Equi-join on named common columns | Standard |
| Self join | A table joined to itself | Technique, not syntax |
| Semi join | Rows of A with at least one match in B | Written as `EXISTS` / `IN` |
| Anti join | Rows of A with no match in B | Written as `NOT EXISTS` / `NOT IN` |
| `CROSS APPLY` / `OUTER APPLY` / `LATERAL` | Right side may reference the left row | 12.1+; `LATERAL` is standard |
| Partitioned outer join | Outer join repeated per partition (gap filling) | Oracle-specific |

## 2. FULL OUTER JOIN

*Which products sold in March but not April, or the reverse?*

```sql
WITH mar AS (
    SELECT DISTINCT oi.product_id
    FROM   order_items oi JOIN orders o ON o.order_id = oi.order_id
    WHERE  o.status <> 'CANCELLED'
    AND    o.order_date >= DATE '2025-03-01' AND o.order_date < DATE '2025-04-01'),
apr AS (
    SELECT DISTINCT oi.product_id
    FROM   order_items oi JOIN orders o ON o.order_id = oi.order_id
    WHERE  o.status <> 'CANCELLED'
    AND    o.order_date >= DATE '2025-04-01' AND o.order_date < DATE '2025-05-01')
SELECT COALESCE(mar.product_id, apr.product_id) AS product_id,
       CASE WHEN apr.product_id IS NULL THEN 'March only'
            WHEN mar.product_id IS NULL THEN 'April only' END AS sold_in
FROM   mar FULL OUTER JOIN apr ON apr.product_id = mar.product_id
WHERE  mar.product_id IS NULL OR apr.product_id IS NULL
ORDER  BY 1;
```

*Result (derived from the sample data):*

| PRODUCT_ID | SOLD_IN |
|---:|---|
| 2 | March only |
| 3 | March only |
| 4 | March only |
| 7 | March only |
| 9 | April only |

## 3. Self join

```sql
SELECT e.employee_name AS employee, m.employee_name AS manager
FROM   employees e
LEFT   JOIN employees m ON m.employee_id = e.manager_id
ORDER  BY e.employee_id;
```

| EMPLOYEE | MANAGER |
|---|---|
| Anita Desai | *(null)* |
| Vikram Rao | Anita Desai |
| Meera Pillai | Anita Desai |
| Arjun Singh | Anita Desai |
| Sunil Kumar | Vikram Rao |
| Fatima Khan | Vikram Rao |
| Ravi Teja | Meera Pillai |
| Pooja Yadav | Arjun Singh |

A self join also finds pairs. *Products frequently bought with Milk (product 5):*

```sql
SELECT p.product_name, COUNT(*) AS times_together
FROM   order_items a
JOIN   order_items b ON b.order_id = a.order_id AND b.product_id <> a.product_id
JOIN   products p    ON p.product_id = b.product_id
WHERE  a.product_id = 5
GROUP  BY p.product_name
ORDER  BY times_together DESC, p.product_name;
```

*Verified: Apple, Basmati Rice, Onion, Tomato and Whole Wheat Bread, once each.*

## 4. CROSS JOIN

Useful when you really want every combination, for example a stock matrix with
zero rows filled in:

```sql
SELECT w.warehouse_name, p.product_name, NVL(i.qty_on_hand, 0) AS qty
FROM   warehouses w
CROSS  JOIN products p
LEFT   JOIN inventory i ON i.warehouse_id = w.warehouse_id AND i.product_id = p.product_id
WHERE  p.category_id = 7
ORDER  BY 1, 2;
```

| WAREHOUSE_NAME | PRODUCT_NAME | QTY |
|---|---|---:|
| Bengaluru South FC | Basmati Rice 5kg | 45 |
| Bengaluru South FC | Wheat Flour 5kg | 20 |
| Delhi NCR FC | Basmati Rice 5kg | 0 |
| Delhi NCR FC | Wheat Flour 5kg | 8 |
| Mumbai Central FC | Basmati Rice 5kg | 30 |
| Mumbai Central FC | Wheat Flour 5kg | 0 |

An accidental cross join shows in a plan as `MERGE JOIN CARTESIAN`. When that
appears unexpectedly, look for a missing join condition or a row estimate of 1.

## 5. NATURAL JOIN and USING

```sql
SELECT order_id, customer_name FROM orders JOIN customers USING (customer_id);
```

`USING` is acceptable. **Do not use `NATURAL JOIN`**: it joins on every column
with the same name. `orders NATURAL JOIN customers` would also match on
`status`, `created_at` and `updated_at`, returning nothing, and adding a column
to either table later can silently change results.

## 6. Semi joins and anti joins

```sql
-- Semi join: customers who have ordered. One row per customer, no duplicates.
SELECT c.customer_name
FROM   customers c
WHERE  EXISTS (SELECT 1 FROM orders o WHERE o.customer_id = c.customer_id);

-- Anti join: products never ordered.
SELECT p.product_name
FROM   products p
WHERE  NOT EXISTS (SELECT 1 FROM order_items oi WHERE oi.product_id = p.product_id);
```

*Verified: 5 customers; Wheat Flour 5kg.*

In a plan these appear as `HASH JOIN SEMI`, `NESTED LOOPS SEMI`,
`HASH JOIN ANTI`. A semi join stops at the first match, which is why `EXISTS`
is better than `JOIN` + `DISTINCT`.

| Form | Null-safe? | Notes |
|---|---|---|
| `EXISTS` / `NOT EXISTS` | Yes | Preferred |
| `IN` | Yes | Equivalent to `EXISTS` for the optimizer |
| `NOT IN` | **No** | Returns nothing if the subquery yields a null; becomes a costlier null-aware anti join (`ANTI NA`) |
| `LEFT JOIN ... WHERE b.key IS NULL` | Yes | Works; intent is less clear |

## 7. LATERAL, CROSS APPLY, OUTER APPLY

A lateral inline view may refer to columns of tables to its left: a
"for each row" join. *The two most recent orders of each customer:*

```sql
SELECT c.customer_name, r.order_id, r.order_date
FROM   customers c
CROSS  APPLY (SELECT o.order_id, o.order_date
              FROM   orders o
              WHERE  o.customer_id = c.customer_id
              ORDER  BY o.order_date DESC
              FETCH  FIRST 2 ROWS ONLY) r
ORDER  BY c.customer_id, r.order_date DESC;
```

| CUSTOMER_NAME | ORDER_ID | ORDER_DATE |
|---|---:|---|
| Rahul Sharma | 1007 | 2025-04-05 |
| Rahul Sharma | 1003 | 2025-03-10 |
| Priya Nair | 1006 | 2025-04-02 |
| Priya Nair | 1002 | 2025-03-03 |
| Amit Verma | 1004 | 2025-03-15 |
| Sneha Iyer | 1005 | 2025-03-18 |
| Karan Mehta | 1008 | 2025-04-08 |

`OUTER APPLY` would also return Neha Gupta with nulls. With
`ix_orders_cust_date` each probe reads two index entries, which makes this
pattern efficient for "top N per parent" when parents are few.

## 8. Non-equi and range joins

```sql
-- Which promotion period does each order fall in?
SELECT o.order_id, o.order_date, p.promotion_name
FROM   orders o
JOIN   promotions p ON o.order_date BETWEEN p.start_date AND p.end_date
WHERE  o.order_id IN (1001, 1007)
ORDER  BY 1, 3;
```

| ORDER_ID | ORDER_DATE | PROMOTION_NAME |
|---:|---|---|
| 1001 | 2025-03-01 | Welcome Offer |
| 1007 | 2025-04-05 | Fresh Savings |
| 1007 | 2025-04-05 | Welcome Offer |

Range joins cannot use a hash join; they run as nested loops or sort-merge and
grow expensive on large inputs.

## 9. Partitioned outer join (data densification)

Reports need a row for every warehouse **and** every month, even when there
were no sales. Oracle's `PARTITION BY` on an outer join repeats the outer join
for each partition:

```sql
WITH months AS (SELECT DATE '2025-03-01' AS m FROM dual UNION ALL
                SELECT DATE '2025-04-01' FROM dual),
     sales AS (SELECT warehouse_id, TRUNC(order_date, 'MM') AS m, SUM(total_amount) AS total
               FROM   orders WHERE status <> 'CANCELLED'
               GROUP  BY warehouse_id, TRUNC(order_date, 'MM'))
SELECT s.warehouse_id, TO_CHAR(months.m, 'YYYY-MM') AS month, NVL(s.total, 0) AS total
FROM   sales s PARTITION BY (s.warehouse_id)
RIGHT  JOIN months ON months.m = s.m
ORDER  BY 1, 2;
```

| WAREHOUSE_ID | MONTH | TOTAL |
|---:|---|---:|
| 1 | 2025-03 | 1063 |
| 1 | 2025-04 | 1129 |
| 2 | 2025-03 | 720 |
| 2 | 2025-04 | 420 |
| 3 | 2025-03 | 356 |
| 3 | 2025-04 | 0 |

## 10. Performance considerations

- **Join order and method** are chosen from row estimates. Wrong estimates produce wrong joins ([2.15](../performance-engineering/01-execution-plans.md)).
- Nested loops need an index on the inner table's join column; hash joins need memory (PGA) and spill to temp when it runs out.
- Declared foreign keys and `NOT NULL` let the optimizer **eliminate joins** to tables you do not select from, which matters for views that join many tables.
- Join on columns of the **same data type**. Joining `NUMBER` to `VARCHAR2` forces a conversion and disables an index.
- :material-tag: **23ai+** `UPDATE ... FROM` and `DELETE ... FROM` allow direct joins in DML.

## 11. Common mistakes

- `NOT IN` against a nullable column.
- Outer join followed by an inner join to a third table through the optional side: the outer join is cancelled.
- Join + `DISTINCT` where a semi join was meant.
- Joining on expressions (`TRUNC(a.dt) = TRUNC(b.dt)`) with no supporting index.

## 12. Check yourself

??? question "Interview questions"
    1. **(Intermediate)** `EXISTS` versus `IN`: which is faster? *The optimizer treats them alike and usually unnests both to a semi join. Choose by clarity. `NOT IN` versus `NOT EXISTS` differ in null semantics.*
    2. **(Intermediate)** What does `CROSS APPLY` give you that a join does not? *The right side can be correlated to the left row, so it can contain `FETCH FIRST`, a table function call or an aggregate per row.*
    3. **(Senior)** What is join elimination and what does it need? *Removing a table from the plan when it cannot change the result: needs a validated (or RELY) foreign key and no columns selected from that table.*
    4. **(Senior)** What does `MERGE JOIN CARTESIAN` in a plan tell you? *Either a missing predicate or the optimizer believes one side returns a single row.*
    5. **(Architect)** A view joins 12 tables and every query against it is slow. Options? *Declare constraints so joins can be eliminated, split into purpose-built views, materialize hot aggregates, and stop using one "universal" view.*

??? example "Exercises"
    1. List every warehouse with its manager's name (job title "Warehouse Manager"), keeping warehouses with none.
    2. Customers who have an ACTIVE cart but no orders. *Neha Gupta (106).*
       ```sql
       SELECT c.customer_name FROM customers c
       WHERE  EXISTS (SELECT 1 FROM carts k WHERE k.customer_id = c.customer_id AND k.status = 'ACTIVE')
       AND    NOT EXISTS (SELECT 1 FROM orders o WHERE o.customer_id = c.customer_id);
       ```
    3. For each product, its most recent review using `OUTER APPLY`.

## 13. Related

Next: [2.2 Subqueries and set operators](02-subqueries-set-operators.md).
