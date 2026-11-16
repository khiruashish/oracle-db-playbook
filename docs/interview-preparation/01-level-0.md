---
tags: [interview, stage-1]
---

# Interview bank: 0 years (foundations)

55 questions (worked ones included). Chapters: Stage 1.

## Worked questions :material-star:

### W1. What is the difference between `WHERE` and `HAVING`?

**Answer.** `WHERE` filters rows before grouping. `HAVING` filters groups after
aggregation.

**Explanation.** A query is evaluated FROM → WHERE → GROUP BY → HAVING →
SELECT → ORDER BY. Aggregates do not exist yet when `WHERE` runs.

```sql
SELECT city, COUNT(*) AS customers
FROM   customers
WHERE  status = 'ACTIVE'          -- row filter
GROUP  BY city
HAVING COUNT(*) >= 2;             -- group filter
```

On FreshMart: Mumbai 3 (Delhi has 2 customers but one is inactive, so it drops out).

**Scenario.** A report of "cities with at least 2 active customers".
**Follow-ups.** Can `HAVING` be used without `GROUP BY`? (Yes: the whole result is one group.) Which is cheaper for a non-aggregate condition? (`WHERE`.)
**Common wrong answer.** "They are the same, `HAVING` is just for `GROUP BY` queries", or writing `WHERE COUNT(*) > 1`.

### W2. Why does `WHERE phone = NULL` return no rows?

**Answer.** `NULL` means unknown. Any comparison with it is unknown, not true,
and `WHERE` keeps only true. Use `IS NULL`.

```sql
SELECT COUNT(*) FROM customers WHERE phone = NULL;    -- 0
SELECT COUNT(*) FROM customers WHERE phone IS NULL;   -- 2
```

**Follow-ups.** What does `COUNT(phone)` return? (4: non-null values.) Is an empty string null in Oracle? (Yes, for `VARCHAR2`.) Why is `NOT IN` dangerous with nulls?
**Common wrong answer.** "NULL equals zero or a blank."

### W3. Explain primary key, unique key and foreign key.

**Answer.** A primary key identifies each row: unique and not null, one per
table. A unique key also forbids duplicates but allows nulls, and a table can
have several. A foreign key requires its value to exist as a key in the parent
table (or be null).

**Scenario.** `customers.customer_id` (PK), `customers.email` (unique),
`orders.customer_id` (FK).
**Follow-ups.** Can a foreign key reference a unique key? (Yes.) What happens when you delete a parent with children? (Refused, unless `ON DELETE CASCADE` or `SET NULL`.) Does Oracle index foreign keys automatically? (No.)
**Common wrong answer.** "A foreign key must reference a primary key" and "a table can have many primary keys".

### W4. What happens to your changes if you do not commit?

**Answer.** They are visible only to your session and hold their row locks.
On `ROLLBACK`, or if the session ends abnormally, they are undone. Other
sessions see the last committed data throughout.

**Follow-ups.** Does DDL commit? (Yes, implicitly.) What does a normal exit from SQL*Plus do? (Commits by default.) What is autocommit?
**Common wrong answer.** "Other users see the changes but they are not permanent."

### W5. Write a query listing every customer and their number of orders, including customers with none.

```sql
SELECT c.customer_id, c.customer_name, COUNT(o.order_id) AS total_orders
FROM   customers c
LEFT   JOIN orders o ON o.customer_id = c.customer_id
GROUP  BY c.customer_id, c.customer_name
ORDER  BY total_orders DESC, c.customer_id;
```

**Explanation.** `LEFT JOIN` keeps customers without orders; `COUNT(o.order_id)`
counts only matched rows, so Neha shows 0. `COUNT(*)` would show 1.
**Follow-ups.** What changes with an inner join? (Neha disappears.) How would you list only customers with no orders?
**Common wrong answer.** Inner join; or `COUNT(*)`.

## Database fundamentals

| # | Question | Answer |
|---|---|---|
| 1 | What is a database? | An organized collection of data stored so it can be retrieved, changed and trusted. |
| 2 | What is a DBMS? An RDBMS? | Software that manages a database. An RDBMS stores data in related tables and is queried with SQL. |
| 3 | Data versus information? | Data are raw facts; information is data in context that answers a question. |
| 4 | Name three problems of storing business data in files. | Redundancy and inconsistency, no safe concurrent access, no integrity rules, weak security, no crash recovery. |
| 5 | What is a table, a row, a column? | A named set of rows; one item; one typed attribute. |
| 6 | What is a schema in Oracle? | The collection of objects owned by a database user. |
| 7 | What is the data dictionary? | Read-only tables and views describing the database itself: `USER_TABLES`, `ALL_OBJECTS`, `DBA_USERS`. |
| 8 | What is SQL? Is it procedural? | The standard declarative language for relational databases: you state what you want, not how. |
| 9 | Name the SQL statement categories. | DQL (SELECT), DML, DDL, DCL, TCL. |
| 10 | OLTP versus OLAP? | Many short transactions on current data versus few long analytical queries on history. |

