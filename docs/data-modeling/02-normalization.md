---
tags: [stage-1, data-modeling, normalization]
---

# 1.4 Normalization and denormalization

!!! abstract "Chapter card"
    **Stage:** 1 (1NF to 3NF) and 2 (BCNF to 5NF) · **Prerequisites:** 1.3 · **Time:** 3 hours

## At a glance

Normalization splits tables until every fact is stored exactly once.

| Subtopic | In one line |
|---|---|
| Anomalies | Update, insert and delete problems of redundant data |
| Functional dependencies | Which columns determine which |
| 1NF, 2NF, 3NF | Atomic values; whole key; nothing but the key |
| BCNF, 4NF, 5NF | Overlapping keys; multivalued facts; join dependencies |
| Denormalization | Deliberate, guarded redundancy for read speed |
| Star and snowflake schemas | Dimensional designs for analytics |

## 1. Overview

**Normalization** is a method for splitting tables so that every fact is stored
exactly once. The rule of thumb for third normal form:

> Every non-key column must depend on **the key, the whole key, and nothing but the key**.

## 2. Why: the three anomalies

Suppose FreshMart starts with one wide table:

| order_id | customer_name | customer_city | product_names | qty | supplier | supplier_city |
|---|---|---|---|---|---|---|
| 1001 | Rahul Sharma | Mumbai | Apple, Milk, Bread | 2, 3, 1 | GreenFields, DairyPure, BakeHouse | Nashik, Anand, Mumbai |
| 1003 | Rahul Sharma | Mumbai | Banana, Eggs, Paneer | 2, 1, 2 | GreenFields, DairyPure, DairyPure | Nashik, Anand, Anand |

| Anomaly | What happens |
|---|---|
| **Update** | Rahul moves to Pune. Every one of his order rows must change; miss one and the data contradicts itself. |
| **Insert** | A new supplier cannot be recorded until someone orders one of its products. |
| **Delete** | Deleting the only order for a product also deletes the fact that its supplier is in Nashik. |

## 3. Functional dependencies

`A → B` ("A determines B") means: if two rows have the same A, they have the
same B.

- `customer_id → customer_name, city`
- `(order_id, product_id) → quantity`
- `product_id → supplier_id`, and `supplier_id → supplier_city`

| Dependency type | Meaning | Removed by |
|---|---|---|
| **Partial** | A non-key column depends on only part of a composite key | 2NF |
| **Transitive** | A non-key column depends on another non-key column | 3NF |
| **Multivalued** (`A ↠ B`) | A determines a *set* of B values independently of other columns | 4NF |
| **Join dependency** | The table can be rebuilt only by joining three or more projections | 5NF |

## 4. The normal forms, step by step

### First normal form (1NF)

*Each column holds one value; there are no repeating groups; rows are identifiable.*

Split the lists into rows. Key becomes `(order_id, product_id)`.

| order_id | product_id | product_name | qty | customer_id | customer_name | supplier_id | supplier_city |
|---|---|---|---|---|---|---|---|
| 1001 | 1 | Apple Royal Gala 1kg | 2 | 101 | Rahul Sharma | 1 | Nashik |
| 1001 | 5 | Full Cream Milk 1L | 3 | 101 | Rahul Sharma | 2 | Anand |

### Second normal form (2NF)

*1NF, and no non-key column depends on part of the key.*

`customer_name` depends only on `order_id`; `product_name` only on
`product_id`. Split:

- `orders (order_id, customer_id, customer_name)`
- `products (product_id, product_name, supplier_id, supplier_city)`
- `order_items (order_id, product_id, qty)`

A table with a single-column key that is in 1NF is automatically in 2NF.

### Third normal form (3NF)

*2NF, and no non-key column depends on another non-key column.*

`order_id → customer_id → customer_name` is transitive; so is
`product_id → supplier_id → supplier_city`. Split again:

- `customers (customer_id, customer_name, city)`
- `orders (order_id, customer_id)`
- `suppliers (supplier_id, supplier_name, city)`
- `products (product_id, product_name, supplier_id)`
- `order_items (order_id, product_id, qty)`

