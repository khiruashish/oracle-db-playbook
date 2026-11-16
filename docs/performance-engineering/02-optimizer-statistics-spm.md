---
tags: [stage-3, performance, optimizer, statistics]
---

# 3.6 Optimizer, statistics and SQL Plan Management

!!! abstract "Chapter card"
    **Stage:** 3 · **Prerequisites:** 2.15 · **Time:** 6 hours · **Applies to:** 19c+

## At a glance

| Subtopic | In one line |
|---|---|
| Cost-based optimizer | Transformer, estimator, plan generator |
| Statistics | Table, column, index, system, dictionary and fixed-object |
| Histograms | Describing skewed columns |
| Extended statistics | Column groups and expressions |
| Gathering and managing | The auto task, preferences, pending, locking, incremental |
| Adaptive features | Adaptive plans, statistics feedback, dynamic statistics |
| Plan stability | SQL plan baselines, SQL profiles, SQL patches |
| Parallel execution | Using many processes for one statement |

## 1. The cost-based optimizer (CBO)

| Component | Job |
|---|---|
| **Query transformer** | Rewrites the statement into equivalent forms (view merging, unnesting, predicate pushing, OR-expansion, star transformation, MV rewrite) |
| **Estimator** | Computes **selectivity**, **cardinality** and **cost** for each operation from statistics |
| **Plan generator** | Tries join orders, join methods and access paths; keeps the cheapest |

**Cost** is an estimate of resource use (I/O and CPU) in units of single-block
reads. The historical **rule-based optimizer** chose plans from fixed ranking
rules (index beats full scan, always) and ignored data volumes; it has been
unsupported for many releases. Legacy code with `/*+ RULE */` hints should be
cleaned up.

Cardinality arithmetic, simplified:

| Predicate | Estimated selectivity |
|---|---|
| `col = value` (no histogram) | 1 / number of distinct values |
| `col = value` (histogram) | From the bucket for that value |
| `col > value` | (high − value) / (high − low) |
| `A AND B` | sel(A) × sel(B): **assumes independence** |
| `f(col) = value`, `LIKE :bind` | Fixed guesses (1%, 5%) |

Most bad plans trace to one of those assumptions being false.

## 2. Statistics

| Statistics | Examples | View |
|---|---|---|
| Table | `NUM_ROWS`, `BLOCKS`, `AVG_ROW_LEN` | `DBA_TAB_STATISTICS` |
| Column | `NUM_DISTINCT`, `NUM_NULLS`, `LOW_VALUE`, `HIGH_VALUE`, histogram | `DBA_TAB_COL_STATISTICS` |
| Index | `BLEVEL`, `LEAF_BLOCKS`, `DISTINCT_KEYS`, `CLUSTERING_FACTOR` | `DBA_IND_STATISTICS` |
| System | CPU speed, I/O timings | `SYS.AUX_STATS$` (defaults are recommended) |
| Dictionary / fixed objects | For queries on `DBA_*` and `V$` views | Gather after upgrades and major changes |

```sql
EXEC DBMS_STATS.GATHER_TABLE_STATS('FRESHMART', 'ORDERS');
EXEC DBMS_STATS.GATHER_SCHEMA_STATS('FRESHMART');

SELECT table_name, num_rows, blocks, last_analyzed, stale_stats
FROM   user_tab_statistics WHERE table_name = 'ORDERS';
```

Leave `ESTIMATE_PERCENT` and `METHOD_OPT` at their defaults
(`AUTO_SAMPLE_SIZE`, `FOR ALL COLUMNS SIZE AUTO`): the automatic sample uses a
full scan with approximate distinct counting and is both accurate and fast.

### The automatic statistics job

A maintenance-window task gathers statistics for objects with **missing** or
**stale** statistics (more than 10% of rows changed by default,
`STALE_PERCENT`). Two refinements:

