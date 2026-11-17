---
tags: [interview, stage-2]
---

# Interview bank: 5 years (SQL, PL/SQL, development)

55 questions (worked ones included). Chapters: Stage 2.

## Worked questions :material-star:

### W1. Find the top product by revenue in each category. Give two solutions and compare them.

```sql
-- A: window function, one pass
SELECT category_id, product_id, revenue
FROM  (SELECT p.category_id, p.product_id, SUM(oi.line_total) AS revenue,
              ROW_NUMBER() OVER (PARTITION BY p.category_id
                                 ORDER BY SUM(oi.line_total) DESC, p.product_id) AS rn
       FROM   order_items oi
       JOIN   orders o   ON o.order_id   = oi.order_id
       JOIN   products p ON p.product_id = oi.product_id
       WHERE  o.status <> 'CANCELLED'
       GROUP  BY p.category_id, p.product_id)
WHERE  rn = 1;

-- B: aggregate with KEEP
WITH prod AS (SELECT p.category_id, p.product_id, SUM(oi.line_total) AS revenue
              FROM   order_items oi
              JOIN   orders o   ON o.order_id   = oi.order_id
              JOIN   products p ON p.product_id = oi.product_id
              WHERE  o.status <> 'CANCELLED'
              GROUP  BY p.category_id, p.product_id)
SELECT category_id,
       MAX(product_id) KEEP (DENSE_RANK FIRST ORDER BY revenue DESC) AS product_id,
       MAX(revenue) AS revenue
FROM   prod GROUP BY category_id;
```

**Result (verified).** Categories 2 to 7: products 1 (540), 3 (120), 5 (476), 8 (180), 10 (300), 11 (1300).
**Explanation.** A returns whole rows and handles "top N"; B is compact for "top 1" and needs no outer filter. A correlated subquery (`revenue = (SELECT MAX ...)`) reads the data twice and returns ties.
**Follow-ups.** How do you return ties? (`RANK`.) Top 3 per category? (`rn <= 3`.) What does the plan show? (`WINDOW SORT PUSHED RANK`.)
**Common wrong answer.** `GROUP BY category_id` with `MAX(revenue)` and a non-grouped `product_id`.

### W2. Two sessions update the same row. Describe exactly what happens.

**Answer.** The first takes a row lock (TX) and proceeds. The second waits on
`enq: TX - row lock contention`. When the first commits, the second re-reads the
row's current version, re-evaluates its `WHERE` clause, and updates it if it
still qualifies. If the first rolls back, the second proceeds on the original
row. Readers are never blocked: they see the last committed version via undo.

**Scenario.** Two checkouts reserving the last units
([2.11](../transactions/01-transactions-concurrency.md)).
**Follow-ups.** How do you avoid waiting forever? (`FOR UPDATE WAIT n` / `NOWAIT`.) What is a lost update and how do you prevent it? What changes under `SERIALIZABLE`? (`ORA-08177`.)
**Common wrong answer.** "The second update fails", or "Oracle escalates to a table lock".

### W3. Rewrite this row-by-row PL/SQL to be fast, and explain why it is faster.

```sql
FOR r IN (SELECT product_id FROM products WHERE category_id = 4) LOOP
    UPDATE inventory SET reorder_level = reorder_level + 5 WHERE product_id = r.product_id;
END LOOP;
```

**Answer.** Best: one SQL statement.

```sql
UPDATE inventory SET reorder_level = reorder_level + 5
WHERE  product_id IN (SELECT product_id FROM products WHERE category_id = 4);
```

If per-row procedural logic is unavoidable: `BULK COLLECT` the ids and `FORALL`
the update.

**Explanation.** Each SQL statement executed from PL/SQL is a context switch
between engines. The loop does one per row; the single statement does one in
total and lets the optimizer choose a join.
**Follow-ups.** What does `SAVE EXCEPTIONS` do? Why use `LIMIT`? Where should the commit go?
**Common wrong answer.** "Add a commit inside the loop to make it faster."

### W4. A query uses a full table scan although an index exists on the filtered column. List the possible reasons.

**Answer.** (1) The predicate is not selective, so a scan is cheaper. (2) A
function or implicit conversion is applied to the column. (3) Leading wildcard
`LIKE`. (4) The column is not the leading column of a composite index. (5)
`IS NULL` on a single-column B-tree index. (6) Stale or missing statistics, or
no histogram on a skewed column. (7) Poor clustering factor. (8) The index is
invisible or unusable. (9) A small table.

**Follow-ups.** How do you confirm which? (Actual plan with predicates; `E-Rows` versus `A-Rows`.) When is the full scan the right plan?
**Common wrong answer.** "Add an index hint."

### W5. What is wrong with `WHEN OTHERS THEN NULL`?

**Answer.** It hides every error, including ones nobody anticipated (space,
deadlock, constraint violations), so the caller believes the work succeeded
and data is silently wrong. Handle only exceptions you can act on; otherwise
log with `DBMS_UTILITY.FORMAT_ERROR_BACKTRACE` and `RAISE`.

**Follow-ups.** How do you log an error so the log survives the caller's rollback? (Autonomous transaction.) How do you return a business error? (`RAISE_APPLICATION_ERROR`.)

## Advanced SQL

