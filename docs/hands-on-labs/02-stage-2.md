---
tags: [labs, stage-2]
---

# Labs: Stage 2

## Lab 2.1 Reporting with analytic SQL

**Objective.** Answer reporting questions with window functions, grouping extensions and CTEs.
**Prerequisites.** Chapters 2.3 to 2.5.

**Tasks and expected results**

| # | Task | Expected |
|---|---|---|
| 1 | Rank customers by net spend | 101 → 1799 (1), 102 → 1140 (2), 105 → 393 (3), 103 → 356 (4) (*verified*) |
| 2 | Running total of customer 101's orders by date | 639, 1063, 1799 (*verified*) |
| 3 | Top product per category by revenue | Apple 540, Tomato 120, Milk 476, Bread 180, Tea 300, Rice 1300 (*verified*) |
| 4 | Net sales by warehouse and month with subtotals (`ROLLUP`) | wh1 1063 + 1129 = 2192; wh2 720 + 420 = 1140; wh3 356; total 3688 |
| 5 | Employee org chart with level and path | 1 at level 1, 3 at level 2, 4 at level 3 (*verified*) |
| 6 | Each category's share of revenue | Staples 35.44%, Dairy 25.03%, Fruits 17.99%, Beverages 11.45%, Vegetables 5.18%, Bakery 4.91% |

**Validation.** Totals reconcile: task 4 grand total equals
`SELECT SUM(total_amount) FROM orders WHERE status <> 'CANCELLED'` (3688).

**Challenge.** For each customer with at least two orders, the average number
of days between consecutive orders.

??? success "Solution"
    ```sql
    SELECT customer_id, ROUND(AVG(gap), 1) AS avg_gap_days
    FROM  (SELECT customer_id,
                  order_date - LAG(order_date) OVER (PARTITION BY customer_id ORDER BY order_date) AS gap
           FROM   orders)
    WHERE  gap IS NOT NULL
    GROUP  BY customer_id;
    ```
    101 → 17.5 (gaps 9 and 26); 102 → 30.

**Further exploration.** Rewrite task 3 with `KEEP (DENSE_RANK FIRST ...)` and,
on 26ai, with `QUALIFY`.

---

## Lab 2.2 A PL/SQL API

**Objective.** Extend `order_pkg` with a tested, transactional procedure.
**Prerequisites.** Chapters 2.7 to 2.10.

**Task.** Add `mark_packed(p_order_id)`: allowed only from `PLACED`; raises
`-20005` otherwise; does not commit.

**Steps**

1. Add the declaration to the specification and the implementation to the body using a conditional `UPDATE ... WHERE status = 'PLACED'` and `SQL%ROWCOUNT`.
2. Recompile; check `SHOW ERRORS` and `USER_OBJECTS.STATUS`.
3. Test both paths.

```sql
BEGIN order_pkg.mark_packed(1007); END;      -- PLACED -> PACKED
/
SELECT status FROM orders WHERE order_id = 1007;                      -- PACKED
SELECT operation, old_values, new_values FROM audit_log WHERE pk_value = '1007';
BEGIN order_pkg.mark_packed(1001); END;      -- DELIVERED: must fail
/
ROLLBACK;
```

**Expected results.** First call succeeds and the audit trigger writes
`status=PLACED` → `status=PACKED`. Second call raises
`ORA-20005: Order 1001 is DELIVERED and cannot be packed`.

**Validation.** After `ROLLBACK`, order 1007 is `PLACED` again and `audit_log`
has no row for it.

??? success "Solution"
    ```sql
    PROCEDURE mark_packed (p_order_id IN orders.order_id%TYPE) IS
        l_status orders.status%TYPE;
    BEGIN
        UPDATE orders SET status = 'PACKED'
        WHERE  order_id = p_order_id AND status = 'PLACED';
        IF SQL%ROWCOUNT = 0 THEN
            BEGIN
                SELECT status INTO l_status FROM orders WHERE order_id = p_order_id;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    RAISE_APPLICATION_ERROR(-20005, 'Order ' || p_order_id || ' does not exist');
            END;
            RAISE_APPLICATION_ERROR(-20005,
                'Order ' || p_order_id || ' is ' || l_status || ' and cannot be packed');
        END IF;
    END mark_packed;
    ```

**Challenge.** Why a conditional `UPDATE` instead of `SELECT status` then `UPDATE`?
*Two sessions could both read `PLACED`; the conditional update is atomic.*

**Further exploration.** Write utPLSQL tests for both paths.

---

## Lab 2.3 Locks and deadlocks

**Objective.** Create, observe and resolve a blocking lock and a deadlock.
**Prerequisites.** Chapter 2.11. Sessions A and B as `FRESHMART`; session C with access to `V$SESSION`.

**Steps**

| # | Session | Statement |
|---|---|---|
| 1 | A | `UPDATE inventory SET qty_on_hand = qty_on_hand WHERE warehouse_id = 1 AND product_id = 5;` |
| 2 | B | `UPDATE inventory SET qty_on_hand = qty_on_hand WHERE warehouse_id = 1 AND product_id = 11;` |
| 3 | A | Same statement for product **11** (A waits) |
| 4 | C | `SELECT sid, blocking_session, event, seconds_in_wait FROM v$session WHERE blocking_session IS NOT NULL;` |
| 5 | B | Same statement for product **5** |
| 6 | A or B | One receives `ORA-00060` |
| 7 | Both | `ROLLBACK;` |