- **Online statistics gathering**: direct-path loads into empty segments and CTAS gather statistics as they load (12c+).
- **High-frequency automatic statistics** (19c, Exadata/cloud): a lightweight task every 15 minutes.
- **Real-time statistics** (19c, Exadata/cloud): conventional DML maintains basic statistics as it runs.

### When the defaults are not enough

| Problem | Tool |
|---|---|
| A large batch load is followed immediately by queries | Gather at the end of the load job |
| Volatile tables (queues, staging) empty at night when statistics are gathered | Gather when representative, then `LOCK_TABLE_STATS`; or rely on dynamic statistics |
| "Out-of-range" dates: queries for today, statistics from yesterday | More frequent gathering on that table; `DBMS_STATS.COPY_TABLE_STATS` for partitions |
| Huge partitioned tables | **Incremental statistics**: `SET_TABLE_PREFS(..., 'INCREMENTAL', 'TRUE')` builds global statistics from per-partition synopses |
| Fear that new statistics will change plans | **Pending statistics**: gather with `PUBLISH = FALSE`, test with `OPTIMIZER_USE_PENDING_STATISTICS`, then publish |
| New statistics made things worse | `DBMS_STATS.RESTORE_TABLE_STATS` (history kept 31 days by default) |
| Different behavior per table | `DBMS_STATS.SET_TABLE_PREFS` rather than custom gather scripts |

## 3. Histograms

Without a histogram the optimizer assumes values are **uniformly distributed**.
`orders.status` has 5 values, so `status = 'CANCELLED'` is estimated at 20% of
rows even if it is really 1%.

| Type | When | Notes |
|---|---|---|
| **Frequency** | Distinct values ≤ buckets (default 254) | Exact count per value |
| **Top-frequency** | A few values dominate, the rest are negligible | 12c+ |
| **Hybrid** | More distinct values than buckets | 12c+; replaces height-balanced |

With `SIZE AUTO`, Oracle creates a histogram when the column is **skewed and
has been used in predicates** (recorded in `SYS.COL_USAGE$`). So a new table
gets histograms only after queries have run against it.

Histograms interact with **bind peeking**: the plan built for the first peeked
value is reused until adaptive cursor sharing reacts
([2.15](01-execution-plans.md)).

## 4. Extended statistics

```sql
-- Correlated columns: city determines state. Without this, selectivities are multiplied.
SELECT DBMS_STATS.CREATE_EXTENDED_STATS('FRESHMART', 'ADDRESSES', '(city, state)') FROM dual;

-- Expression used in predicates
SELECT DBMS_STATS.CREATE_EXTENDED_STATS('FRESHMART', 'PRODUCTS', '(UPPER(product_name))') FROM dual;

EXEC DBMS_STATS.GATHER_TABLE_STATS('FRESHMART', 'ADDRESSES');
```

A **column group** gives the optimizer the number of distinct *combinations*.
For `WHERE city = 'Mumbai' AND state = 'Maharashtra'` the estimate becomes the
share of Mumbai rows instead of (share of Mumbai) × (share of Maharashtra).

## 5. Adaptive features

| Feature | What it does | Control |
|---|---|---|
| **Adaptive plans** | Defers the join method or parallel distribution choice to run time | `OPTIMIZER_ADAPTIVE_PLANS` (default TRUE) |
| **Statistics feedback** | After a run with badly wrong estimates, re-optimizes next time | Part of adaptive statistics |
| **SQL plan directives** | Persistent notes: "estimates for these columns are unreliable; use dynamic statistics" | `OPTIMIZER_ADAPTIVE_STATISTICS` (default FALSE) |
| **Dynamic statistics** (sampling) | Samples data at parse time | `OPTIMIZER_DYNAMIC_SAMPLING` (default 2) |
| **Adaptive cursor sharing** | Several plans for one bind-sensitive statement | Automatic |

The defaults since 12.2 (adaptive plans on, adaptive statistics off) are right
for most systems.

## 6. Plan stability

