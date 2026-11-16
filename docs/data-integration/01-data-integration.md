---
tags: [stage-4, integration, etl, cdc]
---

# 4.5 Data movement and integration

!!! abstract "Chapter card"
    **Stage:** 4 · **Prerequisites:** 2.6, 2.14, 3.4 · **Time:** 4 hours

## At a glance

| Subtopic | In one line |
|---|---|
| Choosing a tool | SQL*Loader, external tables, Data Pump, links, GoldenGate |
| Bulk loading | Direct path, parallel, constraints and indexes during loads |
| ETL and ELT | Transform outside, or inside the database |
| Incremental loading | High-water marks, change tracking |
| Change data capture | Log-based, trigger-based, query-based |
| Validation and reconciliation | Proving the copy is right |
| Java integration | JDBC essentials (details in 4.8) |

## 1. Choosing a tool

| Need | Tool | Notes |
|---|---|---|
| Load flat files, simple and scriptable | **SQL*Loader** (`sqlldr`) | Control file describes the format; express mode for simple CSV |
| Load or query files with SQL | **External tables** | Transform while loading with `INSERT ... SELECT` / `MERGE` |
| Move schemas or tables between Oracle databases | **Data Pump** | Also over a link with `NETWORK_LINK` |
| Small, occasional cross-database queries | **Database links** | Mind coupling and plans |
| Continuous replication, low latency | **GoldenGate** | [4.2](../high-availability/04-goldengate-replication.md) |
| Files in object storage | `DBMS_CLOUD` (`COPY_DATA`, external tables) | Autonomous and recent on-premises releases |
| Application events | Transactional Event Queues, Kafka | [4.3](../distributed-databases/01-distributed.md) |
| Whole-database migration | RMAN, Data Guard, transportable tablespaces, ZDM | [3.3](../database-administration/01-administration.md) |

### SQL*Loader

```text
-- products.ctl
LOAD DATA
INFILE 'products.csv'
BADFILE 'products.bad' DISCARDFILE 'products.dsc'
APPEND INTO TABLE products_stage
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
TRAILING NULLCOLS
(sku, product_name, category_id, supplier_id,
 unit_price "TO_NUMBER(:unit_price, '9999990.99')", unit_of_measure)
```

```bash
sqlldr userid=freshmart@//dbhost/FRESHMART control=products.ctl log=products.log \
       direct=true errors=100
```

Rejected rows go to the **bad file** (database or format errors) and the
**discard file** (did not match a `WHEN` clause). Always check the log's row
counts: a load that "succeeded" with 5% rejected is a failed load.

## 2. Bulk loading techniques

| Technique | Effect | Caveat |
|---|---|---|
| **Direct-path insert**: `INSERT /*+ APPEND */ ... SELECT` | Formats blocks above the high-water mark, bypasses the buffer cache, minimal undo | Takes an exclusive table lock; the session must commit before reading the table; space below the HWM is not reused |
| `NOLOGGING` + direct path | Minimal redo | Not recoverable from older backups; ignored under `FORCE LOGGING` (Data Guard) |
| **Parallel DML** | Several PX servers load at once | `ALTER SESSION ENABLE PARALLEL DML`; EE |
| Unusable indexes, rebuild after | Avoids row-by-row index maintenance | Unique indexes cannot be skipped; rebuild cost |
| Constraints `DISABLE` then `ENABLE NOVALIDATE` / validate | Faster load | You own correctness in between |
| **Partition exchange** | Load and index a staging table, swap it in instantly | Needs partitioning |
| **DML error logging** (`LOG ERRORS INTO ... REJECT LIMIT`) | Bad rows are recorded, not fatal | Not all error types are logged in direct path |
| Array inserts from applications | Hundreds of rows per round trip | JDBC batching |

For a large initial load, the order is: create the table, load with direct
path and parallelism, **then** create indexes and constraints, then gather
statistics (online statistics gathering covers direct loads into empty
segments). :material-tag: **23ai+** relaxes several direct-load restrictions
(for example multiple loads in one transaction).

## 3. ETL and ELT

