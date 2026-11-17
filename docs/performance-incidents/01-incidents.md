---
tags: [performance, incidents, freshmart]
---

# Performance incidents

Twelve realistic FreshMart incidents. Each follows the same seven steps:
**symptoms → diagnostic SQL → plan → root cause → solution → before and after →
prevention**.

!!! warning "Illustrative data"
    Plans, timings and before/after figures are illustrative: they show the
    pattern to look for and were not captured from a running system. Diagnostic
    queries on `V$ACTIVE_SESSION_HISTORY` and `DBA_HIST_*` need the
    Diagnostics Pack.

| # | Incident | Class |
|---|---|---|
| 1 | Slow product search | Access path |
| 2 | Slow customer order history | Index design |
| 3 | Inventory contention | Locking |
| 4 | Deadlocks during order placement | Locking |
| 5 | Full table scan after a data load | Statistics |
| 6 | Missing foreign key index | Locking and access path |
| 7 | Incorrect join order | Cardinality |
| 8 | Excessive hard parsing | Parsing |
| 9 | Connection pool exhaustion | Concurrency |
| 10 | Undo tablespace pressure | Transactions |
| 11 | High redo generation | Write volume |
| 12 | Slow bulk import | Load technique |

---

## 1. Slow product search

**Symptoms.** Search box p95 rises from 30 ms to 4 s as the catalog grows to 2
million products. CPU and `db file scattered read` dominate.

**Diagnostic SQL**

```sql
SELECT sql_id, executions, ROUND(elapsed_time / executions / 1000) AS ms_per_exec,
       ROUND(buffer_gets / executions) AS gets_per_exec
FROM   v$sqlstats WHERE sql_text LIKE 'SELECT product_id, product_name%LIKE%'
ORDER  BY elapsed_time DESC;
```

**Plan**

```text
|* 3 |  TABLE ACCESS FULL | PRODUCTS |  E-Rows 100K | A-Rows 350 | Buffers 41000 |
   3 - filter(UPPER("PRODUCT_NAME") LIKE '%' || UPPER(:TERM) || '%')
```

**Root cause.** A release changed the predicate from a prefix match
(`LIKE :term || '%'`) to a contains match (`LIKE '%' || :term || '%'`). A
leading wildcard cannot use the function-based B-tree index.

**Solution.** Create an Oracle Text index and use `CONTAINS`:

```sql
CREATE INDEX ix_products_name_txt ON products (product_name)
    INDEXTYPE IS CTXSYS.CONTEXT PARAMETERS ('SYNC (ON COMMIT)');

SELECT product_id, product_name, unit_price
FROM   products
WHERE  CONTAINS(product_name, :term || '%', 1) > 0 AND is_active = 'Y'
ORDER  BY SCORE(1) DESC FETCH FIRST 20 ROWS ONLY;
```

The label `1` links `CONTAINS` to `SCORE(1)`. Sanitize `:term` for Oracle Text
operators before use. For meaning-based search, see vector search in
[4.7](../oracle-26ai/01-oracle-26ai.md).

**Before and after**

| | Before | After |
|---|---:|---:|
| Buffer gets per execution | 41,000 | 60 |
| p95 | 4 s | 25 ms |

**Prevention.** Performance tests on production-sized data in CI for the top
ten queries; review any change to a predicate on a search path.

---

## 2. Slow customer order history

**Symptoms.** "My orders" slows as customers accumulate history; worst for the
most loyal customers. Wait: `db file sequential read`.

**Diagnostic SQL**

```sql
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR('&sql_id', NULL, 'ALLSTATS LAST'));
```

**Plan**

```text
|  2 |   SORT ORDER BY STOPKEY              |                   |  A-Rows 10   |
|  3 |    TABLE ACCESS BY INDEX ROWID BATCHED| ORDERS           |  A-Rows 4200 | Buffers 3900 |
|* 4 |     INDEX RANGE SCAN                 | IX_ORDERS_CUSTOMER|  A-Rows 4200 |
```

