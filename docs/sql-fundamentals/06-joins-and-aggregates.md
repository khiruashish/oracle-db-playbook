---
tags: [stage-1, sql, joins, aggregation]
---

# 1.10 Basic joins and aggregates

!!! abstract "Chapter card"
    **Stage:** 1 · **Prerequisites:** 1.5, 1.6 · **Time:** 4 hours · **Applies to:** 19c+

## 1. Overview

Normalization splits facts across tables. A **join** puts them back together for
a question. **Aggregation** summarizes many rows into totals, counts and averages.

## 2. INNER JOIN

Returns the combinations of rows from two tables where the join condition is true.

```sql
SELECT o.order_id, c.customer_name, o.total_amount
FROM   orders o
JOIN   customers c ON c.customer_id = o.customer_id
WHERE  o.order_date < DATE '2025-03-12'
ORDER  BY o.order_id;
```

*Verified result:*

| ORDER_ID | CUSTOMER_NAME | TOTAL_AMOUNT |
|---:|---|---:|
| 1001 | Rahul Sharma | 639 |
| 1002 | Priya Nair | 720 |
| 1003 | Rahul Sharma | 424 |

`o` and `c` are **table aliases**. Qualify every column with its alias once a
query has more than one table: it is clearer and it survives a column with the
same name being added to another table later.

### How to think about it

For each order row, find the customer row with the same `customer_id`. Because
`orders.customer_id` is a foreign key to the primary key of `customers`, each
order matches exactly one customer, so the join returns one row per order.

**The row-count rule:** joining from the "many" side to the "one" side keeps the
row count. Joining from "one" to "many" multiplies rows.

### Joining more tables

```sql
SELECT o.order_id, p.product_name, oi.quantity, oi.line_total
FROM   orders o
JOIN   order_items oi ON oi.order_id  = o.order_id
JOIN   products p     ON p.product_id = oi.product_id
WHERE  o.order_id = 1003
ORDER  BY oi.line_no;
```

| ORDER_ID | PRODUCT_NAME | QUANTITY | LINE_TOTAL |
|---:|---|---:|---:|
| 1003 | Banana Robusta 1 dozen | 2 | 120 |
| 1003 | Eggs 12 pack | 1 | 84 |
| 1003 | Paneer 200g | 2 | 190 |

## 3. LEFT OUTER JOIN

Keeps every row of the left table. Where no match exists, the right table's
columns are `NULL`.

```sql
SELECT c.customer_name, o.order_id
FROM   customers c
LEFT   JOIN orders o ON o.customer_id = c.customer_id
WHERE  c.city = 'Delhi';
```

| CUSTOMER_NAME | ORDER_ID |
|---|---:|
| Amit Verma | 1004 |
| Neha Gupta | *(null)* |

An inner join would drop Neha, who has no orders.

!!! warning "A WHERE on the outer table cancels the outer join"
    ```sql
    -- Intends "all customers with their DELIVERED orders".
    -- The WHERE removes rows where o.status is NULL: it behaves as an inner join.
    SELECT c.customer_name, o.order_id
    FROM   customers c LEFT JOIN orders o ON o.customer_id = c.customer_id
    WHERE  o.status = 'DELIVERED';

    -- Correct: the filter belongs to the join condition.
    SELECT c.customer_name, o.order_id
    FROM   customers c
    LEFT   JOIN orders o ON o.customer_id = c.customer_id AND o.status = 'DELIVERED';
    ```
    The first returns 5 rows (delivered orders only). The second returns 8:
    those 5, plus Amit, Sneha and Neha with a null order.

`RIGHT JOIN` is a left join with the tables swapped. `FULL OUTER JOIN` keeps
unmatched rows from both sides. Details in [2.1](../advanced-sql/01-joins.md).

### Old Oracle join syntax

You will meet this in legacy code:

```sql
SELECT c.customer_name, o.order_id
FROM   customers c, orders o
WHERE  o.customer_id (+) = c.customer_id;     -- (+) marks the side that may be missing
```

It works, but write ANSI joins: the join condition cannot be forgotten, and
`FULL OUTER JOIN` cannot be expressed with `(+)`.

## 4. Aggregates and GROUP BY

`GROUP BY` puts rows with the same values into one group; aggregate functions
then return one value per group.

```sql
SELECT status,
       COUNT(*)          AS orders,
       SUM(total_amount) AS total
FROM   orders
GROUP  BY status
ORDER  BY status;
```

*Verified result:*

| STATUS | ORDERS | TOTAL |
|---|---:|---:|
| CANCELLED | 1 | 270 |
| DELIVERED | 5 | 2596 |
| PLACED | 1 | 736 |
| SHIPPED | 1 | 356 |

**The GROUP BY rule:** every column in the select list must either be in
`GROUP BY` or be inside an aggregate function. Otherwise:
`ORA-00979: not a GROUP BY expression`.

### HAVING filters groups

```sql
SELECT city, COUNT(*) AS customers
FROM   customers
GROUP  BY city
HAVING COUNT(*) >= 2
ORDER  BY customers DESC;
```

| CITY | CUSTOMERS |
|---|---:|
| Mumbai | 3 |
| Delhi | 2 |

Put row conditions in `WHERE` (applied before grouping, cheaper) and only
aggregate conditions in `HAVING`.

## 5. Joins and aggregates together

The query from the introduction of this playbook:

```sql
SELECT c.customer_id,
       c.customer_name,
       COUNT(o.order_id) AS total_orders
FROM   customers c
LEFT   JOIN orders o ON o.customer_id = c.customer_id
GROUP  BY c.customer_id, c.customer_name
ORDER  BY total_orders DESC, c.customer_id;
```

*Verified result:*

