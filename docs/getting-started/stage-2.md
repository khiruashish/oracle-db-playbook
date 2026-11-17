# Stage 2 · Developer

**For:** developers and junior DBAs with working SQL knowledge (roughly the 5-year level).
**Time:** about 8 weeks. **Prerequisite:** the Stage 1 exit test.

## What you will be able to do

- Solve reporting problems with window functions, CTEs, `PIVOT` and grouping extensions.
- Write PL/SQL packages with bulk processing, proper exception handling and safe dynamic SQL.
- Reason about locks, isolation levels and deadlocks.
- Choose the right index and partitioning strategy and prove it with an execution plan.

## Reading order

**Advanced SQL** [2.1](../advanced-sql/01-joins.md) ·
[2.2](../advanced-sql/02-subqueries-set-operators.md) ·
[2.3](../advanced-sql/03-cte-hierarchical.md) ·
[2.4](../advanced-sql/04-aggregation-pivot.md) ·
[2.5](../advanced-sql/05-window-functions.md) ·
[2.6](../advanced-sql/06-merge-topn-json.md)

**PL/SQL** [2.7](../plsql/01-fundamentals.md) ·
[2.8](../plsql/02-cursors-collections-bulk.md) ·
[2.9](../plsql/03-subprograms-packages-triggers.md) ·
[2.10](../plsql/04-exceptions-dynamic-advanced.md)

**Design** [2.11 Transactions](../transactions/01-transactions-concurrency.md) ·
[2.12 Indexing](../indexing/01-indexing.md) ·
[2.13 Partitioning](../partitioning/01-partitioning.md) ·
[2.14 Objects](../database-objects/01-database-objects.md) ·
[2.15 Execution plans](../performance-engineering/01-execution-plans.md)

## Exit test

- [ ] Write "top product per category by revenue" three ways (window function, correlated subquery, `KEEP DENSE_RANK`).
- [ ] Explain why Oracle readers never block writers.
- [ ] Rewrite a row-by-row PL/SQL loop with `BULK COLLECT` and `FORALL`, and say why it is faster.
- [ ] Given a plan, identify the join method, the access path and the step with the wrong row estimate.
- [ ] Finish the [Stage 2 labs](../hands-on-labs/02-stage-2.md) and the [coding challenges](../interview-preparation/06-coding-challenges.md).
