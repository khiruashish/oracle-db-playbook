---
tags: [stage-1, sql]
---

# 1.5 SELECT: reading data

!!! abstract "Chapter card"
    **Stage:** 1 · **Prerequisites:** 1.2, FreshMart installed · **Time:** 3 hours · **Applies to:** 19c+ (notes inline)

## At a glance

`SELECT` reads rows: you describe the result and Oracle works out how to fetch it.

| Subtopic | In one line |
|---|---|
| Statement groups | DQL, DML, DDL, DCL, TCL |
| Clause order | FROM, WHERE, GROUP BY, HAVING, SELECT, ORDER BY, FETCH |
| Columns, expressions, aliases | What to return |
| WHERE | Comparison, BETWEEN, IN, LIKE, IS NULL, AND / OR / NOT |
| DISTINCT | Remove duplicate rows |
| ORDER BY | Sorting and null placement |
| Limiting rows | FETCH FIRST and the ROWNUM trap |

## 1. Overview

SQL statements fall into five groups. This chapter covers the first.

| Group | Purpose | Statements |
|---|---|---|
| **DQL** (query) | Read data | `SELECT` |
| **DML** (manipulation) | Change rows | `INSERT`, `UPDATE`, `DELETE`, `MERGE` |
| **DDL** (definition) | Change structure | `CREATE`, `ALTER`, `DROP`, `TRUNCATE` |
| **DCL** (control) | Change permissions | `GRANT`, `REVOKE` |
| **TCL** (transaction control) | End or mark transactions | `COMMIT`, `ROLLBACK`, `SAVEPOINT` |

`SELECT` describes the rows you want. It never changes data.

## 2. Syntax and logical order

```sql
SELECT   [DISTINCT] columns or expressions   -- 5. choose columns
FROM     table                               -- 1. start with rows
WHERE    row_condition                       -- 2. filter rows
GROUP BY grouping_columns                    -- 3. form groups
HAVING   group_condition                     -- 4. filter groups
ORDER BY sort_columns                        -- 6. sort
OFFSET n ROWS FETCH FIRST m ROWS ONLY;       -- 7. limit (12.1+)
```

The numbers show the **logical** order of evaluation. It explains two rules:

- A column alias defined in `SELECT` cannot be used in `WHERE` (step 2 runs
  before step 5), but it can be used in `ORDER BY`.
- `WHERE` cannot contain aggregate functions; `HAVING` can.

## 3. How Oracle runs a query (beginner view)

1. **Parse**: check syntax, object names and privileges.
2. **Optimize**: choose a plan, for example "use the primary key index".
3. **Execute**: read the blocks that hold the rows.
4. **Fetch**: send rows to the client in batches (the *array fetch size*).

If the same statement text was run before, Oracle reuses the stored plan and
skips step 2. That is one reason applications use bind variables instead of
pasting values into SQL text.

## 4. Examples

### All columns, chosen columns

```sql
SELECT * FROM warehouses;
```

*Verified result (the `created_at` column is omitted here):*

| WAREHOUSE_ID | WAREHOUSE_NAME | CITY |
|---:|---|---|
| 1 | Mumbai Central FC | Mumbai |
| 2 | Bengaluru South FC | Bengaluru |
| 3 | Delhi NCR FC | Delhi |

`SELECT *` is fine for exploring. In application code, list the columns: adding
a column to the table would otherwise change what your program receives.

### Expressions and aliases

```sql
SELECT product_name,
       unit_price,
       unit_price * 1.05           AS price_with_tax,
       'INR ' || unit_price        AS price_label
FROM   products
WHERE  category_id = 6;
```

| PRODUCT_NAME | UNIT_PRICE | PRICE_WITH_TAX | PRICE_LABEL |
|---|---:|---:|---|
| Orange Juice 1L | 120 | 126 | INR 120 |
| Assam Tea 250g | 150 | 157.5 | INR 150 |

`||` concatenates strings. `AS` names the result column. An alias with spaces or
lower case needs double quotes (`AS "Price Label"`); avoid that in code.

### Filtering with WHERE

