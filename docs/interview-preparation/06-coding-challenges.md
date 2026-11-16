---
tags: [interview, sql, practice]
---

# SQL coding and debugging challenges

Twenty challenges on the FreshMart sample data. Results marked *verified* are
checked by `tests/verify_outputs.py`; the others are derived by hand. Try each
before opening the solution.

## Part A: write the query

### A1. Customers who have never ordered

??? success "Solution"
    ```sql
    SELECT c.customer_name FROM customers c
    WHERE  NOT EXISTS (SELECT 1 FROM orders o WHERE o.customer_id = c.customer_id);
    ```
    Neha Gupta.

### A2. Second-highest order total

??? success "Solution"
    ```sql
    SELECT total_amount FROM (
        SELECT total_amount, DENSE_RANK() OVER (ORDER BY total_amount DESC) AS rk FROM orders)
    WHERE rk = 2;
    ```
    720.

### A3. Orders above the average order value (*verified*)

??? success "Solution"
    ```sql
    SELECT order_id FROM orders
    WHERE  total_amount > (SELECT AVG(total_amount) FROM orders) ORDER BY order_id;
    ```
    1001, 1002, 1007 (average 494.75).

### A4. Net spend and rank per customer (*verified*)

??? success "Solution"
    ```sql
    SELECT customer_id, SUM(total_amount) AS spend,
           RANK() OVER (ORDER BY SUM(total_amount) DESC) AS rk
    FROM   orders WHERE status <> 'CANCELLED' GROUP BY customer_id;
    ```
    101: 1799 (1), 102: 1140 (2), 105: 393 (3), 103: 356 (4).

### A5. Products bought by more than one distinct customer

??? success "Solution"
    ```sql
    SELECT p.product_name, COUNT(DISTINCT o.customer_id) AS buyers
    FROM   order_items oi
    JOIN   orders o   ON o.order_id   = oi.order_id
    JOIN   products p ON p.product_id = oi.product_id
    WHERE  o.status <> 'CANCELLED'
    GROUP  BY p.product_name HAVING COUNT(DISTINCT o.customer_id) > 1
    ORDER  BY buyers DESC, p.product_name;
    ```
    Whole Wheat Bread 3 (101, 102, 105); Apple 2; Assam Tea 2; Basmati Rice 2;
    Eggs 2; Full Cream Milk 2.

### A6. Month-over-month revenue change (*verified*)

??? success "Solution"
    See query 17 in [business queries](../grocery-application/04-business-queries.md):
    2025-03 → 2139; 2025-04 → 1549, change −590.

### A7. Customers who ordered in March but not in April

??? success "Solution"
    ```sql
    SELECT customer_id FROM orders WHERE order_date <  DATE '2025-04-01'
    MINUS
    SELECT customer_id FROM orders WHERE order_date >= DATE '2025-04-01';
    ```
    103, 104.

### A8. Each employee with their manager's name and their level in the hierarchy

??? success "Solution"
    ```sql
    SELECT LEVEL AS lvl, e.employee_name, PRIOR e.employee_name AS manager
    FROM   employees e
    START  WITH e.manager_id IS NULL
    CONNECT BY PRIOR e.employee_id = e.manager_id
    ORDER  SIBLINGS BY e.employee_id;
    ```
    Level 1: Anita. Level 2: Vikram, Meera, Arjun. Level 3: Sunil, Fatima,
    Ravi, Pooja (*level counts verified*).

### A9. Orders whose successful payments do not equal the order total

??? success "Solution"
    ```sql
    SELECT o.order_id, o.status, o.total_amount,
           NVL(SUM(CASE WHEN p.status = 'SUCCESS' THEN p.amount END), 0) AS paid
    FROM   orders o LEFT JOIN payments p ON p.order_id = o.order_id
    GROUP  BY o.order_id, o.status, o.total_amount
    HAVING o.total_amount <> NVL(SUM(CASE WHEN p.status = 'SUCCESS' THEN p.amount END), 0)
    ORDER  BY o.order_id;
    ```
    1004 (cash on delivery, pending: paid 0) and 1005 (cancelled and refunded: paid 0).

### A10. Pivot successful payment amounts by method (*verified amounts*)

??? success "Solution"
    ```sql
    SELECT * FROM (SELECT payment_method, amount FROM payments WHERE status = 'SUCCESS')
    PIVOT (SUM(amount) FOR payment_method IN ('UPI' AS upi, 'CARD' AS card,
                                              'WALLET' AS wallet, 'NETBANKING' AS netbanking));
    ```
    UPI 1063, CARD 1456, WALLET 420, NETBANKING 393.

### A11. For each warehouse, the product with the most units on hand

??? success "Solution"
    ```sql
    SELECT warehouse_id,
           MAX(product_id) KEEP (DENSE_RANK FIRST ORDER BY qty_on_hand DESC) AS product_id,
           MAX(qty_on_hand) AS qty
    FROM   inventory GROUP BY warehouse_id ORDER BY warehouse_id;
    ```
    1 → product 5 (200); 2 → product 1 (60); 3 → product 4 (110).

### A12. Average rating per product with at least two reviews (*verified*)

??? success "Solution"
    ```sql
    SELECT product_id, COUNT(*) AS reviews, AVG(rating) AS avg_rating
    FROM   reviews GROUP BY product_id HAVING COUNT(*) >= 2;
    ```
    Product 1: 2 reviews, 4.5.