**Root cause.** The index is on `(customer_id)` only. Oracle fetches **all**
4,200 orders of the customer from scattered table blocks, sorts them, and
returns 10.

**Solution.** `CREATE INDEX ix_orders_cust_date ON orders (customer_id, order_date DESC) ONLINE;`
then drop the redundant single-column index after an invisible period.

```text
|* 2 |   WINDOW NOSORT STOPKEY       |                     | A-Rows 10 |
|  3 |    TABLE ACCESS BY INDEX ROWID| ORDERS              | A-Rows 10 | Buffers 14 |
|* 4 |     INDEX RANGE SCAN          | IX_ORDERS_CUST_DATE | A-Rows 10 |
```

**Before and after**

| | Before | After |
|---|---:|---:|
| Rows fetched to return 10 | 4,200 | 10 |
| Buffer gets | 3,900 | 14 |

**Prevention.** Design indexes from the query (equality, then sort column);
look for `SORT ORDER BY STOPKEY` above a large `A-Rows` in reviews.

---

## 3. Inventory contention

**Symptoms.** During a promotion, checkout latency climbs to seconds while host
CPU is low. Top event: `enq: TX - row lock contention`.

**Diagnostic SQL**

```sql
SELECT event, COUNT(*) AS seconds, COUNT(DISTINCT session_id) AS sessions,
       MAX(blocking_session) AS sample_blocker
FROM   v$active_session_history
WHERE  sample_time > SYSTIMESTAMP - INTERVAL '10' MINUTE
GROUP  BY event ORDER BY seconds DESC FETCH FIRST 5 ROWS ONLY;

SELECT s.sid, s.status, s.event, s.seconds_in_wait, t.start_time
FROM   v$session s JOIN v$transaction t ON t.addr = s.taddr
WHERE  s.sid = &blocker;      -- INACTIVE, "SQL*Net message from client", transaction open 3 s
```

**Plan.** The reservation `UPDATE` uses `INDEX UNIQUE SCAN PK_INVENTORY`: the
statement is efficient. The time is waiting, not working.

**Root cause.** The service reserves stock, then calls the payment gateway
(1 to 3 seconds), then commits. Every buyer of the promoted product queues
behind the row lock for the duration of someone else's payment call.

**Solution.** Split the unit of work: transaction 1 reserves stock and creates
the order as `PENDING` and commits; the gateway is called with no transaction
open; transaction 2 confirms or releases. A timeout job releases stale
reservations. For extreme hot rows, lock-free reservations (23ai+).

**Before and after**

| | Before | After |
|---|---:|---:|
| Lock hold time per checkout | 1 to 3 s | 2 ms |
| Checkout p95 at 50 orders/s on one product | 6 s | 180 ms |

**Prevention.** Rule: no remote calls inside a database transaction. Alert on
transactions open longer than a few seconds from application accounts.

---

## 4. Deadlocks during order placement

**Symptoms.** Sporadic `ORA-00060` in application logs at peak; affected
checkouts fail and are retried by users.

**Diagnostic SQL**

```sql
SELECT originating_timestamp, message_text FROM v$diag_alert_ext
WHERE  message_text LIKE '%ORA-00060%' AND originating_timestamp > SYSTIMESTAMP - INTERVAL '1' DAY;
```

Deadlock graph from the trace file: two sessions, two `TX` locks in mode `X`,
both on `INVENTORY`, rows for products 5 and 11.

**Plan.** Not a plan problem.

**Root cause.** The application reserved items in **cart order**. Cart A holds
Milk then wants Rice; cart B holds Rice then wants Milk.

**Solution.** Reserve in a deterministic order. `order_pkg.place_order`
iterates `ORDER BY product_id`. Add a bounded retry of the whole transaction
for the residual case.

**Before and after**

