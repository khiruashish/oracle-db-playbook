---
tags: [stage-2, partitioning, performance]
---

# 2.13 Partitioning

!!! abstract "Chapter card"
    **Stage:** 2 (sections 1 to 5), 3 and 4 (sections 6 to 9) · **Prerequisites:** 2.12 · **Time:** 4 hours ·
    :material-license: **Enterprise Edition + Partitioning option**

## At a glance

**Partitioning** splits one large table into smaller physical pieces
(partitions) while applications still see one table.

| Subtopic | In one line |
|---|---|
| Range, list, hash | The three basic strategies |
| Interval | Range partitions created automatically |
| Composite | Partition, then subpartition |
| Reference and system | Child follows parent; application-chosen partition |
| Partition pruning | Skip partitions that cannot hold the rows |
| Partition-wise joins | Join matching partitions pair by pair |
| Local and global indexes | Index design for partitioned tables |
| Maintenance | Add, drop, truncate, split, merge, exchange, move |
| Lifecycle | Compress, move to cheaper storage, archive, purge |

## 1. Why partition

| Goal | How partitioning helps |
|---|---|
| **Manageability** | Drop a month of old data as a metadata operation instead of deleting 50M rows |
| **Performance** | Queries with the partition key read only relevant partitions |
| **Availability** | Maintain or recover one partition while others stay available |
| **Lifecycle** | Old partitions compressed, read-only, on cheaper storage |

Partitioning is **not** a general speed-up. An OLTP lookup by primary key is no
faster on a partitioned table, and a query without the partition key can be
slower. Partition when a table is large (tens of GB and growing), has a natural
key for pruning or purging (usually a date), or needs lifecycle management.

## 2. Strategies

=== "Range / interval"

    ```sql
    CREATE TABLE orders_p (
        order_id     NUMBER(12) NOT NULL,
        customer_id  NUMBER(10) NOT NULL,
        order_date   DATE       NOT NULL,
        status       VARCHAR2(12),
        total_amount NUMBER(12,2)
    )
    PARTITION BY RANGE (order_date)
    INTERVAL (NUMTOYMINTERVAL(1, 'MONTH'))
    (PARTITION p_before_2025 VALUES LESS THAN (DATE '2025-01-01'));
    ```

    Range bounds are **exclusive** upper limits. With `INTERVAL`, Oracle creates
    a partition the first time a row arrives for a new month, so loads never
    fail for lack of a partition. Best for time-series data.

=== "List"

    ```sql
    PARTITION BY LIST (city)
    (PARTITION p_mumbai    VALUES ('Mumbai'),
     PARTITION p_bengaluru VALUES ('Bengaluru'),
     PARTITION p_other     VALUES (DEFAULT))
    ```

    For discrete values: region, tenant, status. `AUTOMATIC` list partitioning
    (12.2+) creates a partition per new value. Multi-column list is 12.2+.

=== "Hash"

    ```sql
    PARTITION BY HASH (customer_id) PARTITIONS 16
    ```

    Spreads rows evenly when there is no natural range. Use a power of two.
    Relieves insert contention and enables partition-wise joins; gives pruning
    only for equality predicates and no lifecycle benefit.

=== "Composite"

    ```sql
    PARTITION BY RANGE (order_date) INTERVAL (NUMTOYMINTERVAL(1, 'MONTH'))
    SUBPARTITION BY HASH (customer_id) SUBPARTITIONS 8
    (PARTITION p_before_2025 VALUES LESS THAN (DATE '2025-01-01'))
    ```

    Range for lifecycle and pruning, hash underneath for parallel joins and
    even spread. Any pair of range, list and hash is allowed.

### Reference and system partitioning

**Reference partitioning** partitions a child by its foreign key, so it
inherits the parent's partitioning even though the child lacks the key column:

```sql
CREATE TABLE order_items_p (
    order_id   NUMBER(12) NOT NULL,
    line_no    NUMBER(4)  NOT NULL,
    product_id NUMBER(10) NOT NULL,
    quantity   NUMBER(5)  NOT NULL,
    CONSTRAINT pk_order_items_p PRIMARY KEY (order_id, line_no),
    CONSTRAINT fk_oip_order FOREIGN KEY (order_id) REFERENCES orders_p (order_id)
)
PARTITION BY REFERENCE (fk_oip_order);
```

Dropping a month from `orders_p` drops the matching items too, and joins between
the two are partition-wise. It needs an enforced primary key on the parent.