| Operator | Meaning | Example |
|---|---|---|
| `=`, `<>` (or `!=`), `<`, `<=`, `>`, `>=` | Comparison | `unit_price > 100` |
| `BETWEEN a AND b` | Inclusive range | `unit_price BETWEEN 50 AND 100` |
| `IN (...)` | Any value in a list | `status IN ('PLACED', 'PACKED')` |
| `LIKE` | Pattern: `%` any string, `_` one character | `product_name LIKE '%Milk%'` |
| `IS NULL`, `IS NOT NULL` | Missing value test | `phone IS NULL` |
| `AND`, `OR`, `NOT` | Combine conditions | |

```sql
SELECT product_id, product_name, unit_price
FROM   products
WHERE  unit_price > 100
ORDER  BY unit_price DESC, product_id;
```

*Verified result:*

| PRODUCT_ID | PRODUCT_NAME | UNIT_PRICE |
|---:|---|---:|
| 11 | Basmati Rice 5kg | 650 |
| 12 | Wheat Flour 5kg | 260 |
| 1 | Apple Royal Gala 1kg | 180 |
| 10 | Assam Tea 250g | 150 |
| 9 | Orange Juice 1L | 120 |

**Precedence:** `NOT`, then `AND`, then `OR`. Use parentheses whenever you mix
`AND` and `OR`.

```sql
-- Wrong: AND binds first, so every CANCELLED order is returned regardless of customer.
SELECT order_id FROM orders
WHERE  customer_id = 101 AND status = 'PLACED' OR status = 'CANCELLED';   -- 1005, 1007

-- Right
SELECT order_id FROM orders
WHERE  customer_id = 101 AND (status = 'PLACED' OR status = 'CANCELLED'); -- 1007
```

**String comparison is case-sensitive** and string literals use single quotes:
`WHERE city = 'mumbai'` returns nothing.

### DISTINCT

```sql
SELECT DISTINCT city FROM customers;   -- Mumbai, Bengaluru, Delhi (in any order)
```

`DISTINCT` applies to the whole select list, not to one column. If you need it
to "fix" duplicates after a join, the join is usually wrong.

### Sorting

```sql
SELECT customer_name, phone
FROM   customers
ORDER  BY phone NULLS FIRST, customer_name;
```

In Oracle, nulls sort **last** in ascending order and **first** in descending
order unless you say `NULLS FIRST` / `NULLS LAST`.

### Limiting rows

=== "Standard SQL (12.1+)"

    ```sql
    SELECT order_id, total_amount
    FROM   orders
    ORDER  BY total_amount DESC
    FETCH  FIRST 3 ROWS ONLY;
    ```

=== "Oracle legacy (any release)"

    ```sql
    SELECT order_id, total_amount
    FROM  (SELECT order_id, total_amount
           FROM   orders
           ORDER  BY total_amount DESC)
    WHERE  ROWNUM <= 3;
    ```

*Verified result:*

| ORDER_ID | TOTAL_AMOUNT |
|---:|---:|
| 1007 | 736 |
| 1002 | 720 |
| 1001 | 639 |

!!! warning "The classic ROWNUM mistake"
    `SELECT ... FROM orders WHERE ROWNUM <= 3 ORDER BY total_amount DESC` picks
    three arbitrary rows and *then* sorts them. `ROWNUM` is assigned before
    `ORDER BY`. Sort in an inline view first, or use `FETCH FIRST`.

### The DUAL table

Oracle requires a `FROM` clause before 23ai. `DUAL` is a one-row table for
evaluating expressions.

```sql
SELECT SYSDATE, 2 + 3 FROM dual;
SELECT SYSDATE, 2 + 3;            -- 23ai+: FROM is optional
```

## 5. Real-world use

- Product listing page: `WHERE category_id = :cat AND is_active = 'Y' ORDER BY product_name FETCH FIRST 20 ROWS ONLY`.
- Customer service lookup: `WHERE email = :email`.
- Operations screen: `WHERE status IN ('PLACED', 'PACKED') ORDER BY order_date`.

The `:name` placeholders are **bind variables**. Applications must use them for
every user-supplied value: it prevents SQL injection
([3.5](../security/01-security.md)) and lets Oracle reuse plans.

