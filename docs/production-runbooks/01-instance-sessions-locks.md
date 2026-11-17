---
tags: [runbooks, sessions, locking]
---

# Runbooks: startup, shutdown, sessions, locks

## 1. Database startup and shutdown

| | |
|---|---|
| **Objective** | Stop or start an instance cleanly |
| **Prerequisites** | Approved change or declared incident; application teams informed; services drained; last backup confirmed |
| **Privileges** | `SYSDBA` (or `SYSOPER`); OS access as the software owner; `srvctl` rights with Grid Infrastructure |

```bash
# With Grid Infrastructure / Oracle Restart (preferred: Clusterware tracks the target state)
srvctl stop database  -db FMPRD -stopoption IMMEDIATE
srvctl start database -db FMPRD
srvctl status database -db FMPRD -verbose
```

```sql
-- Without Grid Infrastructure
SHUTDOWN IMMEDIATE
STARTUP
ALTER PLUGGABLE DATABASE ALL OPEN;        -- unless state was saved
ALTER PLUGGABLE DATABASE ALL SAVE STATE;  -- once, so PDBs reopen automatically
```

**Expected output (illustrative):**

```text
Database closed.
Database dismounted.
ORACLE instance shut down.
...
Database mounted.
Database opened.
```

**Verification**

```sql
SELECT instance_name, status, database_status FROM v$instance;   -- OPEN / ACTIVE
SELECT name, open_mode FROM v$pdbs;                              -- READ WRITE
```

Check the listener (`lsnrctl status`), that services are registered, the alert
log for errors, and an application health check.

**Rollback:** if startup fails at `MOUNT` or `OPEN`, do not improvise: read the
error and the alert log; the cause is usually a missing file or parameter.

**Troubleshooting**

| Symptom | Likely cause |
|---|---|
| `SHUTDOWN IMMEDIATE` hangs | A large transaction is rolling back, or a session is stuck. Check the alert log; wait. Use `ABORT` only as an emergency decision |
| `ORA-01078` / `LRM-00109` | Parameter file not found: wrong `ORACLE_SID` or home |
| `ORA-00205` | Control file not found |
| `ORA-01157` / `ORA-01110` | A data file is missing: go to the recovery runbook |
| PDBs stay `MOUNTED` | State not saved |

!!! danger "Safety"
    `SHUTDOWN ABORT` is safe for data (instance recovery runs at startup) but
    it is an emergency action: never before a cold backup, and never as a
    habit. On a Data Guard primary, an unplanned shutdown may trigger
    Fast-Start Failover: disable or account for the observer first.

---

## 2. Session investigation

| | |
|---|---|
| **Objective** | Find who is connected and what they are doing |
| **Privileges** | `SELECT` on `V$SESSION`, `V$SQL` (for example `SELECT_CATALOG_ROLE`) |

```sql
--8<-- "sql/administration/sessions_locks.sql:sessions"
```

**Expected output (illustrative):**

| SID | SERIAL# | USERNAME | STATUS | SQL_ID | EVENT | SECONDS_IN_WAIT | BLOCKING_SESSION |
|---:|---:|---|---|---|---|---:|---:|
| 412 | 30511 | FM_APP | ACTIVE | 7h3k9xq2m4b1a | enq: TX - row lock contention | 184 | 97 |
| 97 | 1220 | FM_APP | INACTIVE | | SQL*Net message from client | 190 | |

Reading it: `ACTIVE` sessions are in a call; `INACTIVE` with
`SQL*Net message from client` are idle (normal for a pool). An **inactive
session that blocks others** is an application that has not committed.

**Verification:** counts per user match the expected pool sizes; no unexpected
programs or machines.

**Troubleshooting:** session counts near `SESSIONS`/`PROCESSES` limits point to
a connection leak or oversized pools: see `V$RESOURCE_LIMIT`.

---

## 3. Blocking session investigation

| | |
|---|---|
| **Objective** | Identify the root blocker, what it holds, and resolve the blockage |
| **Privileges** | `V$` access; `ALTER SYSTEM` to kill sessions |

```sql
--8<-- "sql/administration/sessions_locks.sql:blockers"
```

**Expected output (illustrative):**

```text
SESSION_TREE   USERNAME  STATUS    EVENT                           SECONDS_IN_WAIT
97,1220        FM_APP    INACTIVE  SQL*Net message from client     190
  412,30511    FM_APP    ACTIVE    enq: TX - row lock contention   184
  530,771      FM_APP    ACTIVE    enq: TX - row lock contention   120
```

**Decision steps**

1. Identify the root blocker (top of the tree) and its owner (`machine`, `module`, `client_identifier`).
2. Is its transaction still doing work, or idle? Check `V$TRANSACTION.USED_UREC` twice, a few seconds apart.
3. Contact the owner. If the application has hung or the user has gone, obtain approval to end the session.
4. Prefer the least destructive action:

```sql
ALTER SYSTEM CANCEL SQL '97,1220';                         -- 18c+: only if it is running a statement
ALTER SYSTEM DISCONNECT SESSION '97,1220' POST_TRANSACTION;
ALTER SYSTEM KILL SESSION '97,1220' IMMEDIATE;             -- rolls back its transaction
```

**Verification:** the waiters proceed; the blocker tree query returns no rows.

**Rollback:** a kill cannot be undone; the blocker's uncommitted work is lost
by design.

**Troubleshooting**

| Symptom | Cause |
|---|---|
| Killed session stays `KILLED` for a long time | It is rolling back; watch `USED_UREC` fall |
| Waiters on `enq: TM - contention` | Unindexed foreign key or DDL waiting |
| Blocker is a job or batch | Long transaction design: fix the code |
| The same blocker pattern recurs | Transaction held across user think-time or a remote call |

!!! danger "Safety"
    Killing a session destroys someone's uncommitted work and may leave an
    application in an inconsistent *business* state. Record who approved it.
    Never kill background processes or sessions of `SYS` replication/apply
    processes.

---

## 4. Deadlock investigation

| | |
|---|---|
| **Objective** | Find which statements and objects were involved in an `ORA-00060` and prevent recurrence |
| **Privileges** | Read access to the ADR trace directory; `V$DIAG_ALERT_EXT` |

```sql
SELECT originating_timestamp, message_text
FROM   v$diag_alert_ext
WHERE  message_text LIKE '%ORA-00060%' AND originating_timestamp > SYSTIMESTAMP - INTERVAL '1' DAY;
```

The alert log entry names a trace file. Open it and read the **deadlock graph**:

```text
Deadlock graph:
                       ---------Blocker(s)--------  ---------Waiter(s)---------
Resource Name          process session holds waits  process session holds waits
TX-00090012-0000a1b2        45     412     X             51     530           X
TX-000a0007-00009c11        51     530     X             45     412           X

session 412: UPDATE inventory SET qty_reserved = ... WHERE warehouse_id = 1 AND product_id = 5
session 530: UPDATE inventory SET qty_reserved = ... WHERE warehouse_id = 1 AND product_id = 11
```

| Graph pattern | Meaning | Fix |
|---|---|---|
| Two `TX` resources, both held `X`, waited `X` | Row-level: sessions lock the same rows in opposite order | Lock in a consistent order |
| `TX` waits in mode `S` (4) | Unique/primary key collision on uncommitted inserts, ITL shortage, or bitmap index | Fix key generation; raise `INITRANS`; replace bitmap index |
| `TM` resources | Unindexed foreign key | Create the index |
| Single session in the graph | Autonomous transaction deadlocking with its caller | Remove the autonomous transaction |

**Verification:** after the fix, no new `ORA-00060` lines over a full business
cycle.

**Rollback:** not applicable (investigation only).

**Safety:** Oracle already resolved the deadlock by failing one statement.
There is nothing to kill. The work is in the application code.

---

## 5. Long-running SQL investigation

| | |
|---|---|
| **Objective** | Decide whether a long statement is working, waiting or stuck, and act |
| **Privileges** | `V$` access; `ALTER SYSTEM` to cancel |

```sql
--8<-- "sql/administration/sessions_locks.sql:longsql"
```

**Decision table**

| Observation | Meaning | Action |
|---|---|---|
| `EVENT` is a lock wait | Blocked, not slow | Runbook 3 |
| On CPU or I/O, `V$SESSION_LONGOPS` advancing | Working | Estimate completion; decide with the owner |
| Plan differs from the usual one (`plan_hash_value`) | Plan regression | Runbook 11; SQL plan baseline |
| Estimated rows far from actual | Statistics problem | Gather statistics; see [3.6](../performance-engineering/02-optimizer-statistics-spm.md) |
| `direct path write temp` dominating | Sort/hash spilling to temp | Check PGA, temp space, the plan |
| Parallel statement downgraded to serial | No PX servers available | Check `V$PX_SESSION`, Resource Manager |

With the Tuning Pack, `DBMS_SQL_MONITOR.REPORT_SQL_MONITOR` shows live progress
per plan line.

```sql
ALTER SYSTEM CANCEL SQL '412,30511';   -- 18c+: ends the statement, keeps the session
```

**Verification:** the statement completes or is cancelled; resource use returns
to baseline.

**Rollback:** a cancelled DML statement rolls back; that can take as long as it
ran. Do not restart the instance to "speed it up": rollback resumes at startup.

!!! danger "Safety"
    Cancelling a batch statement may breach a business deadline; cancelling a
    statement in the middle of a non-restartable job may leave partial work.
    Confirm with the job owner.