**System partitioning** has no key: the application names the partition on
insert. Rare; used by some packaged features.

Other variants: **virtual column** partitioning (partition on an expression),
**hybrid partitioned tables** (19c+: some partitions internal, some external
files), and partitioned external tables.

## 3. Partition pruning

```sql
SELECT SUM(total_amount) FROM orders_p
WHERE  order_date >= DATE '2025-03-01' AND order_date < DATE '2025-04-01';
```

*Illustrative plan:*

```text
| Id | Operation               | Name     | Pstart| Pstop |
|  0 | SELECT STATEMENT        |          |       |       |
|  1 |  SORT AGGREGATE         |          |       |       |
|  2 |   PARTITION RANGE SINGLE|          |     4 |     4 |
|  3 |    TABLE ACCESS FULL    | ORDERS_P |     4 |     4 |
```

`Pstart`/`Pstop` show which partitions are read. `KEY` means decided at run
time (bind variables, joins). `PARTITION RANGE ALL` means no pruning.

Pruning is lost when the partition key is wrapped in a function
(`TRUNC(order_date) = ...`, `TO_CHAR(order_date, ...)`) or compared with a
different data type.

## 4. Partition-wise joins

When two tables are partitioned the same way on the join key, Oracle joins
partition 1 to partition 1, 2 to 2, and so on. Each small join fits in memory
and the pairs can run in parallel. **Full** partition-wise joins need both
sides equipartitioned; **partial** ones redistribute one side at run time.

## 5. Indexes on partitioned tables

See the comparison in [2.12](../indexing/01-indexing.md). Decision guide:

| Situation | Choose |
|---|---|
| Queries always include the partition key | Local index |
| Unique key that does not contain the partition key (`order_id` on a date-partitioned table) | Global index (or global hash-partitioned) |
| Frequent drop/exchange of partitions | Local indexes; for global ones use `UPDATE INDEXES` (asynchronous global index maintenance from 12c makes drop/truncate fast) |
| OLTP lookup by non-partition key | Global index |

A local index is **prefixed** when its leading column is the partition key. A
non-prefixed local index probed without the partition key must visit every
index partition.

## 6. Maintenance operations

```sql
ALTER TABLE orders_p ADD PARTITION ...;                          -- range without interval
ALTER TABLE orders_p TRUNCATE PARTITION FOR (DATE '2023-01-15') UPDATE INDEXES;
ALTER TABLE orders_p SPLIT PARTITION p_before_2025 AT (DATE '2024-01-01')
      INTO (PARTITION p_before_2024, PARTITION p_2024) ONLINE;
ALTER TABLE orders_p MERGE PARTITIONS p_2023_01, p_2023_02 INTO PARTITION p_2023_q1a;
ALTER TABLE orders_p MOVE PARTITION p_2024 TABLESPACE archive_ts
      ROW STORE COMPRESS ADVANCED ONLINE UPDATE INDEXES;
ALTER TABLE orders_p MODIFY PARTITION p_2024 READ ONLY;          -- 12.2+
```

!!! danger "Destructive"
    `DROP PARTITION` and `TRUNCATE PARTITION` remove data without undo: they
    are DDL. They need a verified backup or archive copy and an approved change.
    Dropped partitions do not go to the recycle bin.

| Online capability | Release |
|---|---|
| `MOVE PARTITION ... ONLINE` | 12.1 |
| `SPLIT`, `MERGE ... ONLINE`; convert a non-partitioned table: `ALTER TABLE ... MODIFY PARTITION BY ... ONLINE` | 12.2 |
| Change the partitioning strategy of a partitioned table online | 18c |

### Partition exchange

`EXCHANGE PARTITION` swaps a partition with a standalone table by updating the
dictionary only: no rows move.

```sql
CREATE TABLE orders_2023_01_arch FOR EXCHANGE WITH TABLE orders_p;   -- 12.2+: exact shape

ALTER TABLE orders_p
    EXCHANGE PARTITION FOR (DATE '2023-01-15')
    WITH TABLE orders_2023_01_arch
    INCLUDING INDEXES WITHOUT VALIDATION;
```

Uses: **loading** (build and index a staging table offline, swap it in
instantly) and **archiving** (swap a partition out, then export or move the
standalone table). `WITHOUT VALIDATION` trusts that the rows belong in the
partition; use it only when the load guarantees that.

## 7. Lifecycle management

