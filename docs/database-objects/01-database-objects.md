---
tags: [stage-2, objects, views, materialized-views]
---

# 2.14 Views, materialized views and other objects

!!! abstract "Chapter card"
    **Stage:** 2 · **Prerequisites:** 2.1 to 2.6 · **Time:** 3 hours · **Applies to:** 19c+

## At a glance

| Object | In one line |
|---|---|
| View | A stored query; holds no data |
| Materialized view | A stored query **and** its result, refreshed by the database |
| Sequence | A generator of unique numbers |
| Synonym | An alternative name for an object |
| Database link | A connection from one database to another |
| External table | Query a file as if it were a table |
| Temporary tables | Session-private rows (global) or session-private tables (private) |
| Clusters, object types, XMLType | Specialized structures |

## 1. Views

```sql
CREATE OR REPLACE VIEW v_low_stock AS
SELECT w.warehouse_name, p.product_name,
       i.qty_on_hand - i.qty_reserved AS qty_available, i.reorder_level
FROM   inventory i
JOIN   warehouses w ON w.warehouse_id = i.warehouse_id
JOIN   products   p ON p.product_id   = i.product_id
WHERE  i.qty_on_hand - i.qty_reserved <= i.reorder_level;

SELECT * FROM v_low_stock ORDER BY warehouse_name;
```

*Verified result:*

| WAREHOUSE_NAME | PRODUCT_NAME | QTY_AVAILABLE | REORDER_LEVEL |
|---|---|---:|---:|
| Bengaluru South FC | Whole Wheat Bread 400g | 10 | 15 |
| Delhi NCR FC | Wheat Flour 5kg | 8 | 10 |
| Mumbai Central FC | Paneer 200g | 15 | 20 |

**Uses:** hide complexity, give a stable interface while tables change, restrict
columns and rows (security), define a business measure once.

**How it runs:** the view text is merged into your query (view merging) and
optimized as a whole. A view is not slower than writing the same SQL by hand.
The risk is the opposite: views stacked on views that join tables you do not need.

| Option | Effect |
|---|---|
| `WITH READ ONLY` | No DML through the view |
| `WITH CHECK OPTION` | DML through the view may not create rows the view cannot see |
| `FORCE` | Create even if base objects are missing (deployment order) |
| `BEQUEATH CURRENT_USER` | Functions inside run with the invoker's rights |

A view is **updatable** when each row maps to one row of one base table: no
`DISTINCT`, aggregates, `GROUP BY` or set operators. In a join view, only the
**key-preserved** table can be modified. Otherwise use an `INSTEAD OF` trigger.

## 2. Materialized views

A **materialized view (MV)** stores the result of its query in a real segment.
Oracle keeps it up to date and can transparently redirect queries to it.

```sql
CREATE MATERIALIZED VIEW LOG ON orders
    WITH ROWID, SEQUENCE (order_date, status, total_amount) INCLUDING NEW VALUES;

CREATE MATERIALIZED VIEW mv_daily_sales
    BUILD IMMEDIATE
    REFRESH FAST ON DEMAND
    ENABLE QUERY REWRITE
AS
SELECT TRUNC(order_date) AS sale_date,
       status,
       COUNT(*)            AS order_count,
       SUM(total_amount)   AS total_amount,
       COUNT(total_amount) AS cnt_total          -- required for fast refresh of SUM
FROM   orders
GROUP  BY TRUNC(order_date), status;
```

### Refresh

| Method | What it does | Needs |
|---|---|---|
| `COMPLETE` | Re-runs the whole query | Nothing; expensive |
| `FAST` | Applies only the changes since the last refresh | Materialized view logs and a query shape that qualifies |
| `FORCE` | Fast if possible, else complete | |
| Partition change tracking (PCT) | Refreshes only affected partitions | Partitioned base table |

| When | Trade-off |
|---|---|
| `ON DEMAND` | You call `DBMS_MVIEW.REFRESH('MV_DAILY_SALES', 'F')` or schedule it. Data is stale in between |
| `ON COMMIT` | Refreshed as part of every committing transaction: always current, but slows those commits |
| `ON STATEMENT` (12.2+) | Refreshed with each DML statement; limited query shapes |
| Real-time MV: `ENABLE ON QUERY COMPUTATION` (12.2+) | Stale MV plus on-the-fly application of the logs gives current results |

`DBMS_MVIEW.EXPLAIN_MVIEW` tells you exactly why an MV cannot fast refresh or
rewrite. Use it instead of guessing.

A complete refresh by default deletes and reinserts in one transaction
(`ATOMIC_REFRESH => TRUE`): readers always see data, but it generates heavy
undo and redo. `ATOMIC_REFRESH => FALSE` truncates and direct-path loads:
faster, but the MV is empty during the refresh. **Out-of-place refresh**
(12.1+) builds a new copy and swaps it.

