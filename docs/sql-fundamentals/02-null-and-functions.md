---
tags: [stage-1, sql, functions]
---

# 1.6 NULL, expressions and functions

!!! abstract "Chapter card"
    **Stage:** 1 · **Prerequisites:** 1.5 · **Time:** 3 hours · **Applies to:** 19c+

## 1. NULL: the absence of a value

`NULL` means "unknown or not applicable". It is not zero and not a space.
Amit Verma's `phone` is `NULL`: we do not know it.

### Three-valued logic

A comparison with `NULL` is neither true nor false; it is **unknown**. `WHERE`
keeps only rows where the condition is **true**.

| Expression | Result |
|---|---|
| `NULL = NULL` | unknown |
| `NULL <> 5` | unknown |
| `5 + NULL` | `NULL` |
| `'A' || NULL` | `'A'` (Oracle concatenation ignores null) |
| `TRUE AND unknown` | unknown |
| `FALSE AND unknown` | false |
| `TRUE OR unknown` | true |
| `NOT unknown` | unknown |

```sql
SELECT COUNT(*) FROM customers WHERE phone = NULL;     -- 0
SELECT COUNT(*) FROM customers WHERE phone IS NULL;    -- 2 (verified: 103, 106)
```

!!! danger "NOT IN with a NULL returns nothing"
    `x NOT IN (1, 2, NULL)` means `x<>1 AND x<>2 AND x<>NULL`. The last part is
    unknown, so the whole condition is never true.

    ```sql
    -- Employees who are not anyone's manager: returns NO ROWS,
    -- because manager_id is NULL for Anita Desai.
    SELECT employee_name FROM employees
    WHERE  employee_id NOT IN (SELECT manager_id FROM employees);

    -- Correct
    SELECT employee_name FROM employees e
    WHERE  NOT EXISTS (SELECT 1 FROM employees m WHERE m.manager_id = e.employee_id);
    ```
    The correct query returns the four non-managers: Sunil Kumar, Fatima Khan,
    Ravi Teja, Pooja Yadav.

### Oracle-specific NULL behavior

- **An empty string is NULL** in `VARCHAR2`. `'' IS NULL` is true.
- Aggregate functions **ignore** nulls: `AVG(x)` divides by the count of non-null values. `COUNT(*)` counts rows; `COUNT(col)` counts non-null values.
- A B-tree index does **not** store rows where all indexed columns are null, so `WHERE col IS NULL` cannot use a single-column B-tree index.
- A `UNIQUE` constraint allows many rows with null in the constrained column.

### NULL-handling functions

| Function | Standard? | Meaning | Example → result |
|---|---|---|---|
| `COALESCE(a, b, ...)` | Standard | First non-null argument; stops evaluating early | `COALESCE(phone, 'n/a')` |
| `NVL(a, b)` | Oracle | `b` if `a` is null; always evaluates both | `NVL(phone, 'n/a')` |
| `NVL2(a, b, c)` | Oracle | `b` if `a` is not null, else `c` | `NVL2(phone, 'Has phone', 'No phone')` |
| `NULLIF(a, b)` | Standard | Null if `a = b`, else `a` | `total / NULLIF(qty, 0)` avoids divide-by-zero |
| `DECODE(x, a, r1, b, r2, d)` | Oracle | Value match; treats two nulls as equal | Prefer `CASE` |

```sql
SELECT customer_name,
       COALESCE(phone, 'not provided')          AS phone,
       NVL2(phone, 'Y', 'N')                    AS has_phone
FROM   customers
WHERE  city = 'Delhi';
```

*Verified result:*

| CUSTOMER_NAME | PHONE | HAS_PHONE |
|---|---|---|
| Amit Verma | not provided | N |
| Neha Gupta | not provided | N |

## 2. CASE expressions

`CASE` is SQL's if-then-else. It is an expression: it returns a value and can be
used anywhere a value can.

```sql
SELECT product_name, unit_price,
       CASE
           WHEN unit_price >= 200 THEN 'PREMIUM'
           WHEN unit_price >= 80  THEN 'STANDARD'
           ELSE 'BUDGET'
       END AS price_band
FROM   products
WHERE  category_id IN (4, 7)
ORDER  BY unit_price DESC;
```

*Verified result:*

| PRODUCT_NAME | UNIT_PRICE | PRICE_BAND |
|---|---:|---|
| Basmati Rice 5kg | 650 | PREMIUM |
| Wheat Flour 5kg | 260 | PREMIUM |
| Paneer 200g | 95 | STANDARD |
| Eggs 12 pack | 84 | STANDARD |
| Full Cream Milk 1L | 68 | BUDGET |