## 6. Performance and security notes

- A selective `WHERE` on an indexed column lets Oracle read a few blocks instead of the whole table ([1.11](07-first-index.md)).
- Wrapping a column in a function (`WHERE UPPER(email) = ...`) prevents the use of a normal index on that column.
- `LIKE '%milk%'` (leading wildcard) cannot use a normal index range scan.
- To query a table you need the `SELECT` (or `READ`) privilege on it. `READ` allows queries but not `SELECT ... FOR UPDATE`.

## 7. Common mistakes

| Mistake | Fix |
|---|---|
| `WHERE phone = NULL` | `WHERE phone IS NULL` |
| Double quotes for strings: `"Mumbai"` | Single quotes: `'Mumbai'` |
| Using an alias in `WHERE` | Repeat the expression or use an inline view |
| No `ORDER BY`, yet expecting an order | Always state the order you need |
| `BETWEEN DATE '2025-03-01' AND DATE '2025-03-31'` on a column that has a time part | Use `>= DATE '2025-03-01' AND < DATE '2025-04-01'` |
| `ORDER BY 2` (position) in application code | Name the column |

## FreshMart example

=== "Scenario"

    The home page shows a "Budget picks" strip: the five cheapest active products under 100, cheapest first.

=== "SQL"

    ```sql
    SELECT product_name, unit_price, unit_of_measure
    FROM   products
    WHERE  is_active = 'Y'
    AND    unit_price < 100
    ORDER  BY unit_price, product_name
    FETCH  FIRST 5 ROWS ONLY;
    ```

=== "Result"

    | PRODUCT_NAME | UNIT_PRICE | UNIT_OF_MEASURE |
    |---|---:|---|
    | Onion 1kg | 35 | KG |
    | Tomato 1kg | 40 | KG |
    | Whole Wheat Bread 400g | 45 | PACK |
    | Banana Robusta 1 dozen | 60 | DOZEN |
    | Full Cream Milk 1L | 68 | LITRE |

    Derived from the sample data.

=== "Takeaway"

    Filter, sort, limit: three clauses cover most screens of an application. The second sort column makes the order deterministic when two products share a price.

## 8. Check yourself

??? question "Interview questions"
    1. **(Beginner)** In what order are the clauses of a query evaluated? *FROM, WHERE, GROUP BY, HAVING, SELECT, ORDER BY, FETCH.*
    2. **(Beginner)** Difference between `WHERE` and `HAVING`? *WHERE filters rows before grouping; HAVING filters groups after aggregation.*
    3. **(Intermediate)** Why can `WHERE ROWNUM = 2` never return a row? *ROWNUM is assigned as rows pass the predicate. The first candidate gets 1, fails `= 2`, is discarded, and the next candidate is again numbered 1.*
    4. **(Senior)** How does `FETCH FIRST` execute internally? *Oracle rewrites it to an analytic `ROW_NUMBER()` filter; with a suitable index it becomes a stop-key operation that reads only the needed rows.*
    5. **(Architect)** What are the risks of `SELECT *` in a shared codebase? *Hidden coupling to column order and count, wasted network and memory on unused columns (notably LOBs), and it defeats covering indexes.*

??? example "Exercises"
    1. List customers in Delhi. *103 Amit Verma, 106 Neha Gupta.*
       ```sql
       SELECT customer_id, customer_name FROM customers WHERE city = 'Delhi';
       ```
    2. Products priced between 50 and 100 inclusive, cheapest first.
       ```sql
       SELECT product_name, unit_price FROM products
       WHERE  unit_price BETWEEN 50 AND 100 ORDER BY unit_price;
       ```
       *Banana 60, Milk 68, Eggs 84, Paneer 95.*
    3. The two most recent orders.
       ```sql
       SELECT order_id, order_date FROM orders
       ORDER  BY order_date DESC FETCH FIRST 2 ROWS ONLY;
       ```
       *1008 (2025-04-08), 1007 (2025-04-05).*
    4. Products whose name contains "1kg". *Apple, Tomato, Onion.*

## 9. Related

Next: [1.6 NULL, expressions and functions](02-null-and-functions.md).