| Age | Typical treatment |
|---|---|
| Current months | Uncompressed or OLTP-compressed, fast storage, all indexes |
| Older than 1 year | `MOVE ... COMPRESS`, read-only tablespace, fewer indexes (partial indexing) |
| Older than 3 years | Exchange out to an archive table, Data Pump export, or a hybrid external partition |
| Past legal retention | `DROP PARTITION` |

**Automatic Data Optimization (ADO)** with **Heat Map** automates the first
steps by policy (Advanced Compression option):

```sql
ALTER TABLE orders_p ILM ADD POLICY
    ROW STORE COMPRESS ADVANCED SEGMENT AFTER 12 MONTHS OF NO MODIFICATION;
```

Read-only partitions in read-only tablespaces need to be backed up only once,
which shrinks backup windows.

## 8. Design guidance

- Choose the key from the **purge and query pattern**, usually the business date.
- Aim for partitions large enough to matter (GBs) and few enough to manage (hundreds to low thousands; many thousands slow parsing and DDL).
- Keep statistics **incremental** on large partitioned tables so global statistics do not require a full scan ([3.6](../performance-engineering/02-optimizer-statistics-spm.md)).
- A primary key on a partitioned table needs either the partition key in it (local) or a global index.
- Updating the partition key moves the row between partitions and requires `ENABLE ROW MOVEMENT`.

## 9. Common mistakes

- Partitioning small tables, or partitioning "for performance" without a pruning predicate.
- Functions on the partition key in queries.
- Global indexes left `UNUSABLE` after partition DDL without `UPDATE INDEXES`.
- Too many partitions (daily with hash subpartitions over ten years).
- Forgetting the licence: any partitioned object in EE needs the option, and SE2 has none.

## FreshMart example

=== "Scenario"

    At 10 million customers FreshMart writes about 15 million orders and 60
    million order items a month. Order history must stay online for 2 years and
    be retained for 7. Nightly deletes of expired rows no longer finish.

=== "Design"

    ```sql
    CREATE TABLE orders (
        ...same columns...,
        CONSTRAINT pk_orders PRIMARY KEY (order_id) USING INDEX GLOBAL
    )
    PARTITION BY RANGE (order_date) INTERVAL (NUMTOYMINTERVAL(1, 'MONTH'))
    (PARTITION p_initial VALUES LESS THAN (DATE '2025-01-01'));

    -- Children follow the parent
    CREATE TABLE order_items ( ... ) PARTITION BY REFERENCE (fk_order_items_order);

    -- Customer history: local, prefixed by the access pattern
    CREATE INDEX ix_orders_cust_date ON orders (customer_id, order_date DESC) LOCAL;
    ```

=== "Operations"

    | Task | Command | Cost |
    |---|---|---|
    | Monthly purge after 7 years | `DROP PARTITION ... UPDATE GLOBAL INDEXES` | Seconds; index cleanup asynchronous |
    | Compress months older than 12 | `MOVE PARTITION ... COMPRESS ONLINE` | Background, online |
    | Monthly revenue report | Prunes to one partition | Reads about 1/84 of the table |
    | Lookup by `order_id` | Global unique index | Same as unpartitioned |

    Illustrative figures based on the stated assumptions.

=== "Takeaway"

    The win is operational: purge becomes a metadata change and old data
    becomes cheap. The customer-history index is local, so a query for one
    customer without a date range probes many index partitions; the page
    therefore always sends a date range (last 24 months). Design the access
    path and the partitioning together.

## Check yourself

??? question "Interview questions"
    1. **(Intermediate)** Range versus list versus hash: when each?
    2. **(Intermediate)** What is partition pruning and how do you confirm it? *`Pstart`/`Pstop` in the plan.*
    3. **(Senior)** Local versus global index trade-offs?
    4. **(Senior)** How does partition exchange load data with near-zero impact?
    5. **(Architect)** When does partitioning hurt? *Small tables; queries lacking the key against local indexes; too many partitions; operational complexity and licence cost with no purge or pruning benefit.*

??? example "Exercises"
    1. Create `orders_p` and load it from `orders`. How many partitions exist? *Three: the initial one plus March and April 2025.*
       ```sql
       INSERT INTO orders_p SELECT order_id, customer_id, order_date, status, total_amount FROM orders;
       SELECT partition_name, high_value FROM user_tab_partitions WHERE table_name = 'ORDERS_P';
       ```
    2. Show pruning for a March query with `EXPLAIN PLAN`.
    3. Exchange the March partition with an empty table and verify the row counts.

## Related

Next: [2.14 Views, MVs and other objects](../database-objects/01-database-objects.md).
