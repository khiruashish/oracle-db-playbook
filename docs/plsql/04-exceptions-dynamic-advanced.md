---
tags: [stage-2, plsql, exceptions, dynamic-sql]
---

# 2.10 Exceptions, dynamic SQL, advanced PL/SQL

!!! abstract "Chapter card"
    **Stage:** 2 · **Prerequisites:** 2.9 · **Time:** 4 hours · **Applies to:** 19c+

## At a glance

| Subtopic | In one line |
|---|---|
| Exception handling | Predefined, named and user-defined errors; propagation |
| `RAISE_APPLICATION_ERROR` | Send a business error to the caller |
| Dynamic SQL | `EXECUTE IMMEDIATE` and `DBMS_SQL` for statements built at run time |
| SQL injection | How dynamic SQL goes wrong and how to prevent it |
| Autonomous transactions | An independent transaction inside another |
| Optimization and native compilation | Making PL/SQL fast |
| Testing | utPLSQL |

## 1. Exception handling

```sql
DECLARE
    l_price products.unit_price%TYPE;
    e_price_too_low EXCEPTION;                         -- user-defined
    e_child_exists  EXCEPTION;
    PRAGMA EXCEPTION_INIT(e_child_exists, -2292);      -- name an Oracle error
BEGIN
    SELECT unit_price INTO l_price FROM products WHERE sku = 'NO-SUCH-SKU';
    IF l_price < 1 THEN
        RAISE e_price_too_low;
    END IF;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('Unknown SKU');
    WHEN e_price_too_low OR e_child_exists THEN
        DBMS_OUTPUT.PUT_LINE('Business rule violated');
END;
/
```

| Predefined exception | Error | Raised when |
|---|---|---|
| `NO_DATA_FOUND` | ORA-01403 | `SELECT INTO` finds nothing; missing collection element |
| `TOO_MANY_ROWS` | ORA-01422 | `SELECT INTO` finds several rows |
| `DUP_VAL_ON_INDEX` | ORA-00001 | Unique constraint violated |
| `VALUE_ERROR` | ORA-06502 | Conversion or size error |
| `ZERO_DIVIDE` | ORA-01476 | Division by zero |
| `INVALID_CURSOR`, `CURSOR_ALREADY_OPEN` | | Cursor misuse |

### Propagation

An exception not handled in a block moves to the enclosing block, then to the
caller, and finally to the client. When it reaches the client unhandled, Oracle
rolls back **the failed top-level call** (statement-level atomicity); earlier
work in the transaction is still pending.

### Raising business errors

```sql
RAISE_APPLICATION_ERROR(-20002, 'Insufficient stock for ' || l_name);
```

Error numbers must be between -20000 and -20999. Keep a registry of the numbers
your application uses and declare matching named exceptions in a package
specification, as `order_pkg` does.

### The rules that matter

```sql
EXCEPTION
    WHEN OTHERS THEN
        log_pkg.error(                                   -- autonomous logger, section 4
            p_message => SQLERRM,
            p_stack   => DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
        RAISE;                                           -- always re-raise
```

- `WHEN OTHERS THEN NULL;` hides every failure, including ones you never imagined. The compiler warns (PLW-06009). Do not write it.
- `SQLERRM` gives the message; `DBMS_UTILITY.FORMAT_ERROR_BACKTRACE` gives the **line where the error was raised**. Capture both before they are lost.
- Handle an exception only where you can do something useful: translate it, retry, or clean up.
- Use exceptions for exceptional situations, not for ordinary control flow.

## 2. Dynamic SQL

Static SQL is checked at compile time and is always preferred. Dynamic SQL is
needed when the **statement text** is unknown until run time: DDL, a table name
passed in, optional filters.

### EXECUTE IMMEDIATE

```sql
DECLARE
    l_count NUMBER;
    l_table VARCHAR2(128) := 'ORDERS';
BEGIN
    -- Identifiers cannot be bind variables: validate them.
    EXECUTE IMMEDIATE
        'SELECT COUNT(*) FROM ' || DBMS_ASSERT.SQL_OBJECT_NAME(l_table)
        || ' WHERE status = :st'
        INTO  l_count
        USING 'DELIVERED';                                 -- values are always binds
    DBMS_OUTPUT.PUT_LINE(l_count);                         -- 5

    EXECUTE IMMEDIATE 'TRUNCATE TABLE price_update_rejects';   -- DDL (commits)
END;
/
```

Clauses: `INTO` (single row), `BULK COLLECT INTO`, `USING` (binds, by position),
`RETURNING INTO`. For multi-row dynamic queries: `OPEN l_rc FOR l_sql USING ...`.

### SQL injection

