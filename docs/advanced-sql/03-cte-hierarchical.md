---
tags: [stage-2, sql, cte, hierarchy]
---

# 2.3 CTEs and hierarchical queries

!!! abstract "Chapter card"
    **Stage:** 2 · **Prerequisites:** 2.2 · **Time:** 3 hours · **Applies to:** 19c+ (recursive `WITH` since 11.2)

## 1. Common table expressions (the WITH clause)

A **CTE** names a subquery so you can read the statement top to bottom and
reuse the result.

```sql
WITH net_orders AS (
    SELECT * FROM orders WHERE status <> 'CANCELLED'
),
customer_spend AS (
    SELECT customer_id, COUNT(*) AS orders, SUM(total_amount) AS spend
    FROM   net_orders
    GROUP  BY customer_id
)
SELECT c.customer_name, s.orders, s.spend,
       ROUND(s.spend / s.orders, 2) AS avg_order
FROM   customer_spend s
JOIN   customers c ON c.customer_id = s.customer_id
ORDER  BY s.spend DESC;
```

*Verified result:*

| CUSTOMER_NAME | ORDERS | SPEND | AVG_ORDER |
|---|---:|---:|---:|
| Rahul Sharma | 3 | 1799 | 599.67 |
| Priya Nair | 2 | 1140 | 570 |
| Karan Mehta | 1 | 393 | 393 |
| Amit Verma | 1 | 356 | 356 |

### How Oracle executes a CTE

