---
tags: [stage-2, indexing, performance]
---

# 2.12 Indexing

!!! abstract "Chapter card"
    **Stage:** 2 (sections 1 to 6), 3 (sections 7 to 9) · **Prerequisites:** 1.11 · **Time:** 5 hours

## At a glance

| Subtopic | In one line |
|---|---|
| B-tree, unique and non-unique | The default index |
| Composite indexes | Column order decides usefulness |
| Access paths | Unique, range, skip, full and fast full scans |
| Selectivity and clustering factor | Why an index is or is not chosen |
| Function-based, descending, reverse-key, invisible | Variations on B-tree |
| Bitmap indexes | Low-cardinality columns in warehouses |
| Index-organized tables | The table **is** the index |
| Local and global indexes | Indexes on partitioned tables |
| Text, JSON, spatial, vector | Domain and specialized indexes |
| Maintenance | Rebuild, coalesce, monitoring usage |

## 1. B-tree indexes

Structure and basics are in [1.11](../sql-fundamentals/07-first-index.md). Facts
to add:

- **Unique** index: one rowid per key. **Non-unique**: the rowid is part of the key, so entries are still ordered.
- Entirely-null keys are **not stored**. `WHERE col IS NULL` cannot use a single-column B-tree index. Workaround: `CREATE INDEX ix ON t (col, 0)`.
- Index height (`BLEVEL` + 1) is usually 2 to 4 even for huge tables.
- Deleted entries leave free space that is reused only by values in the same key range.

## 2. Composite indexes

`CREATE INDEX ix_orders_cust_date ON orders (customer_id, order_date DESC);`

An index on `(a, b, c)` is sorted by `a`, then `b`, then `c`, like a phone book
sorted by surname, then first name.

| Predicate | Index usable? |
|---|---|
| `a = ?` | Yes |
| `a = ? AND b = ?` | Yes, both columns narrow the range |
| `a = ? AND c = ?` | Yes on `a`; `c` is only a filter inside the range |
| `b = ?` | Not for a range scan (skip scan possible if `a` has few values) |
| `a = ? AND b > ?` | Yes |
| `a > ? AND b = ?` | Range on `a`; `b` only filters |

**Design rule:** equality columns first, then the range or sort column, then
any extra columns you want to cover.

For *"Rahul's latest orders"* (`WHERE customer_id = :c ORDER BY order_date DESC
FETCH FIRST 10 ROWS ONLY`) the index above gives equality on `customer_id`,
already-sorted dates (no sort step), and a stop after 10 entries.

A **covering index** contains every column the query needs, so the table is not
visited at all (no `TABLE ACCESS BY INDEX ROWID`).

## 3. Access paths

| Plan operation | What happens | Typical trigger |
|---|---|---|
| `INDEX UNIQUE SCAN` | One key, at most one row | Equality on all columns of a unique index |
| `INDEX RANGE SCAN` | Walk leaf blocks between two keys | `=` on non-unique, `<`, `>`, `BETWEEN`, `LIKE 'abc%'` |
| `INDEX SKIP SCAN` | Probe once per distinct leading value | Leading column missing and low-cardinality |
| `INDEX FULL SCAN` | Read all leaves in key order, single-block reads | Avoid a sort; all needed columns in the index |
| `INDEX FAST FULL SCAN` | Read all index blocks unordered, multiblock | Index used as a "thin table", for example `COUNT(*)` |
| `TABLE ACCESS BY INDEX ROWID [BATCHED]` | Fetch table rows for the rowids found | Columns needed that are not in the index |
| `TABLE ACCESS FULL` | Read every block below the high-water mark | No useful index, or too many rows wanted |

## 4. Selectivity, cardinality, clustering factor

- **Selectivity** = rows matched ÷ total rows. Lower is more selective.
- **Cardinality** = the optimizer's estimate of rows returned by a step.
- **Clustering factor** measures how well the table's physical row order follows the index order. It ranges from the number of table *blocks* (perfect: neighbors in the index are neighbors in the table) to the number of *rows* (worst: every entry points to a different block).

A range scan for 1,000 rows costs about 1,000 table block reads with a poor
clustering factor, and perhaps 10 with a good one. This is the usual reason the
optimizer rejects an index that "should" be used. You cannot fix it by
rebuilding the index; only reordering the table (or an IOT, or attribute
clustering) changes it.

```sql
SELECT index_name, blevel, leaf_blocks, distinct_keys, clustering_factor, num_rows
FROM   user_indexes WHERE table_name = 'ORDERS';
```