| | ETL | ELT |
|---|---|---|
| Transform | In an external engine, before loading | Inside the target database, after loading raw data |
| Strength | Database-neutral, many connectors | Set-based SQL on the database's own engine; fewer moving parts |
| Typical tools | Informatica, Talend, Spark, Oracle Data Integrator (which generates ELT) | SQL, PL/SQL, dbt, materialized views |

A common layering: **landing/staging** (raw, as received) → **cleansed**
(typed, deduplicated, validated) → **presentation** (star schema or marts,
[4.6](../data-warehousing/01-data-warehousing.md)). Keep the raw layer so loads
can be replayed.

Design every load to be **restartable and idempotent**: a control table with a
batch id and status, `MERGE` rather than blind `INSERT`, and no partial commits
that cannot be resumed.

## 4. Incremental loading

| Method | How it finds changes | Weakness |
|---|---|---|
| Timestamp high-water mark | `WHERE updated_at > :last_run` | Misses deletes; misses rows committed late (a transaction that started before the mark and committed after) |
| Sequence / id watermark | `WHERE id > :last_id` | Inserts only; same late-commit problem |
| Flashback version queries | `VERSIONS BETWEEN SCN` | Limited by undo |
| Materialized view logs | The database records changed keys | Overhead on source DML |
| Log-based CDC | Reads redo | Most complete; extra product |
| Full compare | `MINUS` or hash compare | Expensive; fine for small tables |

The late-commit problem is real: use an overlap window with idempotent
`MERGE`, or drive from SCNs (`ORA_ROWSCN`, `AS OF SCN`) rather than wall-clock
timestamps.

## 5. Change data capture

| Style | Mechanism | Latency | Source impact | Captures deletes |
|---|---|---|---|---|
| **Log-based** | Reads redo (GoldenGate, LogMiner-based tools such as Debezium, OCI GoldenGate) | Seconds | Low: supplemental logging | Yes |
| **Trigger-based** | Triggers write to change tables | Immediate | High: adds work to every transaction | Yes |
| **Query-based** | Polls with a watermark | Minutes | Query load | No |
| **MV log-based** | Materialized view logs | Refresh interval | Medium | Yes |

Patterns built on CDC: feeding a warehouse, keeping a search index or cache
current, the outbox relay, and event streaming to Kafka. Decide whether
consumers receive **table changes** (tight coupling to your schema) or
**business events** (an outbox with a designed contract).

Oracle's own "Change Data Capture" packages (`DBMS_CDC_*`) were desupported in
12c; use the options above.

## 6. Validation and reconciliation

Every pipeline needs proof, not hope.

| Check | Example |
|---|---|
| Row counts per batch and per table | Source 1,204,551 = target 1,204,551 |
| Control totals | `SUM(total_amount)` by day |
| Key completeness | Anti-joins both ways |
| Content hash | `SUM(ORA_HASH(col1 || '|' || col2 ...))` per key range or partition; drill into ranges that differ |
| Referential checks in the target | Facts without dimensions |
| Business rules | No negative stock; totals equal lines |
| Freshness | `MAX(loaded_at)` within the SLA |

```sql
-- Cheap fingerprint of a table slice: compare the two numbers across systems
SELECT COUNT(*) AS row_count,
       SUM(ORA_HASH(order_id || '|' || status || '|' || total_amount)) AS fingerprint
FROM   orders
WHERE  order_date >= DATE '2025-03-01' AND order_date < DATE '2025-04-01';
```

Store reconciliation results in a table and alert on mismatches. For
replication, GoldenGate Veridata does this continuously.

## 7. Java integration essentials

| Topic | Guidance |
|---|---|
| Driver | Oracle JDBC Thin (`ojdbc11` for Java 11+, `ojdbc17` for Java 17+ in recent releases); match or exceed the database release |
| Statements | `PreparedStatement` with binds, always |
| Batching | `addBatch()` / `executeBatch()`; batch sizes of 50 to 500 |
| Fetching | `setFetchSize` (driver default is 10 rows): raise for large reads |
| Pooling | UCP or HikariCP, small and fixed size |
| Statement caching | `oracle.jdbc.implicitStatementCacheSize` avoids repeated soft parses |
| Resilience | FAN, Application Continuity with UCP; timeouts on connect, read and query |
| Observability | Set module, action and client id (end-to-end metrics) |