### Query rewrite

With `ENABLE QUERY REWRITE`, a query written against `orders` that the MV can
answer is rewritten to read the MV. Applications need no change.

```sql
SELECT TRUNC(order_date), SUM(total_amount) FROM orders
WHERE  status <> 'CANCELLED' GROUP BY TRUNC(order_date);
-- Plan: MAT_VIEW REWRITE ACCESS FULL  MV_DAILY_SALES
```

`QUERY_REWRITE_INTEGRITY` controls trust: `ENFORCED` (default; only fresh MVs
and validated constraints), `TRUSTED` (also `RELY` constraints and dimensions),
`STALE_TOLERATED` (stale MVs allowed).

Each MV log adds work to every DML on its base table. Query rewrite and several
refresh features are Enterprise Edition.

## 3. Sequences

```sql
CREATE SEQUENCE invoice_seq START WITH 1 INCREMENT BY 1 CACHE 1000 NOCYCLE;
SELECT invoice_seq.NEXTVAL FROM dual;
```

| Option | Meaning |
|---|---|
| `CACHE n` | Pre-allocates n values in memory. Larger cache = less contention. Values in the cache are lost on instance restart |
| `NOCACHE` | Every `NEXTVAL` updates the dictionary: a serious bottleneck under load |
| `ORDER` | Guarantees ordering across RAC instances at a high cost |
| `SCALE` (18c+) | Prefixes instance and session numbers to spread values and avoid index hot spots |
| `SESSION` | Values private to a session (for temporary tables) |

Sequences are **not transactional**: a rollback does not return the number. Gaps
are normal. For legally gap-free numbering, assign numbers in a serialized
step at document finalization, not from a sequence.

## 4. Synonyms

```sql
CREATE SYNONYM orders FOR freshmart.orders;            -- private, in the current schema
CREATE PUBLIC SYNONYM order_pkg FOR freshmart.order_pkg;
```

A synonym lets an application user reference `orders` without the schema prefix
and lets you repoint a name. It grants nothing: privileges on the target are
still required. Prefer private synonyms or
`ALTER SESSION SET CURRENT_SCHEMA = freshmart`; public synonyms pollute a shared
namespace and are a security review item.

## 5. Database links

```sql
CREATE DATABASE LINK warehouse_dw
    CONNECT TO dw_reader IDENTIFIED BY "..." USING 'DWPROD';

SELECT COUNT(*) FROM fact_sales@warehouse_dw;
```

A link lets SQL in one database query or change objects in another. DML across
a link is a distributed transaction with two-phase commit.

| Concern | Guidance |
|---|---|
| Performance | A join of a local and a remote table may pull the remote rows across the network. Check the plan for `REMOTE` steps; use the `DRIVING_SITE` hint or push the join into a remote view |
| Security | A fixed-user link gives everyone who can use it that remote user's privileges. Use least-privilege accounts; avoid public links |
| Coupling | The local database now depends on the remote one being up and its schema unchanged |
| Operations | Open links hold remote sessions; links break on password rotation |

Use links for controlled data movement, not as an integration architecture
([4.5](../data-integration/01-data-integration.md)).

## 6. External tables

```sql
CREATE DIRECTORY feed_dir AS '/data/feeds';

CREATE TABLE price_feed_ext (
    sku       VARCHAR2(30),
    new_price NUMBER(10,2)
)
ORGANIZATION EXTERNAL (
    TYPE ORACLE_LOADER
    DEFAULT DIRECTORY feed_dir
    ACCESS PARAMETERS (
        RECORDS DELIMITED BY NEWLINE SKIP 1
        BADFILE 'price_feed.bad' LOGFILE 'price_feed.log'
        FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
        MISSING FIELD VALUES ARE NULL)
    LOCATION ('price_feed.csv'))
REJECT LIMIT UNLIMITED;

MERGE INTO products p USING price_feed_ext f ON (p.sku = f.sku)
WHEN MATCHED THEN UPDATE SET p.unit_price = f.new_price;
```

The file is read at query time; nothing is loaded until you select from it.
Read-only, no indexes. Drivers: `ORACLE_LOADER` (text), `ORACLE_DATAPUMP`
(binary, can also unload), `ORACLE_BIGDATA` (Parquet, ORC, Avro, object
storage). **Inline external tables** (18c+) need no DDL. A directory object is a
privilege boundary: grant `READ`/`WRITE` on it sparingly.

## 7. Temporary tables

| | Global temporary table (GTT) | Private temporary table (18c+) |
|---|---|---|
| Definition | Permanent, shared | Exists only in the creating session |
| Data | Private per session | Private |
| Lifetime of rows | `ON COMMIT DELETE ROWS` or `PRESERVE ROWS` | Until transaction or session end |
| Name | Any | Must start with `ORA$PTT_` (default prefix) |
| Indexes, statistics | Yes (session-private statistics from 12c) | No indexes |
| Created by | Deployment DDL | Application at run time, no implicit commit |