| # | Question | Answer |
|---|---|---|
| 1 | Semi join versus inner join? | A semi join returns each outer row once if a match exists (`EXISTS`); an inner join returns one row per match. |
| 2 | Why prefer `NOT EXISTS` to `NOT IN`? | `NOT IN` returns no rows if the subquery yields a null. |
| 3 | What is a correlated subquery? | One that references the outer query; logically evaluated per outer row, usually unnested by the optimizer. |
| 4 | `RANK`, `DENSE_RANK`, `ROW_NUMBER`? | Ties share a rank with gaps; ties share without gaps; unique numbers. |
| 5 | What do `LAG` and `LEAD` do? | Return a value from a previous or following row in the window. |
| 6 | How do you compute a running total? | `SUM(x) OVER (ORDER BY ...)`, with a unique order or `ROWS` frame. |
| 7 | `ROWS` versus `RANGE` frames? | Physical row offsets versus logical value ranges; `RANGE` treats ties as peers. |
| 8 | Why can `LAST_VALUE` return the current row? | The default frame ends at the current row. |
| 9 | `ROLLUP` versus `CUBE` versus `GROUPING SETS`? | Hierarchical subtotals; all combinations; an explicit list. |
| 10 | How do you tell a subtotal null from a data null? | `GROUPING()` or `GROUPING_ID()`. |
| 11 | What does `PIVOT` group by? | Every source column not named in the pivot clause. |
| 12 | What is a CTE and is it always materialized? | A named subquery in `WITH`; no, Oracle may inline or materialize it. |
| 13 | Two ways to query a hierarchy? | `CONNECT BY PRIOR` and recursive `WITH`. |
| 14 | What causes `ORA-30926` in `MERGE`? | Several source rows matching one target row. |
| 15 | Offset versus keyset pagination? | Offset cost grows with depth; keyset is constant but sequential. |
| 16 | `JSON_VALUE` versus `JSON_QUERY`? | Returns a scalar versus a JSON fragment. |
| 17 | What is the fan-out problem? | Joining a parent to two child tables multiplies rows and inflates sums. |
| 18 | What does `LISTAGG` do and what can go wrong? | Concatenates values per group; overflow beyond the `VARCHAR2` limit (`ON OVERFLOW TRUNCATE`). |
| 19 | What is `CROSS APPLY`? | A lateral join: the right side can reference the left row. |
| 20 | How does Oracle treat an empty string? | As `NULL` in `VARCHAR2`. |

## PL/SQL

| # | Question | Answer |
|---|---|---|
| 21 | Procedure versus function? | A function returns a value and can be used in SQL; a procedure performs an action. |
| 22 | Why packages? | Encapsulation, fewer invalidations, overloading, private code, one load. |
| 23 | `%TYPE` and `%ROWTYPE`? | Anchor a variable to a column's or row's type. |
| 24 | What does `SELECT INTO` raise for 0 or many rows? | `NO_DATA_FOUND`; `TOO_MANY_ROWS`. |
| 25 | The three collection types? | Associative arrays, nested tables, VARRAYs. |
| 26 | Implicit versus explicit cursor? | Managed by Oracle for each statement versus declared, opened, fetched and closed by you. |
| 27 | What is a `REF CURSOR`? | A pointer to a result set that can be passed to a client. |
| 28 | `BULK COLLECT` and `FORALL`? | Fetch many rows, and execute one DML for many values, each in one context switch. |
| 29 | What causes a mutating table error? | A row-level trigger querying its own table. |
| 30 | Definer versus invoker rights? | Runs with the owner's or the caller's privileges. Roles are disabled in definer-rights code. |
| 31 | What is an autonomous transaction for? | Logging that must survive the caller's rollback. |
| 32 | `EXECUTE IMMEDIATE` versus `DBMS_SQL`? | Simple dynamic SQL versus statements whose binds or columns are unknown at compile time. |
| 33 | How do you prevent SQL injection in dynamic SQL? | Bind values; validate identifiers with `DBMS_ASSERT` or a whitelist. |
| 34 | What is a pipelined function? | A table function that returns rows as they are produced. |
| 35 | What is package state and why is it risky? | Session-level variables; lost on recompile (`ORA-04068`) and shared across pooled requests. |
| 36 | When are triggers appropriate? | Audit and technical columns; not business workflows. |
| 37 | What does `DETERMINISTIC` promise? | Same inputs give the same output; enables caching and function-based indexes. |
| 38 | How do you test PL/SQL? | utPLSQL suites run in CI against a disposable database. |

## Design, concurrency, tuning

| # | Question | Answer |
|---|---|---|
| 39 | Which isolation levels does Oracle offer? | `READ COMMITTED`, `SERIALIZABLE`, `READ ONLY`. No dirty reads ever. |
| 40 | Optimistic versus pessimistic locking? | Detect conflicts with a version check at write time versus lock on read with `FOR UPDATE`. |
| 41 | What does Oracle do on a deadlock? | Rolls back one statement with `ORA-00060`; the application must roll back and retry. |
| 42 | Column order in a composite index? | Equality columns first, then range or sort columns. |
| 43 | What is a function-based index? | An index on an expression, used when the query has the same expression. |
| 44 | When are bitmap indexes wrong? | On tables with concurrent DML. |
| 45 | View versus materialized view? | A stored query versus a stored result refreshed by the database. |
| 46 | Why partition a table? | Manageability (purge, maintenance), pruning, availability. |
| 47 | Local versus global index? | One index partition per table partition versus one structure across all. |
| 48 | `EXPLAIN PLAN` versus `DISPLAY_CURSOR`? | Predicted plan versus the plan that ran. |
| 49 | Access versus filter predicate? | Used to locate rows versus applied after fetching them. |
| 50 | Why use bind variables? | Cursor sharing (no hard parse per value) and protection from SQL injection. |