| CUSTOMER_ID | CUSTOMER_NAME | TOTAL_ORDERS |
|---:|---|---:|
| 101 | Rahul Sharma | 3 |
| 102 | Priya Nair | 2 |
| 103 | Amit Verma | 1 |
| 104 | Sneha Iyer | 1 |
| 105 | Karan Mehta | 1 |
| 106 | Neha Gupta | 0 |

Column by column: `customer_id` and `customer_name` identify the group;
`total_orders` counts non-null `order_id` values in the group. Using
`COUNT(o.order_id)` rather than `COUNT(*)` is essential: Neha's group has one
row (all nulls from the outer join), so `COUNT(*)` would report 1.

### Revenue by product

```sql
SELECT p.product_name,
       SUM(oi.quantity)   AS units_sold,
       SUM(oi.line_total) AS revenue
FROM   order_items oi
JOIN   orders o   ON o.order_id   = oi.order_id
JOIN   products p ON p.product_id = oi.product_id
WHERE  o.status <> 'CANCELLED'
GROUP  BY p.product_name
ORDER  BY revenue DESC
FETCH  FIRST 5 ROWS ONLY;
```

*Verified result:*

| PRODUCT_NAME | UNITS_SOLD | REVENUE |
|---|---:|---:|
| Basmati Rice 5kg | 2 | 1300 |
| Apple Royal Gala 1kg | 3 | 540 |
| Full Cream Milk 1L | 7 | 476 |
| Assam Tea 250g | 2 | 300 |
| Eggs 12 pack | 3 | 252 |

## 6. The fan-out trap

Joining a parent to **two** child tables multiplies rows and inflates sums.

```sql
-- WRONG: order 1007 has 2 item lines and 2 payment rows -> 4 joined rows.
SELECT o.order_id, SUM(oi.line_total) AS items, SUM(p.amount) AS paid
FROM   orders o
JOIN   order_items oi ON oi.order_id = o.order_id
JOIN   payments p     ON p.order_id  = o.order_id
WHERE  o.order_id = 1007
GROUP  BY o.order_id;
-- items = 1572 (should be 786), paid = 2944 (should be 1472)

-- RIGHT: aggregate each child separately, then join.
SELECT o.order_id, i.items, p.paid
FROM   orders o
JOIN  (SELECT order_id, SUM(line_total) AS items FROM order_items GROUP BY order_id) i
       ON i.order_id = o.order_id
JOIN  (SELECT order_id, SUM(amount) AS paid FROM payments GROUP BY order_id) p
       ON p.order_id = o.order_id
WHERE  o.order_id = 1007;
-- items = 786, paid = 1472
```

Whenever a total looks too large, count the rows before aggregating.

## 7. How Oracle executes joins (first look)

The optimizer chooses a **join method** based on estimated row counts:

| Method | Idea | Good when |
|---|---|---|
| Nested loops | For each row of A, look up matches in B through an index | Few rows from A, index on B |
| Hash join | Build a hash table of the smaller input, probe with the larger | Many rows, equality join |
| Sort-merge join | Sort both, then merge | Range joins, pre-sorted inputs |

You do not choose the method; you provide good statistics and indexes
([2.15](../performance-engineering/01-execution-plans.md)).

## 8. Common mistakes

| Mistake | Symptom |
|---|---|
| Missing join condition | A Cartesian product: 6 customers x 8 orders = 48 rows |
| Filtering the outer table in `WHERE` | Outer join silently becomes inner |
| `COUNT(*)` with an outer join | Zero-match groups report 1 |
| Joining two child tables then summing | Inflated totals (fan-out) |
| Selecting a non-grouped column | `ORA-00979` |
| Using `DISTINCT` to remove duplicates created by a join | Hides a wrong join and costs a sort |

## 9. Check yourself

??? question "Interview questions"
    1. **(Beginner)** Inner join versus left join?
    2. **(Beginner)** Why can't you use `WHERE COUNT(*) > 1`? *Aggregates are computed after `WHERE`; use `HAVING`.*
    3. **(Intermediate)** In a left join, what is the difference between a condition in `ON` and in `WHERE`? *`ON` decides which right-side rows match; `WHERE` filters the joined result and removes null-extended rows.*
    4. **(Senior)** How do you detect fan-out in a report query? *Compare `COUNT(*)` with `COUNT(DISTINCT parent_key)`, or check that each join goes to a unique key.*
    5. **(Architect)** A team reports revenue differently in two dashboards. Where do you look first? *Join fan-out, treatment of cancelled orders and returns, and the date boundary (order date versus payment date). Then define the measure once, in a view.*

??? example "Exercises"
    1. Total net sales (not cancelled) per month.
       ```sql
       SELECT TO_CHAR(order_date, 'YYYY-MM') AS month, COUNT(*) AS orders, SUM(total_amount) AS total
       FROM   orders WHERE status <> 'CANCELLED'
       GROUP  BY TO_CHAR(order_date, 'YYYY-MM') ORDER BY month;
       ```
       *Verified: 2025-03 → 4 orders, 2139; 2025-04 → 3 orders, 1549.*
    2. Revenue per category, highest first (not cancelled).
       *Verified: Staples 1300, Dairy and Eggs 918, Fruits 660, Beverages 420, Vegetables 190, Bakery 180.*
    3. Products that have never been ordered, using a left join.
       ```sql
       SELECT p.product_name FROM products p
       LEFT JOIN order_items oi ON oi.product_id = p.product_id
       WHERE  oi.product_id IS NULL;
       ```
       *Wheat Flour 5kg.*
    4. Number of products and average price per supplier.

## 10. Related

Next: [1.11 Your first index](07-first-index.md). In depth:
[2.1 Joins](../advanced-sql/01-joins.md), [2.4 Aggregation](../advanced-sql/04-aggregation-pivot.md).