```sql
CREATE GLOBAL TEMPORARY TABLE gtt_order_batch (order_id NUMBER PRIMARY KEY)
    ON COMMIT DELETE ROWS;
```

Temporary tables write to the temporary tablespace and, since 12c with
`TEMP_UNDO_ENABLED`, generate almost no redo. In Oracle you rarely need them for
query staging (CTEs and inline views do that); use them for multi-step batch
work or to bind a large id list.

## 8. Specialized structures

| Object | Purpose | Status in new designs |
|---|---|---|
| **Table cluster** (index or hash) | Stores rows of related tables in the same blocks | Rare. Hash clusters suit static lookup tables |
| **Object types** and methods | User-defined types (`CREATE TYPE`) | Mainly as collection types for PL/SQL and `TABLE()` |
| **Nested tables / VARRAY columns** | A collection stored in a column | Avoid as storage: breaks 1NF, awkward to query. Use child tables or JSON |
| **XMLType** | Native XML storage with XQuery | Where XML is required |
| **JSON** | Native JSON | [2.6](../advanced-sql/06-merge-topn-json.md) |
| **Blockchain / immutable tables** (19.10+/21c) | Insert-only, tamper-evident rows | Audit and compliance ledgers |
| **Editioning views** | Stable view over a changing table for EBR | Zero-downtime upgrades |

## 9. Common mistakes

- Views on views on views: a query for one column joins twelve tables.
- `SELECT *` in a view definition (the column list is frozen at creation; recompile after table changes).
- An MV that silently falls back to complete refresh every night.
- `NOCACHE` sequences; expecting gap-free numbers.
- Joining large local and remote tables over a database link.
- Using a GTT with `ON COMMIT DELETE ROWS` under an autocommit client.

## FreshMart example

=== "Scenario"

    The management dashboard shows sales per day and status and is opened
    hundreds of times an hour. At 100 million orders each open costs a large
    aggregation. Freshness of five minutes is acceptable.

=== "SQL"

    ```sql
    -- MV log and MV as defined in section 2, then a 5-minute refresh job:
    BEGIN
        DBMS_SCHEDULER.CREATE_JOB(
            job_name        => 'REFRESH_MV_DAILY_SALES',
            job_type        => 'PLSQL_BLOCK',
            job_action      => q'[BEGIN DBMS_MVIEW.REFRESH('MV_DAILY_SALES', method => 'F'); END;]',
            repeat_interval => 'FREQ=MINUTELY;INTERVAL=5',
            enabled         => TRUE);
    END;
    /

    -- The dashboard keeps querying the base table:
    SELECT TRUNC(order_date) AS sale_date, SUM(total_amount) AS total
    FROM   orders
    WHERE  status <> 'CANCELLED'
    GROUP  BY TRUNC(order_date)
    ORDER  BY sale_date;
    ```

=== "Result"

    On the sample data the query returns 7 rows (one per non-cancelled order
    day), for example `2025-03-01 → 639` and `2025-04-05 → 736`; the totals sum
    to 3688 (verified). With rewrite, the plan reads `MV_DAILY_SALES` (at most
    a few thousand rows per year) instead of `ORDERS`.

=== "Takeaway"

    The application did not change, the measure is defined once, and the
    database keeps the copy correct. The price is the MV log overhead on every
    order DML and a refresh job to monitor. With
    `QUERY_REWRITE_INTEGRITY = ENFORCED`, rewrite happens only while the MV is
    fresh, so decide deliberately between `STALE_TOLERATED` and a real-time MV.

## Check yourself

??? question "Interview questions"
    1. **(Intermediate)** View versus materialized view?
    2. **(Intermediate)** Why do sequences have gaps?
    3. **(Senior)** What is needed for a fast-refreshable aggregate MV? *MV logs with the right columns and options, `COUNT(*)` and `COUNT(col)` for each `SUM`, and a qualifying query; check with `EXPLAIN_MVIEW`.*
    4. **(Senior)** What does `QUERY_REWRITE_INTEGRITY` control?
    5. **(Architect)** Database links are spreading across 40 databases. Risk and alternative? *Hidden coupling, credential sprawl, distributed transactions and unpredictable plans. Replace with owned APIs, replication (GoldenGate) or events; keep links for governed batch movement.*

??? example "Exercises"
    1. Create a view of delivered orders with customer name, `WITH READ ONLY`.
    2. Create a complete-refresh MV of revenue per category and refresh it. *Staples 1300 ... Bakery 180.*
    3. Create a GTT, insert rows, commit, and observe that they are gone.

## Related

Next: [2.15 Execution plans and SQL tuning](../performance-engineering/01-execution-plans.md).