```sql
-- VULNERABLE: user text becomes part of the statement
l_sql := 'SELECT * FROM products WHERE product_name LIKE ''%' || p_search || '%''';
-- p_search = x' UNION SELECT username, password ... --

-- SAFE: user text is data, never code
l_sql := 'SELECT * FROM products WHERE UPPER(product_name) LIKE :s';
OPEN l_rc FOR l_sql USING '%' || UPPER(p_search) || '%';
```

| Rule | How |
|---|---|
| Values | Always bind (`USING`) |
| Identifiers (table, column names) | Validate with `DBMS_ASSERT.SQL_OBJECT_NAME`, `SIMPLE_SQL_NAME`, `ENQUOTE_NAME`, or map user input to a fixed whitelist |
| Sort direction, operators | Map to literals in code: `CASE p_dir WHEN 'D' THEN 'DESC' ELSE 'ASC' END` |
| Privileges | Dynamic SQL in definer-rights code runs with the owner's privileges: the blast radius is the owner's |

Binding also matters for performance: concatenated literals make every
statement unique, forcing a **hard parse** each time
([incident 8](../performance-incidents/01-incidents.md)).

### Optional filters

```sql
l_sql := 'SELECT order_id FROM orders WHERE 1 = 1';
IF p_status IS NOT NULL THEN l_sql := l_sql || ' AND status = :status';
                        ELSE l_sql := l_sql || ' AND (1 = 1 OR :status IS NULL)'; END IF;
IF p_from   IS NOT NULL THEN l_sql := l_sql || ' AND order_date >= :d_from';
                        ELSE l_sql := l_sql || ' AND (1 = 1 OR :d_from IS NULL)'; END IF;
OPEN l_rc FOR l_sql USING p_status, p_from;
```

Every variant keeps the same number of binds, each variant gets its own
well-fitting plan, and the optimizer removes the always-true branches.

### DBMS_SQL

Use `DBMS_SQL` only when the **number or types of binds or columns** are unknown
at compile time (generic exporters, report engines). It parses, binds,
describes columns and fetches step by step. `DBMS_SQL.TO_REFCURSOR` and
`TO_CURSOR_NUMBER` convert between the two styles.

## 3. Autonomous transactions

`PRAGMA AUTONOMOUS_TRANSACTION` makes a subprogram run in its **own**
transaction, which commits or rolls back independently of the caller.

```sql
CREATE OR REPLACE PROCEDURE log_error (p_message IN VARCHAR2, p_stack IN VARCHAR2) IS
    PRAGMA AUTONOMOUS_TRANSACTION;
BEGIN
    INSERT INTO audit_log (table_name, operation, pk_value, new_values)
    VALUES ('ERROR_LOG', 'INSERT', 'n/a', SUBSTR(p_message || ' | ' || p_stack, 1, 4000));
    COMMIT;                       -- required before returning
END;
/
```

The one legitimate use is **logging that must survive the caller's rollback**.
Do not use it to work around mutating-table errors or to commit business data:
the autonomous transaction cannot see the caller's uncommitted changes, can
deadlock with its own caller, and breaks atomicity.

## 4. Making PL/SQL fast

| Technique | Notes |
|---|---|
| Do it in SQL | Biggest gain by far |
| `BULK COLLECT` / `FORALL` | [2.8](02-cursors-collections-bulk.md) |
| `PLSQL_OPTIMIZE_LEVEL = 2` (default) or 3 | Level 3 adds automatic inlining of subprograms |
| Native compilation: `PLSQL_CODE_TYPE = NATIVE` | Compiles to machine code. Helps CPU-bound procedural code; does nothing for time spent in SQL |
| `PLS_INTEGER`, `SIMPLE_INTEGER` | Faster arithmetic than `NUMBER` |
| `NOCOPY` for large `IN OUT` collections | Avoids copies |
| `RESULT_CACHE` functions | For expensive lookups on rarely changing data |
| Avoid functions in `WHERE` clauses | Or make them SQL macros / `PRAGMA UDF` |

Find the time first: `DBMS_HPROF` (hierarchical profiler) shows time per
subprogram and separates SQL time from PL/SQL time; `DBMS_PROFILER` works per
line. Tuning without a profile is guessing.

Conditional compilation (`$IF DBMS_DB_VERSION.VER_LE_19 $THEN ... $END`) lets
one source file support several releases.

## 5. Testing PL/SQL

**utPLSQL** (open source) is the standard unit-test framework. Tests are
annotated packages:

```sql
CREATE OR REPLACE PACKAGE test_order_pkg AS
    --%suite(order_pkg)
    --%rollback(auto)

    --%test(coupon_discount returns 10 percent for WELCOME10)
    PROCEDURE welcome10_discount;

    --%test(coupon_discount rejects an inactive coupon)
    --%throws(-20003)
    PROCEDURE inactive_coupon_rejected;
END;
/
CREATE OR REPLACE PACKAGE BODY test_order_pkg AS
    PROCEDURE welcome10_discount IS
    BEGIN
        ut.expect(order_pkg.coupon_discount('WELCOME10', 800, DATE '2025-03-03')).to_equal(80);
    END;

    PROCEDURE inactive_coupon_rejected IS
        l_dummy NUMBER;
    BEGIN
        l_dummy := order_pkg.coupon_discount('NEWYEAR5', 800, DATE '2025-01-15');
    END;
END;
/
-- Run: EXEC ut.run('test_order_pkg');
```

Each test runs in a transaction that utPLSQL rolls back. Run the suite in CI
against a disposable database ([4.9](../database-devops/01-devops.md)).

## 6. Common mistakes

- `WHEN OTHERS` without `RAISE`.
- Logging only `SQLERRM` and losing the line number.
- Concatenating values into dynamic SQL.
- Dynamic SQL where static SQL would do.
- Autonomous transactions for business writes.
- Enabling native compilation and expecting SQL-bound code to speed up.

## FreshMart example

=== "Scenario"

    Customer service searches orders by any combination of customer, status
    and date range, sorted by a column they pick. The search must be safe
    against injection and must not hard-parse for every request.

=== "PL/SQL"

    ```sql
    CREATE OR REPLACE FUNCTION search_orders (
        p_customer_id IN orders.customer_id%TYPE DEFAULT NULL,
        p_status      IN orders.status%TYPE      DEFAULT NULL,
        p_from        IN DATE                    DEFAULT NULL,
        p_sort        IN VARCHAR2                DEFAULT 'DATE'
    ) RETURN SYS_REFCURSOR
    IS
        l_sql VARCHAR2(2000) :=
            'SELECT order_id, customer_id, order_date, status, total_amount FROM orders WHERE 1 = 1';
        l_rc  SYS_REFCURSOR;
    BEGIN
        l_sql := l_sql || CASE WHEN p_customer_id IS NOT NULL
                               THEN ' AND customer_id = :c'
                               ELSE ' AND (1 = 1 OR :c IS NULL)' END;
        l_sql := l_sql || CASE WHEN p_status IS NOT NULL
                               THEN ' AND status = :s'
                               ELSE ' AND (1 = 1 OR :s IS NULL)' END;
        l_sql := l_sql || CASE WHEN p_from IS NOT NULL
                               THEN ' AND order_date >= :d'
                               ELSE ' AND (1 = 1 OR :d IS NULL)' END;
        -- Sort column comes from a whitelist, never from the input text.
        l_sql := l_sql || ' ORDER BY ' ||
                 CASE UPPER(p_sort) WHEN 'TOTAL' THEN 'total_amount DESC'
                                    WHEN 'STATUS' THEN 'status'
                                    ELSE 'order_date DESC' END || ', order_id';

        OPEN l_rc FOR l_sql USING p_customer_id, p_status, p_from;
        RETURN l_rc;
    END search_orders;
    /
    ```

=== "Result"

    `search_orders(p_customer_id => 101, p_status => 'DELIVERED')` returns:

    | ORDER_ID | CUSTOMER_ID | ORDER_DATE | STATUS | TOTAL_AMOUNT |
    |---:|---:|---|---|---:|
    | 1003 | 101 | 2025-03-10 | DELIVERED | 424 |
    | 1001 | 101 | 2025-03-01 | DELIVERED | 639 |

    Derived from the sample data.

=== "Takeaway"

    At most 8 distinct statement texts per sort option exist, each shared by all
    callers. All values are bound; the only concatenated text comes from
    literals in the code.

## Check yourself

??? question "Interview questions"
    1. **(Intermediate)** How do you create a custom error for callers? *`RAISE_APPLICATION_ERROR(-20xxx, msg)`.*
    2. **(Intermediate)** `EXECUTE IMMEDIATE` versus `DBMS_SQL`?
    3. **(Senior)** Why is `WHEN OTHERS THEN NULL` dangerous?
    4. **(Senior)** When is an autonomous transaction appropriate?
    5. **(Architect)** How do you guarantee no SQL injection in a large PL/SQL codebase? *Static SQL by default; code review plus static analysis for every dynamic statement; `DBMS_ASSERT` on identifiers; least-privilege owners; SQL Firewall (23ai) as a detective/preventive control.*

??? example "Exercises"
    1. Write a block that inserts a duplicate review and reports "already reviewed" via `DUP_VAL_ON_INDEX`.
    2. Write a procedure `count_rows(p_table)` that safely returns the row count of any table in the schema.
    3. Add a utPLSQL test asserting that `available_qty(1, 5)` returns 198.

## Related

Next: [2.11 Transactions and concurrency](../transactions/01-transactions-concurrency.md).
