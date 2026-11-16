---
tags: [stage-2, sql, analytics]
---

# 2.5 Window (analytic) functions

!!! abstract "Chapter card"
    **Stage:** 2 · **Prerequisites:** 2.4 · **Time:** 5 hours · **Applies to:** 19c+

## At a glance

A **window function** computes a value for each row by looking at a set of
related rows (its *window*) **without collapsing them** the way `GROUP BY` does.

| Subtopic | What it answers |
|---|---|
| `OVER (PARTITION BY ... ORDER BY ...)` | Which rows form the window, and in what order |
| Ranking: `ROW_NUMBER`, `RANK`, `DENSE_RANK`, `NTILE` | "Top 3 per category", "which quartile?" |
| Offset: `LAG`, `LEAD` | "Compare with the previous row" |
| Aggregates over a window | Running totals, moving averages, share of total |
| `FIRST_VALUE`, `LAST_VALUE`, `NTH_VALUE` | "Value from the first/last row of the window" |
| Frames: `ROWS`, `RANGE`, `GROUPS` | Exactly which neighbors are included |
| `QUALIFY` | Filter on a window function directly (26ai) |

## 1. Anatomy

```sql
function(args) OVER (
    PARTITION BY cols      -- split rows into independent groups (optional)
    ORDER BY cols          -- order inside each group (needed for ranking/running)
    ROWS BETWEEN ... AND ...   -- the frame: which rows around the current one (optional)
)
```

Window functions run **after** `WHERE`, `GROUP BY` and `HAVING`, and before the
final `ORDER BY`. So they cannot appear in `WHERE`: wrap the query in an inline
view and filter outside.

## 2. Ranking functions

```sql
SELECT product_name, unit_price,
       ROW_NUMBER() OVER (ORDER BY unit_price DESC) AS rn,
       RANK()       OVER (ORDER BY unit_price DESC) AS rnk,
       DENSE_RANK() OVER (ORDER BY unit_price DESC) AS drnk
FROM   products;
```

| Function | Ties | Sequence for values 650, 260, 260, 180 |
|---|---|---|
| `ROW_NUMBER` | Arbitrary order among ties | 1, 2, 3, 4 |
| `RANK` | Same rank, then a gap | 1, 2, 2, 4 |
| `DENSE_RANK` | Same rank, no gap | 1, 2, 2, 3 |

### Example: rank customers by net spend

```sql
SELECT customer_id,
       SUM(total_amount)                             AS net_spend,
       RANK() OVER (ORDER BY SUM(total_amount) DESC) AS spend_rank
FROM   orders
WHERE  status <> 'CANCELLED'
GROUP  BY customer_id
ORDER  BY spend_rank;
```

*Verified result:*

| CUSTOMER_ID | NET_SPEND | SPEND_RANK |
|---:|---:|---:|
| 101 | 1799 | 1 |
| 102 | 1140 | 2 |
| 105 | 393 | 3 |
| 103 | 356 | 4 |

The window function ranks the **grouped** rows: aggregates are computed first.

### Example: top product per category (Top-N per group)

```sql
SELECT category_id, product_id, revenue
FROM  (SELECT p.category_id, p.product_id,
              SUM(oi.line_total) AS revenue,
              ROW_NUMBER() OVER (PARTITION BY p.category_id
                                 ORDER BY SUM(oi.line_total) DESC, p.product_id) AS rn
       FROM   order_items oi
       JOIN   orders o   ON o.order_id   = oi.order_id
       JOIN   products p ON p.product_id = oi.product_id
       WHERE  o.status <> 'CANCELLED'
       GROUP  BY p.category_id, p.product_id)
WHERE  rn = 1
ORDER  BY category_id;
```

*Verified result:*

| CATEGORY_ID | PRODUCT_ID | REVENUE |
|---:|---:|---:|
| 2 | 1 | 540 |
| 3 | 3 | 120 |
| 4 | 5 | 476 |
| 5 | 8 | 180 |
| 6 | 10 | 300 |
| 7 | 11 | 1300 |

Always add a tie-breaker (`p.product_id`) to `ROW_NUMBER`'s `ORDER BY`,
otherwise the "winner" among ties can change between runs.

### NTILE

`NTILE(4) OVER (ORDER BY unit_price)` splits the 12 products into 4 buckets of
3: the three cheapest get 1, the three dearest get 4.

## 3. LAG and LEAD

```sql
SELECT order_id, order_date,
       LAG(order_date) OVER (ORDER BY order_date)              AS previous_order,
       order_date - LAG(order_date) OVER (ORDER BY order_date) AS days_since_previous
FROM   orders
WHERE  customer_id = 101
ORDER  BY order_date;
```

*Verified result:*