## 5. B-tree variations

| Type | Syntax | Use | Caveat |
|---|---|---|---|
| Function-based | `CREATE INDEX ix ON products (UPPER(product_name))` | Queries that apply the same expression | The query must use the identical expression; function must be deterministic |
| Descending | `(customer_id, order_date DESC)` | Mixed-direction `ORDER BY a ASC, b DESC` | Not needed for a single direction: indexes scan both ways |
| Reverse-key | `CREATE INDEX ix ON t (id) REVERSE` | Spreads inserts of a sequence key across leaves to relieve "right-hand" contention (mainly RAC) | No range scans. Hash partitioning or scalable sequences are often better |
| Invisible | `CREATE INDEX ... INVISIBLE` / `ALTER INDEX ix INVISIBLE` | Test adding or removing an index safely; it is maintained but ignored by the optimizer | Still costs DML |
| Compressed | `COMPRESS n` / `COMPRESS ADVANCED LOW` | Repeating leading columns | Advanced index compression needs the Advanced Compression option |
| Partial (12c+) | `INDEXING OFF` on some partitions + `INDEXING PARTIAL` | Index only hot partitions | Partitioned tables only |
| Virtual column index | Index a virtual column | Same as function-based, with a name | |

Conditional (filtered) indexes are done with a function that returns null for
rows to exclude, since null keys are not stored:

```sql
-- Only open orders are indexed: tiny index, perfect for the work queue
CREATE INDEX ix_orders_open ON orders (CASE WHEN status IN ('PLACED','PACKED') THEN order_date END);
```

## 6. Bitmap indexes

A bitmap index stores, for each distinct value, a bitmap with one bit per row.
Bitmaps for several conditions combine with fast AND/OR operations.

```sql
CREATE BITMAP INDEX bx_fact_sales_status ON fact_sales (order_status);
```

| Good for | Bad for |
|---|---|
| Low-cardinality columns in data warehouses | OLTP tables with concurrent DML |
| Many ad hoc `AND` / `OR` combinations | Columns updated frequently |
| Star transformation; counting | |

One bitmap entry covers a range of rows, so changing one row **locks many
rows**. Concurrent DML on a bitmap-indexed table produces blocking and
deadlocks. Bitmap indexes are an Enterprise Edition feature.

## 7. Index-organized tables (IOT)

In an IOT the rows are stored in the primary key B-tree itself.

```sql
CREATE TABLE cart_items_iot (
    cart_id NUMBER, product_id NUMBER, quantity NUMBER,
    CONSTRAINT pk_cart_items_iot PRIMARY KEY (cart_id, product_id)
) ORGANIZATION INDEX;
```

Use for narrow tables always accessed by primary key (association tables,
lookups): one structure instead of two, and rows with the same leading key are
physically together. Costs: secondary indexes are larger and slower (logical
rowids), and wide rows need an overflow segment.

## 8. Indexes on partitioned tables

| | Local index | Global index |
|---|---|---|
| Structure | One index partition per table partition | One tree (or its own partitioning) across all table partitions |
| Partition maintenance (drop, exchange) | Affects only that index partition | Becomes unusable unless `UPDATE INDEXES` / asynchronous maintenance |
| Unique constraint | Only if the partition key is part of the index | Any columns |
| Queries without the partition key | Must probe every index partition | One probe |
| Typical use | Data warehouses, time-series | OLTP lookups by a non-partition key |

Details in [2.13](../partitioning/01-partitioning.md).

## 9. Specialized indexes

| Index | For | Created with |
|---|---|---|
| Oracle Text | Full-text search: words, stemming, fuzzy | `INDEXTYPE IS CTXSYS.CONTEXT`; :material-tag: **23ai+** `CREATE SEARCH INDEX` |
| JSON search / multivalue | Paths and array values in JSON | [2.6](../advanced-sql/06-merge-topn-json.md) |
| Spatial | Geometry (nearest warehouse) | `INDEXTYPE IS MDSYS.SPATIAL_INDEX_V2` |
| Vector (HNSW, IVF) | Approximate similarity search | :material-tag: **23ai+**, [4.7](../oracle-26ai/01-oracle-26ai.md) |
| Domain index | The extensibility framework behind the above | |

**Automatic indexing** (19c+) creates and validates indexes from the workload by
itself, but only on Exadata and Autonomous Database.

## 10. Maintenance