## Part B: find and fix the bug

### B1. "Employees who are not managers" returns no rows

```sql
SELECT employee_name FROM employees
WHERE  employee_id NOT IN (SELECT manager_id FROM employees);
```

??? success "Solution"
    `manager_id` is null for Anita Desai, so `NOT IN` is never true. Use
    `NOT EXISTS`, or add `WHERE manager_id IS NOT NULL` to the subquery.
    Correct result: Sunil Kumar, Fatima Khan, Ravi Teja, Pooja Yadav.

### B2. The "top 3 orders" are wrong

```sql
SELECT order_id, total_amount FROM orders WHERE ROWNUM <= 3 ORDER BY total_amount DESC;
```

??? success "Solution"
    `ROWNUM` is assigned before the sort: three arbitrary rows are then sorted.
    Use `ORDER BY total_amount DESC FETCH FIRST 3 ROWS ONLY`. Correct: 1007,
    1002, 1001.

### B3. Totals are too high

```sql
SELECT o.order_id, SUM(oi.line_total) AS items, SUM(p.amount) AS paid
FROM   orders o
JOIN   order_items oi ON oi.order_id = o.order_id
JOIN   payments p     ON p.order_id  = o.order_id
GROUP  BY o.order_id;
```

??? success "Solution"
    Fan-out: each item row is paired with each payment row. Order 1007 shows
    items 1572 instead of 786. Aggregate each child in its own inline view (or
    scalar subquery) and then join.

### B4. All customers "with delivered orders" loses customers

```sql
SELECT c.customer_name, o.order_id
FROM   customers c LEFT JOIN orders o ON o.customer_id = c.customer_id
WHERE  o.status = 'DELIVERED';
```

??? success "Solution"
    The `WHERE` on the outer table removes null-extended rows, making it an
    inner join (5 rows). Move the condition into `ON` (8 rows).

### B5. March orders are missing some rows in production

```sql
SELECT * FROM orders WHERE order_date BETWEEN DATE '2025-03-01' AND DATE '2025-03-31';
```

??? success "Solution"
    `DATE` has a time part. Orders placed during 31 March after midnight are
    excluded. Use `order_date >= DATE '2025-03-01' AND order_date < DATE '2025-04-01'`.
    (The sample data has no time parts, which is why the bug hides in testing.)

### B6. This query is correct but slow on a large table

```sql
SELECT * FROM orders WHERE TO_CHAR(order_date, 'YYYY-MM-DD') = '2025-03-10';
```

??? success "Solution"
    The function on the column prevents index range scans and partition
    pruning. Rewrite:
    `WHERE order_date >= DATE '2025-03-10' AND order_date < DATE '2025-03-11'`.

### B7. The procedure "works" but orders are sometimes oversold

```sql
SELECT qty_on_hand - qty_reserved INTO l_avail FROM inventory WHERE warehouse_id = p_wh AND product_id = p_id;
IF l_avail >= p_qty THEN
    UPDATE inventory SET qty_reserved = qty_reserved + p_qty WHERE warehouse_id = p_wh AND product_id = p_id;
END IF;
```

??? success "Solution"
    A race: two sessions read the same availability before either writes. Use
    a single conditional `UPDATE ... AND qty_on_hand - qty_reserved >= p_qty`
    and check `SQL%ROWCOUNT`, or `SELECT ... FOR UPDATE` first. (Here the check
    constraint would catch the worst case with an error, which is better than
    overselling but still a failed checkout.)

### B8. The running total repeats values

```sql
SELECT order_id, order_date, SUM(total_amount) OVER (ORDER BY order_date) AS running
FROM   orders;
```

??? success "Solution"
    With the default `RANGE` frame, rows sharing an `order_date` are peers and
    get the same running total. Add a unique tie-breaker
    (`ORDER BY order_date, order_id`) or specify `ROWS UNBOUNDED PRECEDING`.
    (The sample data has unique dates, so again the bug hides until production.)

## Part C: explain the plan

For each, say what you would check and what you would change.

| # | Plan fragment | What it tells you |
|---|---|---|
| C1 | `TABLE ACCESS FULL ORDERS` with `filter("CUSTOMER_ID"=:B1)`, A-Rows 3, Buffers 40,000 | 40,000 blocks read to return 3 rows: a missing or unusable index on `customer_id` |
| C2 | `NESTED LOOPS`, outer E-Rows 10, A-Rows 2,000,000 | Cardinality misestimate driving the wrong join method: check statistics, histograms, correlated predicates |
| C3 | `MERGE JOIN CARTESIAN` | A missing join predicate, or an estimate of one row on one side |
| C4 | `SORT ORDER BY STOPKEY` above `INDEX RANGE SCAN` returning 50,000 rows | The index does not supply the order: add the sort column to the index |
| C5 | `filter(TO_NUMBER("PHONE")=9800000101)` | Implicit conversion: the column is a string compared with a number; bind or quote the value |
| C6 | `PARTITION RANGE ALL` on a date-partitioned table | No pruning: predicate missing, or a function on the partition key |
| C7 | `HASH JOIN` with "Used-Tmp" and `direct path write temp` waits | The hash table spilled to temp: PGA sizing, or far more rows than estimated |
| C8 | Same `sql_id`, two `plan_hash_value`s, one 100 times slower | Plan instability: bind peeking or statistics change; stabilize with a baseline, then fix the estimate |