Conditions are tested top to bottom and the first true one wins. Without `ELSE`,
an unmatched row yields `NULL`. The *simple* form compares one expression:
`CASE status WHEN 'PLACED' THEN 1 WHEN 'PACKED' THEN 2 END`.

## 3. Character functions

| Function | Result for `'Apple Royal Gala 1kg'` |
|---|---|
| `UPPER(s)`, `LOWER(s)`, `INITCAP(s)` | `APPLE ROYAL GALA 1KG`, ... |
| `LENGTH(s)` | `20` |
| `SUBSTR(s, 1, 5)` | `Apple` (positions start at 1) |
| `INSTR(s, 'Royal')` | `7` |
| `REPLACE(s, '1kg', '2kg')` | `Apple Royal Gala 2kg` |
| `TRIM(s)`, `LTRIM`, `RTRIM` | Removes surrounding spaces |
| `LPAD('7', 3, '0')` | `007` |
| `s || ' (fruit)'` or `CONCAT(a, b)` | Concatenation |
| `REGEXP_LIKE(s, '^[A-Z]')` | True if it starts with a capital |
| `REGEXP_SUBSTR(sku, '[^-]+', 1, 2)` | Second dash-separated part of the SKU: `APL` |

## 4. Numeric functions

| Function | Example | Result |
|---|---|---|
| `ROUND(n, d)` | `ROUND(157.456, 1)` | `157.5` |
| `TRUNC(n, d)` | `TRUNC(157.456, 1)` | `157.4` |
| `CEIL`, `FLOOR` | `CEIL(4.1)`, `FLOOR(4.9)` | `5`, `4` |
| `MOD(a, b)` | `MOD(10, 3)` | `1` |
| `ABS`, `SIGN`, `POWER`, `SQRT` | `POWER(2, 10)` | `1024` |
| `GREATEST`, `LEAST` | `LEAST(50, 30)` | `30` (null if any argument is null) |

## 5. Date and time

Oracle's `DATE` holds year, month, day, hour, minute and second. There is no
date-only type: a "date only" value has time 00:00:00.

| Expression | Meaning |
|---|---|
| `SYSDATE` / `SYSTIMESTAMP` | Database server's current date-time / timestamp with zone |
| `CURRENT_DATE` / `CURRENT_TIMESTAMP` | Same, in the **session** time zone |
| `DATE '2025-03-01'` | ANSI date literal (independent of NLS settings) |
| `TIMESTAMP '2025-03-01 10:15:00'` | ANSI timestamp literal |
| `date + 7` | Seven days later |
| `date2 - date1` | Number of days (may be fractional) |
| `ADD_MONTHS(d, 1)`, `MONTHS_BETWEEN(d2, d1)` | Month arithmetic |
| `TRUNC(d)` / `TRUNC(d, 'MM')` / `TRUNC(d, 'IW')` | Midnight / first of month / Monday of ISO week |
| `LAST_DAY(d)`, `NEXT_DAY(d, 'MONDAY')` | Calendar helpers |
| `EXTRACT(YEAR FROM d)` | A component as a number |
| `d + INTERVAL '2' HOUR` | Interval arithmetic |

```sql
SELECT order_id,
       order_date,
       TRUNC(order_date, 'MM')            AS month_start,
       DATE '2025-04-30' - order_date     AS days_before_month_end
FROM   orders
WHERE  order_date >= DATE '2025-04-01'
ORDER  BY order_id;
```

*Verified result (with `nls_date_format = 'YYYY-MM-DD'`):*

| ORDER_ID | ORDER_DATE | MONTH_START | DAYS_BEFORE_MONTH_END |
|---:|---|---|---:|
| 1006 | 2025-04-02 | 2025-04-01 | 28 |
| 1007 | 2025-04-05 | 2025-04-01 | 25 |
| 1008 | 2025-04-08 | 2025-04-01 | 22 |

## 6. Conversion functions