| | Before | After |
|---|---:|---:|
| Deadlocks per peak hour | 40 | 0 |

**Prevention.** One write path for multi-row locking (the package); code review
checklist item "locks acquired in a consistent order"; alert on any
`ORA-00060`.

---

## 5. Full table scan after a data load

**Symptoms.** The fulfilment screen (`WHERE status = 'PLACED'`) goes from
milliseconds to 20 seconds the morning after a historical load.

**Diagnostic SQL**

```sql
SELECT column_name, num_distinct, histogram, last_analyzed
FROM   dba_tab_col_statistics WHERE owner = 'FRESHMART' AND table_name = 'ORDERS' AND column_name = 'STATUS';
-- STATUS  5  NONE
```

**Plan**

```text
|* 2 |  TABLE ACCESS FULL | ORDERS | E-Rows 10M | A-Rows 20K |
```

**Root cause.** The load replaced statistics and removed the histogram on the
skewed `status` column. The optimizer assumes each of 5 values has 20% of rows.

**Solution.** Gather with a histogram and record it as a table preference
(full walkthrough in [3.6](../performance-engineering/02-optimizer-statistics-spm.md)).

**Before and after**

| | Before | After |
|---|---:|---:|
| Estimated rows | 10,000,000 | 20,000 |
| Access | Full scan | `INDEX RANGE SCAN IX_ORDERS_STATUS_DATE` |
| Elapsed | 20 s | 15 ms |

**Prevention.** Statistics preferences per table; load jobs end with a
statistics step; plan-change alerts on critical statements; SQL plan baselines
for the top screens.

---

## 6. Missing foreign key index

**Symptoms.** A weekly job deletes obsolete products. While it runs, order
placement freezes on `enq: TM - contention`, and the delete itself is slow.

**Diagnostic SQL**

```sql
--8<-- "sql/administration/objects_users.sql:indexes"
```

The foreign-key query lists `ORDER_ITEMS.FK_ORDER_ITEMS_PRODUCT` (in a schema
where `ix_order_items_product` was dropped as "unused").

**Plan.** The recursive check for each deleted product is a full scan of
`ORDER_ITEMS`.

**Root cause.** Without an index on the child foreign key column, deleting a
parent row takes a share lock on the **whole child table** and scans it.
Concurrent inserts into `order_items` wait.

**Solution.** `CREATE INDEX ix_order_items_product ON order_items (product_id) ONLINE;`

**Before and after**

| | Before | After |
|---|---:|---:|
| Delete of 1,000 products | 40 min | 3 s |
| Checkout blocked | Yes | No |

**Prevention.** The foreign-key-index check runs in CI and in the weekly health
check; "unused index" reviews exclude indexes that support foreign keys.
Better still: deactivate products (`is_active = 'N'`) instead of deleting them.

---

## 7. Incorrect join order

**Symptoms.** The daily "orders using promotion X" report takes 25 minutes; it
used to take seconds.

**Diagnostic SQL**

```sql
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR('&sql_id', NULL, 'ALLSTATS LAST'));
```

**Plan**

```text
| Id | Operation            | Name        | Starts | E-Rows | A-Rows |
|  1 |  NESTED LOOPS        |             |      1 |     12 |  1800K |
|* 2 |   TABLE ACCESS FULL  | ORDERS      |      1 |     12 |  1800K |
|* 3 |   INDEX UNIQUE SCAN  | PK_COUPONS  |  1800K |      1 |  1800K |
```

**Root cause.** The predicate `o.order_date >= TRUNC(SYSDATE) - 30 AND o.status
<> 'CANCELLED' AND o.subtotal > 500` is estimated at 12 rows: three
selectivities multiplied, with statistics a month old (the date range is
"out of range" of the known high value). With 12 rows expected, nested loops
driven by `orders` looks ideal; with 1.8 million it is 1.8 million probes.