## Relational model and design

| # | Question | Answer |
|---|---|---|
| 11 | What is a candidate key? | A minimal set of columns that uniquely identifies a row. One becomes the primary key. |
| 12 | Natural versus surrogate key? | Business-meaningful versus generated and meaningless. Surrogates are stable; keep a unique constraint on the natural key. |
| 13 | What is a composite key? | A key of more than one column, such as `(order_id, line_no)`. |
| 14 | What is referential integrity? | Every foreign key value matches an existing parent key or is null. |
| 15 | Name the three relationship cardinalities. | One-to-one, one-to-many, many-to-many. |
| 16 | How is many-to-many implemented? | With an associative table holding a foreign key to each side. |
| 17 | What is normalization? | Organizing tables so each fact is stored once, removing update, insert and delete anomalies. |
| 18 | State 1NF, 2NF, 3NF briefly. | Atomic values and a key; no dependency on part of the key; no dependency on non-key columns. |
| 19 | What is denormalization and why do it? | Deliberate redundancy to speed reads, at the cost of extra maintenance. |
| 20 | What is an ER diagram? | A drawing of entities, their attributes and relationships. |

## Basic SQL

| # | Question | Answer |
|---|---|---|
| 21 | Order of clauses in a `SELECT`? | SELECT, FROM, WHERE, GROUP BY, HAVING, ORDER BY, then FETCH. |
| 22 | What does `DISTINCT` do? | Removes duplicate rows from the result. |
| 23 | `BETWEEN 10 AND 20`: inclusive? | Yes, both ends. |
| 24 | Wildcards in `LIKE`? | `%` any string, `_` one character. |
| 25 | How do you sort descending with nulls last? | `ORDER BY col DESC NULLS LAST`. |
| 26 | How do you return only the first 5 rows? | `ORDER BY ... FETCH FIRST 5 ROWS ONLY` (12c+), or `ROWNUM` over an ordered inline view. |
| 27 | What is an alias? | A temporary name for a column or table in a query. |
| 28 | `COUNT(*)` versus `COUNT(col)`? | Rows versus non-null values of the column. |
| 29 | Name five aggregate functions. | `COUNT`, `SUM`, `AVG`, `MIN`, `MAX`. |
| 30 | What does `GROUP BY` do? | Forms groups of rows with equal values so aggregates return one row per group. |
| 31 | Inner join versus left outer join? | Matching rows only, versus all left rows with nulls where no match. |
| 32 | What is a Cartesian product? | Every row of one table paired with every row of another; usually a missing join condition. |
| 33 | What is `DUAL`? | A one-row table for evaluating expressions; optional from 23ai. |
| 34 | `NVL` versus `COALESCE`? | Both replace nulls; `COALESCE` is standard, accepts many arguments and short-circuits. |
| 35 | How do you concatenate strings? | The double-pipe operator or `CONCAT`. |
| 36 | What does a `DATE` contain in Oracle? | Date and time to the second. |
| 37 | How do you convert a string to a date? | `TO_DATE('2025-03-01', 'YYYY-MM-DD')` or the literal `DATE '2025-03-01'`. |
| 38 | What is `CASE`? | A conditional expression returning a value. |
| 39 | What is a subquery? | A query inside another statement. |
| 40 | `UNION` versus `UNION ALL`? | `UNION` removes duplicates; `UNION ALL` keeps them and is cheaper. |

## DDL, DML, constraints, transactions, indexes

| # | Question | Answer |
|---|---|---|
| 41 | `DELETE` versus `TRUNCATE` versus `DROP`? | Removes chosen rows (DML, can roll back); removes all rows (DDL, no rollback); removes the table. |
| 42 | `CHAR` versus `VARCHAR2`? | Fixed length padded with spaces versus variable length. |
| 43 | Which type for money? | `NUMBER(p,s)`; never floating point. |
| 44 | Name the constraint types. | `NOT NULL`, `PRIMARY KEY`, `UNIQUE`, `FOREIGN KEY`, `CHECK`. |
| 45 | What is an identity column? | A column whose values Oracle generates from an internal sequence. |
| 46 | What does ACID mean? | Atomicity, consistency, isolation, durability. |
| 47 | What is a savepoint? | A marker inside a transaction you can roll back to. |
| 48 | What is an index and what does it cost? | A sorted structure for fast lookup; it costs space and slows DML. |
| 49 | Which indexes exist automatically? | Those for primary key and unique constraints. |
| 50 | What is a view? | A stored query that behaves like a table and holds no data. |