This is the FreshMart design. Most transactional schemas stop here.

### Boyce-Codd normal form (BCNF)

*For every dependency `X → Y`, X is a superkey.* BCNF differs from 3NF only when
a table has overlapping candidate keys.

Example: `delivery_slots (warehouse_id, slot_time, driver_id)` with the rules
"a driver works at one warehouse" (`driver_id → warehouse_id`) and "one driver
per warehouse per slot" (`(warehouse_id, slot_time) → driver_id`). The
determinant `driver_id` is not a superkey, so the driver's warehouse is repeated
on every slot row. Fix: `drivers (driver_id, warehouse_id)` and
`delivery_slots (driver_id, slot_time)`.

### Fourth normal form (4NF)

*BCNF, and no non-trivial multivalued dependencies.*

`product_attrs (product_id, dietary_tag, pack_size)`: a product's dietary tags
(vegan, gluten-free) are independent of its pack sizes (500 g, 1 kg). One table
forces every combination to be stored: 2 tags x 3 sizes = 6 rows for 5 facts.
Split into `product_tags (product_id, dietary_tag)` and
`product_sizes (product_id, pack_size)`.

### Fifth normal form (5NF)

*4NF, and every join dependency is implied by the candidate keys.* The table
cannot be split further without losing information.

Classic case: `supplier_product_warehouse`. **If** the business rule is "when a
supplier supplies a product, and the supplier serves a warehouse, and the
warehouse stocks the product, then the supplier supplies that product to that
warehouse", the three-column table equals the join of its three two-column
projections and should be stored as those three. If the rule does not hold, the
three-column table is already in 5NF. 5NF is a statement about business rules,
not about table shape.

### Summary

| Form | Removes | Test |
|---|---|---|
| 1NF | Repeating groups, multi-valued cells | One value per cell, a key exists |
| 2NF | Partial dependencies | Non-key columns need the whole key |
| 3NF | Transitive dependencies | Non-key columns depend only on the key |
| BCNF | Dependencies on non-superkeys | Every determinant is a candidate key |
| 4NF | Independent multivalued facts | One multivalued fact per table |
| 5NF | Join dependencies | Cannot be losslessly split further |

## 5. Verifying a decomposition in SQL

A decomposition must be **lossless**: joining the pieces returns exactly the
original rows. For FreshMart, the wide "order line" view is recovered by joins:

```sql
SELECT o.order_id, c.customer_name, p.product_name, oi.quantity, s.supplier_name
FROM   orders o
JOIN   customers   c  ON c.customer_id = o.customer_id
JOIN   order_items oi ON oi.order_id   = o.order_id
JOIN   products    p  ON p.product_id  = oi.product_id
JOIN   suppliers   s  ON s.supplier_id = p.supplier_id
WHERE  o.order_id = 1001
ORDER  BY oi.line_no;
```

*Verified result:*

| ORDER_ID | CUSTOMER_NAME | PRODUCT_NAME | QUANTITY | SUPPLIER_NAME |
|---:|---|---|---:|---|
| 1001 | Rahul Sharma | Apple Royal Gala 1kg | 2 | GreenFields Agro |
| 1001 | Rahul Sharma | Full Cream Milk 1L | 3 | DairyPure Ltd |
| 1001 | Rahul Sharma | Whole Wheat Bread 400g | 1 | BakeHouse Foods |

## 6. Denormalization

Denormalization is **deliberately** storing redundant data to make reads
cheaper. It is a performance decision made with evidence, never a starting point.

| Technique | FreshMart example | Cost you accept |
|---|---|---|
| Stored aggregate | `orders.subtotal`, `orders.total_amount` | Must stay equal to the lines; enforced in `order_pkg` and `ck_orders_total` |
| Snapshot column | `order_items.unit_price` | None: this is a different fact (price *then*), not redundancy |
| Copied parent column | `customers.city` alongside `addresses.city` | Two places to update |
| Precomputed join | Materialized view of daily sales | Refresh cost and staleness |
| Star schema | `fact_sales` with dimension tables | Separate load process (chapter [4.6](../data-warehousing/01-data-warehousing.md)) |