**Expected results.** Step 4 shows A waiting on `enq: TX - row lock contention`
with B as the blocker. Within seconds of step 5 one session gets
`ORA-00060: deadlock detected while waiting for resource`; the other continues
to wait until the loser rolls back.

**Validation.** Find the deadlock trace (`V$DIAG_ALERT_EXT` or `adrci`) and
identify the two statements in the graph.

**Challenge.** Rewrite the two "transactions" so that a deadlock is impossible.

??? success "Solution"
    Both sessions update product 5 first, then product 11: the second session
    simply waits for the first and proceeds after its commit.

**Further exploration.** Repeat step 3 with `SELECT ... FOR UPDATE WAIT 3`.

---

## Lab 2.4 Indexes and plans

**Objective.** See how an index changes a plan, and how a function disables one.
**Prerequisites.** Chapters 2.12, 2.15.

**Setup: a bigger table**

```sql
CREATE TABLE orders_big AS
SELECT ROWNUM AS order_id,
       101 + MOD(ROWNUM, 5000)                              AS customer_id,
       DATE '2024-01-01' + MOD(ROWNUM, 730)                 AS order_date,
       CASE WHEN MOD(ROWNUM, 200) = 0 THEN 'PLACED' ELSE 'DELIVERED' END AS status,
       ROUND(DBMS_RANDOM.VALUE(100, 900), 2)                AS total_amount
FROM   dual CONNECT BY LEVEL <= 500000;
EXEC DBMS_STATS.GATHER_TABLE_STATS(USER, 'ORDERS_BIG')
```

**Steps**

1. Get the actual plan (`GATHER_PLAN_STATISTICS` + `DISPLAY_CURSOR('ALLSTATS LAST')`) for
   `SELECT * FROM orders_big WHERE customer_id = 150 ORDER BY order_date DESC FETCH FIRST 10 ROWS ONLY;`
2. `CREATE INDEX ix_ob_cust ON orders_big (customer_id);` Repeat.
3. Replace it with `(customer_id, order_date DESC)`. Repeat.
4. Query `WHERE TO_CHAR(order_date, 'YYYY-MM') = '2025-03'` after creating an index on `order_date`. Then rewrite as a range.
5. Query `WHERE status = 'PLACED'` with an index on `status`; check the row estimate; gather a histogram; check again.

**Expected results (shape, not numbers)**

| Step | Plan |
|---|---|
| 1 | `TABLE ACCESS FULL`, sort |
| 2 | `INDEX RANGE SCAN`, about 100 table rows fetched, `SORT ORDER BY STOPKEY` |
| 3 | `INDEX RANGE SCAN`, 10 rows, `WINDOW NOSORT STOPKEY` |
| 4 | Full scan with a `filter(TO_CHAR(...))`; the range version uses the index |
| 5 | Estimate about 250,000 (half) before the histogram; about 2,500 after |

**Validation.** Buffers fall at each of steps 1 → 2 → 3.

**Challenge.** Make step 3 an index-only plan for
`SELECT order_date, total_amount ...`.

??? success "Solution"
    `CREATE INDEX ix_ob_cover ON orders_big (customer_id, order_date DESC, total_amount);`
    The plan loses `TABLE ACCESS BY INDEX ROWID`.

**Clean up.** `DROP TABLE orders_big PURGE;`

---

## Lab 2.5 Partitioning

**Objective.** Create an interval-partitioned table, see pruning, and exchange a partition.
**Prerequisites.** Chapter 2.13. An edition with the Partitioning option (the Free edition includes it).

**Steps**

```sql
CREATE TABLE orders_p
PARTITION BY RANGE (order_date) INTERVAL (NUMTOYMINTERVAL(1, 'MONTH'))
(PARTITION p_before_2025 VALUES LESS THAN (DATE '2025-01-01'))
AS SELECT order_id, customer_id, order_date, status, total_amount FROM orders;

SELECT partition_name, high_value, num_rows FROM user_tab_partitions WHERE table_name = 'ORDERS_P';

EXPLAIN PLAN FOR
SELECT SUM(total_amount) FROM orders_p
WHERE  order_date >= DATE '2025-03-01' AND order_date < DATE '2025-04-01';
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(format => 'BASIC +PARTITION'));
```

**Expected results.** Three partitions: `P_BEFORE_2025` (empty) and two
system-named partitions for March (5 rows) and April (3 rows). The plan shows
`PARTITION RANGE SINGLE` with equal `Pstart` and `Pstop`.

**Validation.** The March query returns 2409 (all five March orders including
the cancelled one: 639 + 720 + 424 + 356 + 270).

**Challenge.** Archive March by exchanging it with an empty table, without
moving rows.

??? success "Solution"
    ```sql
    CREATE TABLE orders_2025_03 FOR EXCHANGE WITH TABLE orders_p;
    ALTER TABLE orders_p EXCHANGE PARTITION FOR (DATE '2025-03-15') WITH TABLE orders_2025_03;
    SELECT COUNT(*) FROM orders_2025_03;   -- 5
    SELECT COUNT(*) FROM orders_p;         -- 3
    ```

**Clean up.** Drop both tables with `PURGE`.
