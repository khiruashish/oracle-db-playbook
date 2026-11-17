# Stage 1 · Foundations

**For:** someone who has never worked with a database.
**Time:** 3 to 4 weeks at one hour a day.
**You need:** the lab database from [setup](setup.md) with FreshMart installed.

## What you will be able to do

- Explain what a relational database is and why it beats files and spreadsheets.
- Read and draw an ER diagram, and normalize a table to third normal form.
- Write `SELECT`, `INSERT`, `UPDATE`, `DELETE` with filters, sorting and functions.
- Join two or three tables and summarize with `GROUP BY`.
- Create tables with keys and constraints, and explain `COMMIT` and `ROLLBACK`.

## Reading order

1. [1.1 Data, databases and the RDBMS](../database-fundamentals/01-data-and-databases.md)
2. [1.2 The relational model](../database-fundamentals/02-relational-model.md)
3. [1.3 Data modeling and ER diagrams](../data-modeling/01-data-modeling.md)
4. [1.4 Normalization](../data-modeling/02-normalization.md)
5. [1.5 SELECT: reading data](../sql-fundamentals/01-select.md)
6. [1.6 NULL, expressions and functions](../sql-fundamentals/02-null-and-functions.md)
7. [1.7 DDL: tables and data types](../sql-fundamentals/03-ddl.md)
8. [1.8 DML and transactions basics](../sql-fundamentals/04-dml-and-transactions.md)
9. [1.9 Constraints and data integrity](../sql-fundamentals/05-constraints.md)
10. [1.10 Basic joins and aggregates](../sql-fundamentals/06-joins-and-aggregates.md)
11. [1.11 Your first index](../sql-fundamentals/07-first-index.md)

## Exit test

You are ready for Stage 2 when you can do all of this without notes:

- [ ] Draw the FreshMart customer, order, order item, product relationships from memory.
- [ ] Explain why `WHERE phone = NULL` returns no rows.
- [ ] Write a query listing every customer with their number of orders, including customers with none.
- [ ] Explain what happens to uncommitted changes when your session crashes.
- [ ] Finish the [Stage 1 labs](../hands-on-labs/01-stage-1.md) and score 80% on the [0-years bank](../interview-preparation/01-level-0.md).
