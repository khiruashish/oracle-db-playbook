---
tags: [runbooks, performance, security]
---

# Runbooks: SQL diagnosis, objects, users, indexes

## 11. SQL performance diagnosis

| | |
|---|---|
| **Objective** | Find which statement is responsible for a slowdown and why |
| **Privileges** | `V$SQLSTATS`, `V$SQL`, `V$SESSION`. `DBA_HIST_*` and ASH need the :material-license: Diagnostics Pack |

```sql
--8<-- "sql/performance/sql_diagnosis.sql:topsql"
```

Then, for the statement at the top:

```sql
--8<-- "sql/performance/sql_diagnosis.sql:onesql"
```

**Procedure**

1. **What is the database doing now?** Activity by wait class:

    ```sql
    --8<-- "sql/performance/sql_diagnosis.sql:waits"
    ```

2. **Which SQL owns the time?** Top by elapsed time; note `ms_per_exec` and `gets_per_exec`, not only totals.
3. **Did its plan change?** Several `plan_hash_value` rows for one `sql_id` with very different cost per execution.
4. **Is the plan based on good estimates?** `ALLSTATS LAST`: compare E-Rows and A-Rows ([2.15](../performance-engineering/01-execution-plans.md)).
5. **Fix the cause:** statistics, index, rewrite; for an urgent regression, load the previous good plan as a baseline ([3.6](../performance-engineering/02-optimizer-statistics-spm.md)).

**Hard-parse check**

```sql
--8<-- "sql/performance/sql_diagnosis.sql:literals"
```

**Verification:** per-execution time and buffer gets return to baseline; DB
time by wait class returns to its normal shape.

**Rollback:** drop a baseline or index you added
(`DBMS_SPM.DROP_SQL_PLAN_BASELINE`); restore statistics with
`DBMS_STATS.RESTORE_TABLE_STATS`.

!!! danger "Safety"
    Do not flush the shared pool in production to "fix" a plan: it forces
    every statement to hard parse. To invalidate one cursor use
    `DBMS_SHARED_POOL.PURGE` for that cursor, or
    `DBMS_STATS` with `NO_INVALIDATE => FALSE` on the affected table.

---

## 12. Invalid object investigation

| | |
|---|---|
| **Objective** | Find and repair invalid PL/SQL, views and synonyms, typically after a deployment or upgrade |
| **Privileges** | `DBA_OBJECTS`, `DBA_ERRORS`; `ALTER ANY PROCEDURE` or ownership to recompile |

```sql
--8<-- "sql/administration/objects_users.sql:invalid"
```

For the whole database after patching or upgrade:

```sql
@?/rdbms/admin/utlrp.sql        -- parallel recompile; run as SYSDBA in each container
```

**Expected:** zero invalid application objects after a release. Record the
count **before** a change so you can tell new problems from old ones.

**Troubleshooting**

| Error in `DBA_ERRORS` | Cause |
|---|---|
| `PLS-00201: identifier must be declared` | Missing object or missing direct grant (role grants do not count in definer-rights code) |
| `ORA-00942` in a view | Base table dropped or privilege revoked |
| `PL/SQL: ORA-00904` | Column renamed or dropped |
| Object valid in one edition, invalid in another | Edition-based redefinition in progress |

**Rollback:** recompilation changes nothing functionally. If a deployment left
objects invalid, roll the deployment forward with a fix or back per its plan.

**Safety:** recompiling a package with session state causes `ORA-04068` once in
connected sessions; avoid recompiling during peak.

---

## 13. User and privilege management

| | |
|---|---|
| **Objective** | Create, change, review and remove accounts under least privilege |
| **Prerequisites** | An approved access request naming the person or service, the role and the expiry |
| **Privileges** | `CREATE USER`, `ALTER USER`, `DROP USER`, `GRANT ANY ROLE` (typically a security administrator role) |

```sql
-- Create a service account with a role
CREATE USER fm_report IDENTIFIED BY "&password" PROFILE app_profile
    DEFAULT TABLESPACE users QUOTA 0 ON users;
GRANT CREATE SESSION TO fm_report;
GRANT fm_read_role TO fm_report;

-- Lock, unlock, rotate
ALTER USER fm_report ACCOUNT LOCK;
ALTER USER fm_report ACCOUNT UNLOCK;
ALTER USER fm_report IDENTIFIED BY "&new_password";

-- Revoke
REVOKE fm_read_role FROM fm_report;
```

**Review**

```sql
--8<-- "sql/administration/objects_users.sql:users"
```

**Verification:** connect as the account and confirm it can do what it should
and nothing more (`SELECT * FROM session_privs; SELECT * FROM session_roles;`).

**Rollback:** re-grant or unlock.

!!! danger "Destructive"
    ```sql
    DROP USER some_user CASCADE;
    ```
    `CASCADE` drops every object the user owns, with no recycle bin for the
    schema as a whole. Before dropping: lock the account for an agreed period,
    confirm no objects or dependencies (`DBA_OBJECTS`, `DBA_DEPENDENCIES`),
    export the schema, and obtain approval. Never grant `DBA`, `SYSDBA` or
    `ANY` privileges to resolve an application error.

**Troubleshooting:** `ORA-28000` (locked: check failed logins in the audit
trail before unlocking); `ORA-28001` (expired); `ORA-01017` after rotation
(application still using the old secret: use gradual password rollover);
`ORA-01045` (no `CREATE SESSION`).

---

## 14. Index health investigation

| | |
|---|---|
| **Objective** | Find unusable, invisible, unused or missing indexes |
| **Privileges** | `DBA_INDEXES`, `DBA_IND_PARTITIONS`, `DBA_INDEX_USAGE`; `ALTER ANY INDEX` to repair |

```sql
--8<-- "sql/administration/objects_users.sql:indexes"
```

**Actions**

| Finding | Action |
|---|---|
| `UNUSABLE` index or partition | `ALTER INDEX ix REBUILD [PARTITION p] ONLINE;` Find out which operation caused it (direct load, partition DDL without `UPDATE INDEXES`) |
| Foreign key without an index | Create it `ONLINE` if the parent is ever deleted from or its key updated, or the child is joined from the parent |
| Parallel degree not 1 on an OLTP index | `ALTER INDEX ix NOPARALLEL;` |
| Invisible index nobody remembers | Decide: make visible or drop |
| Not used for a full business cycle (including month-end, year-end) | Make invisible first, wait a cycle, then drop |
| "Fragmented" index | Usually nothing. Rebuild or coalesce only with evidence ([2.12](../indexing/01-indexing.md)) |

**Verification:** no `UNUSABLE` rows; affected queries use the index again.

**Rollback:** `ALTER INDEX ix VISIBLE;` or recreate a dropped index from
version control.

!!! danger "Safety"
    An unusable **unique** index blocks DML on its table. A non-online rebuild
    locks the table. Dropping an index that polices a constraint or supports a
    foreign key changes locking behavior: check `DBA_CONSTRAINTS.INDEX_NAME`
    first.