| ORDER_ID | ORDER_DATE | PREVIOUS_ORDER | DAYS_SINCE_PREVIOUS |
|---:|---|---|---:|
| 1001 | 2025-03-01 | *(null)* | *(null)* |
| 1003 | 2025-03-10 | 2025-03-01 | 9 |
| 1007 | 2025-04-05 | 2025-03-10 | 26 |

`LAG(col, n, default)` looks `n` rows back; `LEAD` looks forward. They replace
self-joins for "previous/next row" questions.

## 4. Aggregates over a window

### Running total

```sql
SELECT order_id, order_date, total_amount,
       SUM(total_amount) OVER (ORDER BY order_date, order_id) AS running_total
FROM   orders
WHERE  customer_id = 101
ORDER  BY order_date;
```

*Verified result:*

| ORDER_ID | ORDER_DATE | TOTAL_AMOUNT | RUNNING_TOTAL |
|---:|---|---:|---:|
| 1001 | 2025-03-01 | 639 | 639 |
| 1003 | 2025-03-10 | 424 | 1063 |
| 1007 | 2025-04-05 | 736 | 1799 |

### Share of total

```sql
SELECT c.category_name,
       SUM(oi.line_total)                                           AS revenue,
       ROUND(100 * RATIO_TO_REPORT(SUM(oi.line_total)) OVER (), 2)  AS pct_of_total
FROM   order_items oi
JOIN   orders o     ON o.order_id    = oi.order_id
JOIN   products p   ON p.product_id  = oi.product_id
JOIN   categories c ON c.category_id = p.category_id
WHERE  o.status <> 'CANCELLED'
GROUP  BY c.category_name
ORDER  BY revenue DESC;
```

*Result (revenue verified; percentages computed from 3668):*

| CATEGORY_NAME | REVENUE | PCT_OF_TOTAL |
|---|---:|---:|
| Staples | 1300 | 35.44 |
| Dairy and Eggs | 918 | 25.03 |
| Fruits | 660 | 17.99 |
| Beverages | 420 | 11.45 |
| Vegetables | 190 | 5.18 |
| Bakery | 180 | 4.91 |

`OVER ()` with nothing inside means "the whole result set".

### Moving average

```sql
SELECT order_id, total_amount,
       ROUND(AVG(total_amount) OVER (ORDER BY order_date
                                     ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 2) AS moving_avg_3
FROM   orders
WHERE  status <> 'CANCELLED'
ORDER  BY order_date;
```

| ORDER_ID | TOTAL_AMOUNT | MOVING_AVG_3 |
|---:|---:|---:|
| 1001 | 639 | 639 |
| 1002 | 720 | 679.5 |
| 1003 | 424 | 594.33 |
| 1004 | 356 | 500 |
| 1006 | 420 | 400 |
| 1007 | 736 | 504 |
| 1008 | 393 | 516.33 |

## 5. Frames

The frame decides which rows of the partition feed the function.

| Frame | Meaning |
|---|---|
| `ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW` | From the first row to this one (physical rows) |
| `ROWS BETWEEN 2 PRECEDING AND CURRENT ROW` | This row and the two before |
| `RANGE BETWEEN INTERVAL '7' DAY PRECEDING AND CURRENT ROW` | Rows whose order value is within 7 days (logical) |
| `ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING` | The whole partition |
| `GROUPS BETWEEN ...`, `EXCLUDE ...` | :material-tag: **21c+** peer-group frames |

!!! warning "The default frame surprises people"
    With `ORDER BY` and no frame, the default is
    `RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW`. Two consequences:

    1. Rows that **tie** on the `ORDER BY` value are peers and share the same
       running total. Add a unique tie-breaker or say `ROWS`.
    2. `LAST_VALUE(x)` returns the *current* row's value, because the frame
       ends at the current row. Write the frame out:
       `LAST_VALUE(x) OVER (ORDER BY d ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)`.

## 6. FIRST_VALUE, LAST_VALUE, NTH_VALUE

```sql
SELECT DISTINCT customer_id,
       FIRST_VALUE(order_id) OVER (PARTITION BY customer_id ORDER BY order_date) AS first_order,
       LAST_VALUE(order_id)  OVER (PARTITION BY customer_id ORDER BY order_date
              ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)          AS last_order
FROM   orders
WHERE  customer_id IN (101, 102);
```

| CUSTOMER_ID | FIRST_ORDER | LAST_ORDER |
|---:|---:|---:|
| 101 | 1001 | 1007 |
| 102 | 1002 | 1006 |

Add `IGNORE NULLS` to skip nulls, which is the standard way to "carry the last
known value forward".

## 7. QUALIFY :material-tag: **26ai**

`QUALIFY` filters on a window function without an inline view (reported for
release update 23.26.0; check your release).

```sql
SELECT customer_id, order_id, order_date
FROM   orders
QUALIFY ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_date DESC) = 1;
```

On 19c to 23ai, use the inline view form from section 2.