| Mechanism | What it is | Effect | Licence |
|---|---|---|---|
| **SQL plan baseline** (SPM) | A set of **accepted** plans for a statement | The optimizer may use only accepted plans; new plans are recorded but not used until verified | EE |
| **SQL profile** | Corrections to cardinality estimates, created by SQL Tuning Advisor | Helps the optimizer find a better plan; does not fix one plan | Tuning Pack |
| **SQL patch** | Hints attached to a statement without changing its text (`DBMS_SQLDIAG.CREATE_SQL_PATCH`) | Targeted fix for third-party SQL | EE |
| **Stored outline** | Legacy | Migrate to baselines | |
| Hint in code | | Last resort | |

### SQL Plan Management

```sql
-- Capture the current good plan from the cursor cache
DECLARE n PLS_INTEGER;
BEGIN
    n := DBMS_SPM.LOAD_PLANS_FROM_CURSOR_CACHE(sql_id => '7h3k9xq2m4b1a', plan_hash_value => 1234567890);
END;
/
SELECT sql_handle, plan_name, enabled, accepted, fixed, origin
FROM   dba_sql_plan_baselines;

-- Let Oracle test an unaccepted plan and accept it only if it is better
SELECT DBMS_SPM.EVOLVE_SQL_PLAN_BASELINE(sql_handle => 'SQL_abc123...') FROM dual;
```

How it works: on hard parse the optimizer produces its best-cost plan. If the
statement has a baseline and that plan is not in it, the plan is stored as
**unaccepted** and an accepted plan is used instead. **Evolution** runs the new
plan against the accepted one and accepts it when it is measurably better. The
`SPM Evolve Advisor` task does this automatically in the maintenance window.

Uses: protect critical statements through upgrades and statistics changes; fix
a regression at once by loading the previous plan from AWR or a SQL tuning set.
**Automatic SQL Plan Management** (19c on Exadata/cloud; real-time SPM in
:material-tag: **23ai+**) detects and repairs regressions without intervention.

### Finding regressions

```sql
SELECT sql_id, plan_hash_value, executions,
       ROUND(elapsed_time / NULLIF(executions, 0) / 1000) AS ms_per_exec,
       ROUND(buffer_gets  / NULLIF(executions, 0))        AS gets_per_exec
FROM   v$sql
WHERE  sql_id = '&sql_id';
```

Two rows with different `plan_hash_value` and very different cost per execution
is a plan change. Historical plans are in `DBA_HIST_SQLSTAT` (Diagnostics Pack).

## 7. Parallel execution

One statement is run by a **query coordinator** and several **parallel
execution (PX) servers**, each scanning part of the data (granules) and passing
rows through table queues.

```sql
SELECT /*+ PARALLEL(8) */ status, COUNT(*), SUM(total_amount) FROM orders GROUP BY status;
ALTER SESSION ENABLE PARALLEL DML;      -- needed for parallel INSERT/UPDATE/DELETE/MERGE
```

| Setting | Meaning |
|---|---|
| Degree of parallelism (DOP) | Number of PX servers per operation; a statement may use 2 × DOP |
| `PARALLEL_DEGREE_POLICY = AUTO` | Oracle decides the DOP, may queue statements, and can use in-memory parallel execution |
| `PARALLEL_MAX_SERVERS`, `PARALLEL_SERVERS_TARGET` | Limits; beyond the target statements queue |
| `PARALLEL_MIN_TIME_THRESHOLD` | Only statements estimated above this run in parallel under AUTO |

Parallel execution trades resources for elapsed time. It suits data
warehouses, batch and maintenance (index builds, statistics, CTAS). In OLTP it
is dangerous: a few parallel statements can take all CPU and I/O. Do not set a
default `PARALLEL` degree on OLTP tables and indexes (a common leftover from a
parallel index build), and cap DOP with Resource Manager. Parallel query is an
Enterprise Edition feature.

## 8. Production recommendations