| Function | Example | Result |
|---|---|---|
| `TO_CHAR(date, fmt)` | `TO_CHAR(DATE '2025-03-01', 'DD Mon YYYY')` | `01 Mar 2025` |
| `TO_CHAR(number, fmt)` | `TO_CHAR(1234.5, 'FM9,999,990.00')` | `1,234.50` |
| `TO_DATE(str, fmt)` | `TO_DATE('01-03-2025', 'DD-MM-YYYY')` | a `DATE` |
| `TO_NUMBER(str)` | `TO_NUMBER('42')` | `42` |
| `TO_TIMESTAMP`, `TO_TIMESTAMP_TZ` | | |
| `CAST(x AS type)` | `CAST(order_date AS TIMESTAMP)` | Standard SQL |
| `... DEFAULT v ON CONVERSION ERROR` | `TO_NUMBER('abc' DEFAULT -1 ON CONVERSION ERROR)` | `-1` (12.2+) |
| `VALIDATE_CONVERSION(x AS type)` | | `1` or `0` (12.2+) |

!!! warning "Implicit conversion is a bug waiting to happen"
    `WHERE order_date = '01-MAR-25'` works only while the session's
    `NLS_DATE_FORMAT` happens to match, and breaks on another machine.
    `WHERE varchar_col = 123` makes Oracle apply `TO_NUMBER` to the **column**,
    which disables its index and fails on the first non-numeric value.
    Always convert explicitly, on the literal side.

## 7. Aggregate functions (preview)

`COUNT`, `SUM`, `AVG`, `MIN`, `MAX` collapse many rows into one.

```sql
SELECT COUNT(*)            AS orders,
       COUNT(coupon_id)    AS orders_with_coupon,
       SUM(total_amount)   AS total,
       ROUND(AVG(total_amount), 2) AS avg_order,
       MIN(order_date)     AS first_order,
       MAX(order_date)     AS last_order
FROM   orders;
```

*Verified result:*

| ORDERS | ORDERS_WITH_COUPON | TOTAL | AVG_ORDER | FIRST_ORDER | LAST_ORDER |
|---:|---:|---:|---:|---|---|
| 8 | 2 | 3958 | 494.75 | 2025-03-01 | 2025-04-08 |

Grouping is covered in [1.10](06-joins-and-aggregates.md).

## 8. Performance and production notes

- A function on a column in `WHERE` blocks ordinary index use. Either move the function to the other side (`order_date >= TRUNC(SYSDATE)` instead of `TRUNC(order_date) = TRUNC(SYSDATE)`) or create a function-based index ([2.12](../indexing/01-indexing.md)).
- Prefer `COALESCE` and `CASE` (standard, short-circuit) over `NVL` and `DECODE` in new code.
- Store timestamps in UTC or use `TIMESTAMP WITH TIME ZONE`; never store local times without knowing the zone.
- Calling a PL/SQL function from SQL for every row is far slower than a built-in.

## 9. Check yourself

??? question "Interview questions"
    1. **(Beginner)** `COUNT(*)` versus `COUNT(column)`? *Rows versus non-null values.*
    2. **(Beginner)** Difference between `NVL` and `COALESCE`? *NVL takes two arguments and evaluates both; COALESCE takes many, is standard, and stops at the first non-null.*
    3. **(Intermediate)** Why does `NOT IN (subquery)` sometimes return nothing? *A null in the subquery result makes the predicate unknown for every row.*
    4. **(Senior)** How does `DECODE` differ from `CASE` with nulls? *DECODE treats NULL as equal to NULL; `CASE x WHEN NULL` never matches.*
    5. **(Architect)** What is your standard for time zones in a multi-region system? *Store instants as `TIMESTAMP WITH TIME ZONE` or UTC `TIMESTAMP`, convert at the presentation layer, and keep business dates (delivery date) as separate date columns with an explicit zone rule.*

??? example "Exercises"
    1. Show each customer's email domain.
       ```sql
       SELECT customer_name, SUBSTR(email, INSTR(email, '@') + 1) AS domain FROM customers;
       ```
       *Every row returns `example.com`.*
    2. How many orders used no coupon? *`SELECT COUNT(*) - COUNT(coupon_id) FROM orders;` → 6.*
    3. Label orders: total >= 700 "LARGE", >= 400 "MEDIUM", else "SMALL". How many of each?
       *LARGE 2 (1002, 1007), MEDIUM 3 (1001, 1003, 1006), SMALL 3 (1004, 1005, 1008).*
    4. Orders placed in March 2025 without using a function on the column.
       ```sql
       SELECT order_id FROM orders
       WHERE  order_date >= DATE '2025-03-01' AND order_date < DATE '2025-04-01';
       ```
       *1001 to 1005.*

## 10. Related

Next: [1.7 DDL](03-ddl.md).