Full treatment with Spring Boot in [4.8](../spring-boot-integration/01-spring-boot.md).

## 8. Common mistakes

- Row-by-row loads from application code for millions of rows.
- `NOLOGGING` loads into a database with a standby.
- Ignoring the bad file.
- Timestamp watermarks without an overlap.
- Pipelines that cannot be rerun without duplicates.
- No reconciliation: discovering a month later that 2% of rows never arrived.
- Database links as the enterprise integration bus.

## FreshMart example

=== "Scenario"

    Each night suppliers send a CSV of up to 500,000 price and catalog rows.
    Bad rows must be reported, not stop the load; a rerun must be harmless; and
    the job must finish in minutes.

=== "Pipeline"

    ```sql
    -- 1. The file is visible through an external table (2.14): price_feed_ext

    -- 2. Stage with validation, capturing rejects
    EXEC DBMS_ERRLOG.CREATE_ERROR_LOG('PRODUCTS', 'ERR$_PRODUCTS');

    -- 3. One set-based MERGE: idempotent by SKU
    MERGE INTO products p
    USING (SELECT sku, new_price
           FROM  (SELECT f.sku, f.new_price,
                         ROW_NUMBER() OVER (PARTITION BY f.sku ORDER BY ROWNUM DESC) AS rn
                  FROM   price_feed_ext f
                  WHERE  f.new_price > 0)
           WHERE  rn = 1) s                      -- deduplicate: avoids ORA-30926
    ON    (p.sku = s.sku)
    WHEN MATCHED THEN UPDATE SET p.unit_price = s.new_price
         WHERE p.unit_price <> s.new_price
    LOG ERRORS INTO err$_products ('PRICE_FEED_' || TO_CHAR(SYSDATE, 'YYYYMMDD')) REJECT LIMIT UNLIMITED;

    -- 4. Reconcile and record
    INSERT INTO load_control (batch_name, rows_in_file, rows_merged, rows_rejected, finished_at)
    SELECT 'PRICE_FEED', (SELECT COUNT(*) FROM price_feed_ext), SQL%ROWCOUNT,
           (SELECT COUNT(*) FROM err$_products), SYSTIMESTAMP FROM dual;
    COMMIT;
    ```

=== "Checks"

    | Check | Rule |
    |---|---|
    | Rows in file versus merged + unchanged + rejected | Must balance |
    | Rejected share | Alert above 1% |
    | Largest price change | Alert above 50% (possible unit error) |
    | Rerun | Second run merges 0 rows |

    Illustrative: `load_control` is a control table you create;
    `SQL%ROWCOUNT` must be captured into a variable in PL/SQL before the insert.

=== "Takeaway"

    External table + one `MERGE` + error logging gives a restartable, auditable
    load with no procedural loop. The reconciliation row is what turns "the job
    ran" into "the job was right".

## Check yourself

??? question "Interview questions"
    1. **(Intermediate)** SQL*Loader versus external tables?
    2. **(Senior)** What does a direct-path insert do differently, and what are its restrictions?
    3. **(Senior)** Compare log-based and trigger-based CDC.
    4. **(Principal)** Why can a timestamp-based incremental load miss rows?
    5. **(Architect)** How do you prove to an auditor that the warehouse matches the source? *Automated reconciliation at count, control-total and hash level per load, stored with batch ids; lineage from source to report; exception handling with ownership; periodic full compares on a sample.*

??? example "Exercises"
    1. Load a CSV of 10 products through an external table and `MERGE`.
    2. Compare conventional and `APPEND` inserts of 1 million generated rows: time and redo size.
    3. Write a reconciliation query between `orders` and a copy, by month.

## Related

Next: [4.6 Data warehousing](../data-warehousing/01-data-warehousing.md).