| Question | Answer |
|---|---|
| Rebuild indexes regularly? | **No.** B-trees stay balanced. Routine rebuilds cost redo and locks and the index soon returns to its steady state |
| When to rebuild | After a mass delete that will not be refilled, to move tablespace, to change compression, or when unusable |
| Rebuild versus coalesce | `REBUILD [ONLINE]` creates a new structure (needs double space; `ONLINE` is EE). `COALESCE` merges adjacent sparse leaf blocks in place, online, with less redo |
| Is the index used? | `DBA_INDEX_USAGE` (12.2+) records access counts. Make an index invisible for a full business cycle before dropping it |
| Unusable indexes | `SELECT index_name FROM user_indexes WHERE status = 'UNUSABLE'` after direct loads or partition operations |

```sql
ALTER INDEX ix_orders_status_date REBUILD ONLINE;
ALTER INDEX ix_orders_status_date COALESCE;
ALTER INDEX ix_orders_status_date INVISIBLE;
```

## 11. Performance and production guidance

- Every index adds redo, undo and latching to each DML. On hot insert tables, count indexes carefully.
- Create indexes on large tables with `ONLINE` (EE) and consider `PARALLEL` then reset to `NOPARALLEL`.
- Gather statistics is automatic on index creation.
- Redundant indexes: `(a)` is redundant when `(a, b)` exists, unless it is unique.
- Index foreign keys ([1.9](../sql-fundamentals/05-constraints.md)).

## 12. Common mistakes

- Indexing each column separately instead of one composite index per query pattern.
- Wrong column order (range column first).
- Function on the column, or implicit type conversion, disabling the index.
- Bitmap indexes in OLTP.
- Rebuilding on a schedule and dropping "unused" indexes that enforce foreign keys or constraints.

## FreshMart example

=== "Scenario"

    The "My orders" page shows a customer's 10 most recent orders. At 5 million
    orders it has become slow. The query:

    ```sql
    SELECT order_id, order_date, status, total_amount
    FROM   orders
    WHERE  customer_id = :cust
    ORDER  BY order_date DESC
    FETCH  FIRST 10 ROWS ONLY;
    ```

=== "Index options"

    | Index | Behavior |
    |---|---|
    | None | Full scan of 5M rows, then sort |
    | `(customer_id)` | Range scan of all the customer's orders, fetch each row, then sort |
    | `(customer_id, order_date DESC)` | Range scan in the right order; stop after 10 entries; 10 table visits |
    | `(customer_id, order_date DESC, status, total_amount, order_id)` | Same, and no table visits at all (covering) |

=== "Plan"

    *Illustrative plan with `ix_orders_cust_date` (not executed):*

    ```text
    | Id | Operation                     | Name                |
    |  0 | SELECT STATEMENT              |                     |
    |* 1 |  VIEW                         |                     |
    |* 2 |   WINDOW NOSORT STOPKEY       |                     |
    |  3 |    TABLE ACCESS BY INDEX ROWID| ORDERS              |
    |* 4 |     INDEX RANGE SCAN          | IX_ORDERS_CUST_DATE |
       4 - access("CUSTOMER_ID"=:CUST)
    ```

    `NOSORT STOPKEY` is the proof: no sort, and the scan ends after 10 rows.

=== "Takeaway"

    The third option is what FreshMart ships. The covering index is faster
    still, but it is wide and must be maintained on every order insert and
    status change; add it only if measurements show the table visits matter.

## Check yourself

??? question "Interview questions"
    1. **(Intermediate)** How do you decide the column order of a composite index?
    2. **(Intermediate)** Why might the optimizer choose a full scan when an index exists?
    3. **(Senior)** What is the clustering factor and can a rebuild improve it? *No; it depends on table row order.*
    4. **(Senior)** Why are bitmap indexes dangerous in OLTP?
    5. **(Architect)** A table has 23 indexes and inserts are slow. Method? *Measure usage with `DBA_INDEX_USAGE`, find redundant prefixes, map each index to a query or constraint, make candidates invisible for a cycle, drop, and put index review into the change process.*

??? example "Exercises"
    1. Which index supports `WHERE status = 'PLACED' ORDER BY order_date`? *`ix_orders_status_date`.*
    2. Create an invisible index on `payments (status, paid_at)` and test it with `ALTER SESSION SET optimizer_use_invisible_indexes = TRUE`.
    3. Write a function-based index for case-insensitive email lookup and the query that uses it.

## Related

Next: [2.13 Partitioning](../partitioning/01-partitioning.md).