| Behavior | When | Effect |
|---|---|---|
| **Inline** | Referenced once (default) | Treated exactly like an inline view and merged |
| **Materialize** | Referenced more than once (optimizer's choice) | Computed once into a temporary segment; the plan shows `TEMP TABLE TRANSFORMATION` |

Hints `/*+ MATERIALIZE */` and `/*+ INLINE */` force either behavior. Both are
widely used but **undocumented**: treat them as a last resort and test after
every upgrade. A CTE is not automatically an optimization barrier in Oracle.

A `WITH` clause may also declare PL/SQL functions for one statement (12.1+),
and :material-tag: **26ai** release updates add nested `WITH` clauses.

## 2. Recursive WITH (standard SQL)

A recursive CTE has an **anchor member** and a **recursive member** joined by
`UNION ALL`. The column list after the name is mandatory in Oracle.

```sql
WITH org (employee_id, employee_name, manager_id, lvl, path) AS (
    -- anchor: the top of the tree
    SELECT employee_id, employee_name, manager_id, 1, employee_name
    FROM   employees
    WHERE  manager_id IS NULL
    UNION ALL
    -- recursive: people who report to someone already found
    SELECT e.employee_id, e.employee_name, e.manager_id, o.lvl + 1,
           o.path || ' > ' || e.employee_name
    FROM   employees e
    JOIN   org o ON o.employee_id = e.manager_id
)
SEARCH DEPTH FIRST BY employee_id SET ord
CYCLE employee_id SET is_cycle TO 'Y' DEFAULT 'N'
SELECT LPAD(' ', 2 * (lvl - 1)) || employee_name AS org_chart, lvl, path
FROM   org
ORDER  BY ord;
```

*Result (levels verified: 1 at level 1, 3 at level 2, 4 at level 3):*

| ORG_CHART | LVL | PATH |
|---|---:|---|
| Anita Desai | 1 | Anita Desai |
| &nbsp;&nbsp;Vikram Rao | 2 | Anita Desai > Vikram Rao |
| &nbsp;&nbsp;&nbsp;&nbsp;Sunil Kumar | 3 | Anita Desai > Vikram Rao > Sunil Kumar |
| &nbsp;&nbsp;&nbsp;&nbsp;Fatima Khan | 3 | Anita Desai > Vikram Rao > Fatima Khan |
| &nbsp;&nbsp;Meera Pillai | 2 | Anita Desai > Meera Pillai |
| &nbsp;&nbsp;&nbsp;&nbsp;Ravi Teja | 3 | Anita Desai > Meera Pillai > Ravi Teja |
| &nbsp;&nbsp;Arjun Singh | 2 | Anita Desai > Arjun Singh |
| &nbsp;&nbsp;&nbsp;&nbsp;Pooja Yadav | 3 | Anita Desai > Arjun Singh > Pooja Yadav |

- `SEARCH DEPTH FIRST ... SET ord` produces tree order (parent, then its subtree). `BREADTH FIRST` lists level by level.
- `CYCLE ... SET` stops recursion when a row is revisited. Without it a loop in the data raises `ORA-32044`.

Recursive `WITH` is not only for trees. A number or date generator:

```sql
WITH days (d) AS (
    SELECT DATE '2025-03-01' FROM dual
    UNION ALL
    SELECT d + 1 FROM days WHERE d < DATE '2025-03-07'
)
SELECT d FROM days;      -- 7 rows
```

## 3. CONNECT BY (Oracle-specific)

Oracle's original hierarchical syntax is shorter and still common.

```sql
SELECT LPAD(' ', 2 * (LEVEL - 1)) || employee_name       AS org_chart,
       LEVEL                                             AS lvl,
       SYS_CONNECT_BY_PATH(employee_name, ' > ')         AS path,
       CONNECT_BY_ROOT employee_name                     AS top_boss,
       CONNECT_BY_ISLEAF                                 AS is_leaf
FROM   employees
START  WITH manager_id IS NULL
CONNECT BY PRIOR employee_id = manager_id
ORDER  SIBLINGS BY employee_id;
```

It returns the same eight rows in the same order; `path` starts with the
separator (` > Anita Desai > Vikram Rao`).

| Element | Meaning |
|---|---|
| `START WITH` | The root rows |
| `CONNECT BY PRIOR parent_key = child_fk` | `PRIOR` marks the column taken from the parent row. `PRIOR employee_id = manager_id` walks **down**; `employee_id = PRIOR manager_id` walks **up** |
| `LEVEL` | Depth, 1 for roots |
| `SYS_CONNECT_BY_PATH` | Path from the root |
| `CONNECT_BY_ROOT` | A column of the root row |
| `CONNECT_BY_ISLEAF` | 1 if the row has no children |
| `ORDER SIBLINGS BY` | Sorts children under each parent, preserving the tree |
| `NOCYCLE` / `CONNECT_BY_ISCYCLE` | Tolerate and flag loops |

!!! warning "Filtering a hierarchy"
    `WHERE` is applied **after** the hierarchy is built: it removes a row but
    keeps its children. To prune a whole branch, put the condition in
    `CONNECT BY`:
    `CONNECT BY PRIOR employee_id = manager_id AND employee_name <> 'Vikram Rao'`.

The row generator idiom `SELECT LEVEL FROM dual CONNECT BY LEVEL <= 10` builds
ten rows.

### Walking up

*Chain of command above Sunil Kumar (employee 5):*

```sql
SELECT LEVEL, employee_name
FROM   employees
START  WITH employee_id = 5
CONNECT BY employee_id = PRIOR manager_id;
```

| LEVEL | EMPLOYEE_NAME |
|---:|---|
| 1 | Sunil Kumar |
| 2 | Vikram Rao |
| 3 | Anita Desai |

## 4. Rolling up a hierarchy

*Revenue per top-level category, including its subcategories.*

```sql
WITH tree AS (
    SELECT category_id, CONNECT_BY_ROOT category_name AS top_category
    FROM   categories
    START  WITH parent_category_id IS NULL
    CONNECT BY PRIOR category_id = parent_category_id
)
SELECT t.top_category, SUM(oi.line_total) AS revenue
FROM   tree t
JOIN   products p     ON p.category_id = t.category_id
JOIN   order_items oi ON oi.product_id = p.product_id
JOIN   orders o       ON o.order_id    = oi.order_id
WHERE  o.status <> 'CANCELLED'
GROUP  BY t.top_category
ORDER  BY revenue DESC;
```

*Result (derived from verified category revenue; Fruits 660 + Vegetables 190 = 850):*

| TOP_CATEGORY | REVENUE |
|---|---:|
| Staples | 1300 |
| Dairy and Eggs | 918 |
| Fresh Produce | 850 |
| Beverages | 420 |
| Bakery | 180 |

## 5. CONNECT BY or recursive WITH?

| | `CONNECT BY` | Recursive `WITH` |
|---|---|---|
| Portability | Oracle only | Standard SQL |
| Brevity for plain trees | Shorter | Longer |
| Computed values carried down (running product, cost roll-up) | Awkward | Natural |
| Graph traversal with conditions | Limited | Flexible |
| Sibling ordering | `ORDER SIBLINGS BY` | `SEARCH DEPTH FIRST BY` |

Use recursive `WITH` in new code. For path queries over real graphs, consider
SQL property graphs :material-tag: **23ai+** ([4.7](../oracle-26ai/01-oracle-26ai.md)).

## 6. Performance considerations

- Index the child's parent column (`ix_employees_manager`, `ix_categories_parent`). Each level is a join.
- Deep or wide hierarchies read in memory; `SYS_CONNECT_BY_PATH` on wide trees builds long strings.
- For hierarchies queried far more often than changed, consider storing a path or closure table, or a materialized view.
- A materialized CTE writes to temp. For a small CTE referenced many times this is cheap; for a large one it can dominate the run time.

## 7. Common mistakes

- Missing column alias list on a recursive CTE (`ORA-32039`).
- `PRIOR` on the wrong side: the query walks up instead of down and returns only the roots.
- No cycle protection on user-maintained hierarchies.
- Assuming a CTE is always materialized (or never).
- Using `ORDER BY` instead of `ORDER SIBLINGS BY`, which destroys the tree order.

## 8. Check yourself

??? question "Interview questions"
    1. **(Intermediate)** What are the two parts of a recursive CTE?
    2. **(Intermediate)** How do you list all descendants of one node with `CONNECT BY`? *`START WITH id = :node CONNECT BY PRIOR id = parent_id`.*
    3. **(Senior)** When does Oracle materialize a CTE and how do you see it? *When referenced more than once and judged beneficial; the plan shows `TEMP TABLE TRANSFORMATION` and a `SYS_TEMP_...` object.*
    4. **(Senior)** Difference between a filter in `WHERE` and in `CONNECT BY`? *`WHERE` removes single rows after the walk; `CONNECT BY` prunes the subtree.*
    5. **(Architect)** How would you model a bill of materials with 20 levels and millions of parts that is read constantly? *Adjacency list as the source of truth plus a maintained closure or materialized path for reads; or a property graph. Choose by the read-to-write ratio and the kinds of path queries.*

??? example "Exercises"
    1. Number of direct and indirect reports per manager.
       ```sql
       SELECT CONNECT_BY_ROOT employee_name AS manager, COUNT(*) - 1 AS reports
       FROM   employees
       CONNECT BY PRIOR employee_id = manager_id
       GROUP  BY CONNECT_BY_ROOT employee_name
       HAVING COUNT(*) > 1;
       ```
       *Anita Desai 7, Vikram Rao 2, Meera Pillai 1, Arjun Singh 1.*
    2. Generate the dates of March 2025 and left join to orders to show days with no orders.
    3. Show the category tree with indentation using recursive `WITH`.

## 9. Related

Next: [2.4 Advanced aggregation and PIVOT](04-aggregation-pivot.md).