| DO | DON'T |
|---|---|
| Keep the automatic statistics task enabled | Disable it and forget to replace it |
| Fix estimates with statistics features first | Reach for hints and `optimizer_index_cost_adj` |
| Use table preferences for exceptions | Maintain custom gather scripts with hard-coded percentages |
| Baseline the critical 50 statements before an upgrade | Set `OPTIMIZER_FEATURES_ENABLE` to the old release forever |
| Gather dictionary and fixed-object statistics after upgrades | Leave them at defaults |

## 9. Common mistakes

- Gathering statistics on a queue table when it is empty.
- `ESTIMATE_PERCENT = 5` "to be fast", producing poor distinct counts and no usable histograms.
- Deleting histograms globally because of one bind-peeking problem.
- Assuming a SQL profile pins a plan.
- Parallel degree left on objects after maintenance.

## FreshMart example

=== "Scenario"

    The operations screen lists orders waiting to be packed. It was fast, then
    became slow the morning after a large historical data load.

    ```sql
    SELECT order_id, customer_id, order_date
    FROM   orders
    WHERE  status = 'PLACED'
    ORDER  BY order_date;
    ```

=== "Diagnosis"

    *Illustrative:* 50 million orders; 49.9 million `DELIVERED`, 20,000 `PLACED`.

    ```text
    | Id | Operation          | Name   | E-Rows | A-Rows |
    |* 2 |  TABLE ACCESS FULL | ORDERS |    10M |    20K |
       2 - filter("STATUS"='PLACED')
    ```

    `E-Rows` 10M = 50M / 5 distinct values: the uniform assumption. There is no
    histogram on `status`:

    ```sql
    SELECT column_name, num_distinct, histogram
    FROM   user_tab_col_statistics
    WHERE  table_name = 'ORDERS' AND column_name = 'STATUS';
    -- STATUS  5  NONE
    ```

    The load replaced the statistics (online gathering during the direct-path
    load does not create histograms).

=== "Fix"

    ```sql
    EXEC DBMS_STATS.GATHER_TABLE_STATS('FRESHMART', 'ORDERS', method_opt => 'FOR COLUMNS status SIZE 254');

    -- Make it permanent for future automatic gathers
    EXEC DBMS_STATS.SET_TABLE_PREFS('FRESHMART', 'ORDERS', 'METHOD_OPT', -
         'FOR ALL COLUMNS SIZE AUTO FOR COLUMNS status SIZE 254');
    ```

    With a frequency histogram the estimate for `'PLACED'` becomes about 20K
    and the plan returns to `INDEX RANGE SCAN IX_ORDERS_STATUS_DATE` with no
    sort. Because the application binds `:status`, add a plan baseline or rely
    on adaptive cursor sharing so that `'DELIVERED'` (which should full-scan)
    and `'PLACED'` each get the right plan.

=== "Takeaway"

    The plan was "wrong" only because the optimizer was told the data was
    uniform. The durable fix is better information, recorded as a table
    preference so that the next gather does not undo it.

## Check yourself

??? question "Interview questions"
    1. **(Intermediate)** What statistics does the optimizer use?
    2. **(Intermediate)** When is a histogram needed?
    3. **(Senior)** SQL profile versus SQL plan baseline?
    4. **(Senior)** How do incremental statistics work on partitioned tables?
    5. **(Architect)** Policy for plan stability across a fleet? *Default optimizer settings; automatic statistics with table preferences; SPM for a curated set of critical statements and automatic SPM where available; SQL Performance Analyzer before upgrades and parameter changes; monitoring of plan changes with per-execution regressions as alerts.*

??? example "Exercises"
    1. Gather statistics on `ORDERS`; check `USER_TAB_COL_STATISTICS` for histograms before and after running queries filtering on `status`.
    2. Create a column group on `addresses (city, state)` and compare the estimate for a two-column predicate.
    3. Load a plan into a baseline, create a new index, and observe the new plan recorded as unaccepted.

## Related

Next: [3.7 AWR, ASH and wait analysis](03-awr-ash-waits.md).
