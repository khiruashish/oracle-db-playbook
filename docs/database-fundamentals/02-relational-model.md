---
tags: [stage-1, fundamentals, theory]
---

# 1.2 The relational model

!!! abstract "Chapter card"
    **Stage:** 1 · **Prerequisites:** 1.1 · **Time:** 3 hours · **Applies to:** theory; independent of release

## 1. Overview

In 1970 E. F. Codd proposed that all data be presented as **relations**: sets of
rows with named, typed columns, with every relationship expressed by *values*
rather than by pointers. This model is why you can join any two tables on
matching values without the database being designed for that question in advance.

## 2. Terminology: theory and SQL

| Relational theory | SQL / Oracle | Notes |
|---|---|---|
| Relation | Table | A relation is a *set*: no duplicates, no order. SQL tables are bags: duplicates are allowed unless a key forbids them. |
| Tuple | Row | |
| Attribute | Column | |
| Domain | Data type (plus constraints) | The set of legal values. :material-tag: **23ai+** adds `CREATE DOMAIN`. |
| Degree | Number of columns | |
| Cardinality | Number of rows | The same word is used later for "rows estimated by the optimizer". |
| Relation schema | Table definition | |

**Two rules that surprise beginners**

1. **Rows have no order.** A query without `ORDER BY` may return rows in any
   order, and that order can change tomorrow.
2. **Each cell holds one value** from the column's domain (this becomes first
   normal form in chapter [1.4](../data-modeling/02-normalization.md)).

## 3. Keys

A key is how you say "this row, and no other".

| Key type | Definition | FreshMart example |
|---|---|---|
| **Superkey** | Any set of columns that is unique | `(customer_id, email)` |
| **Candidate key** | A minimal superkey: remove any column and it stops being unique | `customer_id`; also `email` |
| **Primary key** | The candidate key chosen to identify rows. Not null. | `customers.customer_id` |
| **Alternate key** | A candidate key that was not chosen | `customers.email` (enforced with `UNIQUE`) |
| **Composite key** | A key of two or more columns | `inventory (warehouse_id, product_id)` |
| **Natural key** | A key with business meaning | `products.sku` |
| **Surrogate key** | A meaningless generated number | `products.product_id` |
| **Foreign key** | Columns whose values must match a key in another (or the same) table | `orders.customer_id` → `customers.customer_id` |

### Integrity rules

- **Entity integrity**: no part of a primary key may be null. A row you cannot
  identify is not a fact.
- **Referential integrity**: a foreign key value must either match an existing
  parent key or be null. Order 1001 cannot belong to customer 999 if no
  customer 999 exists.

```sql
-- Referential integrity in action (order 5000 does not need to exist first:
-- the foreign key on customer_id is checked and fails).
INSERT INTO orders (customer_id, address_id, warehouse_id, subtotal, total_amount)
VALUES (999, 201, 1, 100, 100);
```

```text
ORA-02291: integrity constraint (FRESHMART.FK_ORDERS_CUSTOMER) violated - parent key not found
```

## 4. Relational algebra

Relational algebra is the small set of operations that every SQL query is built
from. The optimizer rewrites your SQL using the rules of this algebra, which is
why two differently written queries can run the same way.

| Operation | Symbol | Meaning | SQL |
|---|---|---|---|
| Selection | σ | Keep rows that satisfy a condition | `WHERE` |
| Projection | π | Keep some columns | `SELECT` column list |
| Rename | ρ | Rename a relation or attribute | `AS` |
| Cartesian product | × | Every row paired with every row | `CROSS JOIN` |
| Join | ⋈ | Product followed by a selection on matching columns | `JOIN ... ON` |
| Union | ∪ | Rows in either | `UNION` |
| Intersection | ∩ | Rows in both | `INTERSECT` |
| Difference | − | Rows in the first and not in the second | `MINUS` (Oracle) / `EXCEPT` (standard; accepted from 21c) |
| Division | ÷ | "Rows related to **all** of ..." | `NOT EXISTS (... NOT EXISTS ...)` or `GROUP BY ... HAVING COUNT` |
| Semijoin | ⋉ | Rows of A that have a match in B | `EXISTS`, `IN` |
| Antijoin | ▷ | Rows of A that have no match in B | `NOT EXISTS` |

### Worked example

*"Names of customers in Mumbai."*

Algebra: π~customer_name~ ( σ~city = 'Mumbai'~ ( customers ) )