**Star schema**: one central fact table of measurements with foreign keys to
denormalized dimension tables. **Snowflake schema**: the dimensions are
normalized again into sub-dimensions. Stars are simpler and usually faster to
query; snowflakes save space and suit very large, shared dimensions.

### Trade-offs

| | Normalized (3NF) | Denormalized |
|---|---|---|
| Writes | One place to change, short transactions | More rows and columns to maintain |
| Reads | More joins | Fewer joins |
| Integrity | Enforced by structure | Enforced by code, triggers or refresh jobs |
| Best for | OLTP | Reporting, read-heavy APIs |

Before denormalizing, try in this order: a better index, a better query, a
materialized view (the database keeps the copy correct), and only then redundant
columns.

## 7. Common mistakes

- Treating a **snapshot** as redundancy and "normalizing" it away (then old invoices change when prices change).
- **Over-normalizing** fixed attributes: a `genders` or `yes_no` table adds joins and no value.
- Denormalizing **before measuring**. Oracle joins millions of rows per second on indexed keys.
- Storing a derived total with **nothing enforcing** it.
- Believing normalization is about saving disk space. It is about correctness.

## FreshMart example

=== "Scenario"

    `orders.subtotal` duplicates information held in `order_items`. That is a deliberate denormalization. An auditor asks for proof that the copy has not drifted from the lines.

=== "SQL"

    ```sql
    SELECT o.order_id, o.subtotal, s.lines_total
    FROM   orders o
    JOIN  (SELECT order_id, SUM(line_total) AS lines_total
           FROM   order_items GROUP BY order_id) s ON s.order_id = o.order_id
    WHERE  o.subtotal <> s.lines_total;
    ```

=== "Result"

    No rows selected.

    *Verified*: for all 8 orders the stored subtotal equals the sum of the lines
    (for example order 1001: 360 + 204 + 45 = 609).

=== "Takeaway"

    Redundancy is acceptable when something guarantees it: here one write path (`order_pkg`), a check constraint on the total, and this reconciliation query. Redundancy with no guard is an anomaly waiting to happen.

## 8. Check yourself

??? question "Interview questions"
    1. **(Beginner)** What is 1NF? *Atomic values, no repeating groups, each row identifiable.*
    2. **(Beginner)** Give an example of an update anomaly.
    3. **(Intermediate)** 3NF versus BCNF? *3NF allows a dependency whose right side is part of a candidate key; BCNF does not. They differ only with overlapping candidate keys.*
    4. **(Senior)** `orders.total_amount` is derivable. Is the table still in 3NF? *Strictly, a stored derived value is controlled redundancy. It is accepted because it is enforced by a check constraint and written in one place.*
    5. **(Architect)** How do you decide between a materialized view and a redundant column? *A materialized view is declarative, optimizer-aware (query rewrite) and refreshed by the database; a redundant column is immediate but relies on application discipline. Prefer the MV unless the value must be transactionally current and fast refresh on commit is too costly.*

??? example "Exercises"
    1. Table `enrolment (student_id, course_id, student_name, course_title, grade)`. Normalize to 3NF.
       *`students (student_id, student_name)`, `courses (course_id, course_title)`, `enrolments (student_id, course_id, grade)`.*
    2. Which normal form does `customers` violate by having `city` when `addresses` also has `city`? *None formally (it is a different fact: registration city). It becomes a problem only if both are meant to be the same fact.*
    3. Write a query that proves `orders.subtotal` equals the sum of its lines for every order.
       ```sql
       SELECT o.order_id
       FROM   orders o
       WHERE  o.subtotal <> (SELECT SUM(oi.line_total)
                             FROM   order_items oi
                             WHERE  oi.order_id = o.order_id);
       ```
       *Verified: no rows.*

## 9. Related

Next: [1.5 SELECT](../sql-fundamentals/01-select.md). Later:
[2.14 Materialized views](../database-objects/01-database-objects.md),
[4.6 Data warehousing](../data-warehousing/01-data-warehousing.md).