## 8. Other analytic tools

| Tool | Use |
|---|---|
| Named windows: `WINDOW w AS (PARTITION BY ...)` | Reuse one window definition (:material-tag: **21c+**) |
| `PERCENT_RANK`, `CUME_DIST`, `PERCENTILE_CONT` | Distribution analysis |
| `LISTAGG(...) OVER (PARTITION BY ...)` | String aggregation without grouping |
| `MATCH_RECOGNIZE` | Pattern matching over rows: sessions, "V" shapes, consecutive events (12.1+) |

## 9. How Oracle executes them

A window function appears in the plan as `WINDOW SORT` (sort by partition and
order keys), `WINDOW BUFFER` (already sorted input) or `WINDOW NOSORT` (an index
supplies the order). `WINDOW SORT PUSHED RANK` means Oracle stops keeping rows
that cannot satisfy an outer `rn <= N` filter.

Performance notes:

- The sort needs PGA memory and spills to temp for large partitions.
- Several functions with the **same** `PARTITION BY`/`ORDER BY` share one sort. Different windows mean several sorts.
- An index matching (partition columns, order columns) can remove the sort.
- Filter early: `WHERE` reduces the rows before the window is computed.

## 10. Common mistakes

- No tie-breaker in `ROW_NUMBER() ... ORDER BY`: non-deterministic results.
- `LAST_VALUE` with the default frame.
- Running totals with duplicate order keys under the default `RANGE` frame.
- Using a window function in `WHERE` (`ORA-30483`).
- Using `RANK` when you need exactly N rows (ties return more).

## FreshMart example

=== "Scenario"

    The retention team wants a "customer health" list: for every customer who
    has ordered, their number of orders, net spend, days since their previous
    order (at their latest order), and their spend rank. One query, one pass
    over `orders`.

=== "SQL"

    ```sql
    WITH o AS (
        SELECT customer_id, order_id, order_date, total_amount,
               COUNT(*)          OVER (PARTITION BY customer_id) AS orders,
               SUM(total_amount) OVER (PARTITION BY customer_id) AS net_spend,
               order_date - LAG(order_date) OVER (PARTITION BY customer_id
                                                  ORDER BY order_date) AS gap_days,
               ROW_NUMBER() OVER (PARTITION BY customer_id
                                  ORDER BY order_date DESC, order_id DESC) AS rn
        FROM   orders
        WHERE  status <> 'CANCELLED')
    SELECT c.customer_name, o.orders, o.net_spend, o.gap_days,
           RANK() OVER (ORDER BY o.net_spend DESC) AS spend_rank
    FROM   o
    JOIN   customers c ON c.customer_id = o.customer_id
    WHERE  o.rn = 1
    ORDER  BY spend_rank;
    ```

=== "Result"

    | CUSTOMER_NAME | ORDERS | NET_SPEND | GAP_DAYS | SPEND_RANK |
    |---|---:|---:|---:|---:|
    | Rahul Sharma | 3 | 1799 | 26 | 1 |
    | Priya Nair | 2 | 1140 | 30 | 2 |
    | Karan Mehta | 1 | 393 | *(null)* | 3 |
    | Amit Verma | 1 | 356 | *(null)* | 4 |

    Derived from the sample data (spend and ranks verified; Priya's gap is
    2025-03-03 to 2025-04-02 = 30 days).

=== "Takeaway"

    Three windows partitioned by customer share one sort. `rn = 1` keeps the
    latest order row, which carries the per-customer totals with it. The
    self-join alternative would read `orders` three times.

## Check yourself

??? question "Interview questions"
    1. **(Intermediate)** `RANK` versus `DENSE_RANK` versus `ROW_NUMBER`?
    2. **(Intermediate)** How do window functions differ from `GROUP BY`? *They keep every row and add a computed column.*
    3. **(Senior)** Why does `LAST_VALUE` often return the current row? *Default frame ends at the current row.*
    4. **(Senior)** `ROWS` versus `RANGE`? *Physical row offsets versus logical value offsets; RANGE treats ties as peers.*
    5. **(Architect)** A report with eight window functions over 500M rows is slow. Approach? *Group functions onto shared windows, filter before windowing, support the sort with an index or partition-wise processing, consider parallel query, or precompute in a materialized view.*

??? example "Exercises"
    1. Second-highest order total per warehouse.
    2. Running count of orders per customer by date.
    3. Each product's price difference from the average of its category.
       ```sql
       SELECT product_name, unit_price,
              ROUND(unit_price - AVG(unit_price) OVER (PARTITION BY category_id), 2) AS diff
       FROM   products;
       ```
       *Apple +60, Banana -60, Tomato +2.5, Onion -2.5, ...*

## Related

Next: [2.6 MERGE, Top-N, pagination, JSON](06-merge-topn-json.md).