**Solution.** Gather current statistics on `orders`; the plan becomes a hash
join driven by the 1 matching coupon. Longer term: incremental statistics on
the partitioned table so recent partitions are always current.

**Before and after**

| | Before | After |
|---|---:|---:|
| Join | Nested loops, 1.8M probes | Hash join |
| Elapsed | 25 min | 9 s |

**Prevention.** Look for the first step where E-Rows and A-Rows diverge; keep
statistics on fast-growing date columns current.

---

## 8. Excessive hard parsing

**Symptoms.** CPU at 90%; waits on `library cache: mutex X` and
`latch: shared pool`; occasional `ORA-04031`. Throughput falls as load rises.

**Diagnostic SQL**

```sql
--8<-- "sql/performance/sql_diagnosis.sql:literals"
```

One `force_matching_signature` has 180,000 versions:
`SELECT ... FROM products WHERE product_id = 48211`.

**Plan.** Each statement is a trivial unique scan. The cost is the parse, not
the execution.

**Root cause.** A new recommendations service builds SQL by string
concatenation. Every product id is a new statement: hard parse, new cursor,
shared pool churn.

**Solution.** Bind variables (`WHERE product_id = ?`) with statement caching in
the driver. As a stopgap while the code is fixed:
`ALTER SYSTEM SET cursor_sharing = FORCE` for that service's sessions (a logon
trigger or service-level setting), understanding that it changes optimizer
behavior for literals.

**Before and after**

| | Before | After |
|---|---:|---:|
| Hard parses per second | 2,400 | 3 |
| DB CPU | 90% | 25% |

**Prevention.** Static analysis for string-built SQL (also the SQL injection
check); a dashboard of hard parses per second; `cursor_sharing = EXACT` as the
standard with exceptions recorded.

---

## 9. Connection pool exhaustion

**Symptoms.** Application errors: `Connection is not available, request timed
out after 30000ms`. The database shows 800 sessions, average active sessions
about 300 on 16 cores, waits on CPU and `resmgr:cpu quantum` or latches.

**Diagnostic SQL**

```sql
SELECT status, COUNT(*) FROM v$session WHERE username = 'FM_APP' GROUP BY status;
SELECT resource_name, current_utilization, max_utilization, limit_value
FROM   v$resource_limit WHERE resource_name IN ('sessions', 'processes');
```

**Plan.** No single bad statement; everything is slower.

**Root cause.** 16 pods × `maximum-pool-size: 50`. A brief slowdown made every
pod open all its connections; 800 sessions then competed for 16 cores, context
switching and contending on latches, which made each request slower, which
kept the pools full: a feedback loop.

**Solution.** Reduce the pool to 4 per pod (64 in total), with a short
`connection-timeout` (2 to 3 s) so excess requests fail fast and are shed or
queued in the application. Add a Resource Manager active session limit as a
backstop.

**Before and after**

| | Before | After |
|---|---:|---:|
| Sessions | 800 | 64 |
| Throughput at peak | 900 tps, collapsing | 2,600 tps, stable |
| p95 | 8 s | 120 ms |

**Prevention.** Size total connections from database cores
([4.8](../spring-boot-integration/01-spring-boot.md)); account for autoscaling
(pool × maximum pods); alert on pool *pending* threads.

---

## 10. Undo tablespace pressure

**Symptoms.** A nightly report fails with `ORA-01555: snapshot too old` after
two hours; undo tablespace at 98%; occasionally `ORA-30036`.

**Diagnostic SQL**

```sql
--8<-- "sql/administration/space_undo_redo.sql:undo"
```

`V$UNDOSTAT` shows `maxquerylen` 7,400 s and a transaction with 9 million undo
records.

**Plan.** The report's plan is unchanged; it simply runs for two hours.

**Root cause.** Two things overlap: the archive job deletes 9 million rows in
one transaction, filling undo with active extents; the long report needs older
undo that has been overwritten.