```sql
SELECT customer_name
FROM   customers
WHERE  city = 'Mumbai';
```

*Verified result:*

| CUSTOMER_NAME |
|---|
| Rahul Sharma |
| Sneha Iyer |
| Karan Mehta |

*"Names of customers who have placed an order"* is a semijoin:
customers ⋉ orders.

```sql
SELECT c.customer_name
FROM   customers c
WHERE  EXISTS (SELECT 1 FROM orders o WHERE o.customer_id = c.customer_id);
```

Five rows are returned: everyone except Neha Gupta (106).

### Why the algebra matters in practice

Because selection and join commute, the optimizer may filter before joining:

σ~city='Mumbai'~ (customers ⋈ orders) ≡ (σ~city='Mumbai'~ customers) ⋈ orders

Filtering 6 customers down to 3 *before* the join is cheaper than joining first.
This rewrite is called **predicate pushdown**; you will see it in plans in
chapter [2.15](../performance-engineering/01-execution-plans.md).

## 5. Relational calculus

Algebra says *how* to combine relations. **Relational calculus** says *what* you
want, as a logical statement.

- **Tuple relational calculus**:
  { c.customer_name | c ∈ customers ∧ c.city = 'Mumbai' }
- **Domain relational calculus** uses variables for individual values rather
  than rows.

Codd proved the two are equally expressive. SQL is closer to tuple calculus (you
describe the result), and the DBMS translates it into algebra to execute it. A
language that can express everything the algebra can is called **relationally
complete**.

## 6. Where SQL departs from the model

| Model | SQL reality | Consequence |
|---|---|---|
| Relations are sets | Tables and results can contain duplicates | You need `DISTINCT`, and keys must be declared |
| Two-valued logic | `NULL` gives three-valued logic | `WHERE x = NULL` is never true (chapter [1.6](../sql-fundamentals/02-null-and-functions.md)) |
| No ordering | Column order and `ORDER BY` exist | Never rely on implicit order |
| Empty string is a value | **Oracle treats `''` in `VARCHAR2` as `NULL`** | `WHERE name = ''` finds nothing in Oracle |

## 7. Common mistakes

- Choosing a **natural key that changes** (email, phone) as a primary key. Every foreign key then has to change with it. Use a surrogate primary key and a `UNIQUE` constraint on the natural key.
- Adding a surrogate key and **forgetting the unique constraint** on the natural key, which lets duplicates in.
- Believing rows come back "in insert order".
- Using a join when the question is a semijoin, which multiplies rows and then needs `DISTINCT` to hide the mistake.

## 8. Check yourself

??? question "Interview questions"
    1. **(Beginner)** Candidate key versus primary key? *Every table may have several candidate keys; one is chosen as primary, the rest are alternate keys.*
    2. **(Beginner)** Can a foreign key be null? *Yes, unless declared `NOT NULL`. A null foreign key means "no parent".*
    3. **(Intermediate)** Can a foreign key reference a non-primary-key column? *Yes, if that column has a `UNIQUE` or primary key constraint.*
    4. **(Senior)** Express relational division in SQL: products stocked in **every** warehouse.
       ```sql
       SELECT p.product_name
       FROM   products p
       WHERE  NOT EXISTS (
                SELECT 1 FROM warehouses w
                WHERE  NOT EXISTS (
                         SELECT 1 FROM inventory i
                         WHERE  i.warehouse_id = w.warehouse_id
                         AND    i.product_id   = p.product_id));
       ```
       *On the sample data this returns no rows: no product is stocked in all three warehouses.*
    5. **(Architect)** Surrogate or natural keys as a standard? *Surrogate primary keys for stability and narrow joins, with natural keys always enforced by unique constraints. Exceptions: pure association tables and stable code tables.*

??? example "Exercises"
    1. List all candidate keys of `coupons`. *`coupon_id` and `coupon_code`.*
    2. Write algebra and SQL for "SKUs of products priced above 100".
       *π~sku~(σ~unit_price>100~(products)); `SELECT sku FROM products WHERE unit_price > 100;` returns 5 rows.*
    3. Which FreshMart tables have a composite primary key? *`inventory`, `cart_items`, `order_items`.*

## 9. Related

Next: [1.3 Data modeling](../data-modeling/01-data-modeling.md).
Deeper: [2.1 Joins](../advanced-sql/01-joins.md) for semi and anti joins.