**Solution.** Replace the mass `DELETE` with `DROP PARTITION` on the
month-partitioned table (almost no undo). Tune the report (it scanned
unneeded partitions) and move it to the standby. Size undo for the remaining
longest legitimate query.

**Before and after**

| | Before | After |
|---|---:|---:|
| Archive job | 3 h, 60 GB undo, 80 GB redo | 2 s |
| Report | Fails after 2 h | 6 min on the standby |

**Prevention.** Lifecycle by partition, not by delete; schedule long reads and
large writes apart; alert on undo usage and on `SSOLDERRCNT > 0`.

---

## 11. High redo generation

**Symptoms.** Archive destination fills on weekdays around 14:00; log switches
every 20 seconds; standby transport lag grows; `log file sync` rises.

**Diagnostic SQL**

```sql
--8<-- "sql/administration/space_undo_redo.sql:redo"
```

Segment-level (Diagnostics Pack): `DBA_HIST_SEG_STAT` ordered by
`db_block_changes_delta` points to `INVENTORY` and its indexes.

**Plan.** A sync job runs
`UPDATE inventory SET qty_on_hand = :q, updated_at = SYSTIMESTAMP WHERE warehouse_id = :w AND product_id = :p`
for **every** product every 5 minutes, 2 million rows, one commit per row.

**Root cause.** Unchanged rows are rewritten (each update generates redo and
undo and fires the trigger), and row-by-row commits add a `log file sync` each.

**Solution.** One `MERGE` per batch that updates only rows whose quantity
actually changed (`WHERE i.qty_on_hand <> s.counted_qty`) and commits once
([2.6](../advanced-sql/06-merge-topn-json.md)).

**Before and after**

| | Before | After |
|---|---:|---:|
| Rows updated per run | 2,000,000 | about 15,000 |
| Redo per run | 1.4 GB | 12 MB |
| Commits per run | 2,000,000 | 1 |

**Prevention.** Review jobs that update whole tables; track redo per day as a
capacity metric; never update a row to its current value.

---

## 12. Slow bulk imports

**Symptoms.** The initial catalog import of 5 million products takes 9 hours
and is being rerun for every new city.

**Diagnostic SQL**

```sql
SELECT event, COUNT(*) FROM v$active_session_history
WHERE  module = 'catalog-import' AND sample_time > SYSTIMESTAMP - INTERVAL '30' MINUTE
GROUP  BY event ORDER BY 2 DESC;
-- log file sync, SQL*Net message to/from client round trips, index maintenance
```

**Plan.** Single-row `INSERT ... VALUES`, executed 5 million times, autocommit on.

**Root cause.** One network round trip, one statement execution and one commit
per row; five indexes maintained row by row; a row-level trigger.

**Solution.** In order of benefit:

1. Load the file through an external table and a single
   `INSERT /*+ APPEND */ ... SELECT` (direct path), with parallel DML if licensed.
2. If the application must insert: JDBC batches of 500 and one commit per batch.
3. For an initial load: create secondary indexes after loading; validate constraints afterwards.

**Before and after**

| Method | Elapsed for 5M rows |
|---|---:|
| Row by row, autocommit | 9 h |
| JDBC batch 500, commit per batch | 12 min |
| External table + direct-path insert, indexes built after | 3 min |

**Prevention.** A documented bulk-load pattern in the platform's golden path;
reviews reject row-by-row loops over large sets
([4.5](../data-integration/01-data-integration.md)).

---

## Patterns across the twelve

| Lesson | Incidents |
|---|---|
| Follow the time (wait class first), not the CPU graph | 3, 9, 10 |
| Read access versus filter predicates, and E-Rows versus A-Rows | 1, 2, 5, 7 |
| Most "database" incidents are application transaction design | 3, 4, 8, 9, 11, 12 |
| Statistics are data the optimizer depends on | 5, 7 |
| Set-based beats row-by-row | 10, 11, 12 |
| More connections or more hardware would not have helped | 3, 8, 9 |
