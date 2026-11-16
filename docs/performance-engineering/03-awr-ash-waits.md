---
tags: [stage-3, performance, awr, ash]
---

# 3.7 AWR, ASH and wait analysis

!!! abstract "Chapter card"
    **Stage:** 3 · **Prerequisites:** 3.1, 3.6 · **Time:** 6 hours ·
    :material-license: AWR, ASH and ADDM need the **Diagnostics Pack**; SQL Monitoring needs the **Tuning Pack**

## At a glance

| Subtopic | In one line |
|---|---|
| DB time | The one metric: time sessions spend working or waiting in the database |
| Wait events and classes | Where non-CPU time goes |
| AWR | Hourly snapshots of workload statistics; reports compare two snapshots |
| ASH | One sample per second of every active session |
| ADDM | Automatic analysis of an AWR period |
| Real-Time SQL Monitoring | Live view of long-running statements |
| Latches and mutexes | Short-term memory locks and their contention |
| Bottleneck patterns | CPU, I/O, memory, locking, commit |
| Baselines and benchmarking | Knowing what "normal" is |

Without the packs: **Statspack** (free, AWR's ancestor), `V$` views sampled by
your own scripts, and SQL trace (`DBMS_MONITOR`, `tkprof`).

## 1. The method: follow the time

**DB time** = time spent by foreground sessions in database calls
= **CPU time + non-idle wait time**.

**Average active sessions (AAS)** = DB time ÷ elapsed time.

| AAS compared with CPU cores | Meaning |
|---|---|
| Well below | Headroom |
| About equal, mostly on CPU | CPU saturated |
| Far above | Sessions are queueing: on CPU, I/O or locks |

The method is always the same: find where the time goes (which wait class,
which SQL, which session), reduce the largest part, measure again. Ratios such
as the buffer cache hit ratio do not tell you where time goes.

## 2. Wait events

A session is either **on CPU** or **waiting** on a named event.

| Wait class | Typical events | Usual meaning |
|---|---|---|
| **User I/O** | `db file sequential read` (single block: index access), `db file scattered read` (multiblock: full scans), `direct path read` | Physical reads. Is the SQL reading too much, or is storage slow? |
| **System I/O** | `log file parallel write`, `db file parallel write` | Background writers |
| **Commit** | `log file sync` | Waiting for LGWR at commit |
| **Concurrency** | `buffer busy waits`, `latch: cache buffers chains`, `library cache lock`, `cursor: pin S wait on X`, `row cache lock` | Sessions competing for shared memory structures |
| **Application** | `enq: TX - row lock contention`, `enq: TM - contention` | Application locking |
| **Configuration** | `log file switch (checkpoint incomplete)`, `enq: HW - contention`, `free buffer waits` | Something is undersized |
| **Network** | `SQL*Net more data to client` | Large results, slow clients |
| **Cluster** | `gc buffer busy acquire`, `gc cr block busy` | RAC block transfers |
| **Idle** | `SQL*Net message from client` | Waiting for the application: not database time |
| **Scheduler** | `resmgr:cpu quantum` | Throttled by Resource Manager |

```sql
-- What is everyone doing right now?
SELECT NVL(event, 'ON CPU') AS event, wait_class, COUNT(*) AS sessions
FROM   v$session
WHERE  type = 'USER' AND status = 'ACTIVE'
GROUP  BY event, wait_class ORDER BY sessions DESC;
```

## 3. AWR

The **Automatic Workload Repository** stores snapshots (default every 60
minutes, kept 8 days) of system statistics, wait events, top SQL, segment
statistics and more in `SYSAUX`.

```sql
EXEC DBMS_WORKLOAD_REPOSITORY.CREATE_SNAPSHOT;                           -- manual snapshot
EXEC DBMS_WORKLOAD_REPOSITORY.MODIFY_SNAPSHOT_SETTINGS(retention => 43200, interval => 30);  -- 30 days, 30 min

@?/rdbms/admin/awrrpt.sql      -- report between two snapshots
@?/rdbms/admin/awrddrpt.sql    -- compare two periods (good hour versus bad hour)
@?/rdbms/admin/awrsqrpt.sql    -- one SQL statement
@?/rdbms/admin/ashrpt.sql      -- ASH report
```

In a CDB, AWR exists at both the CDB and the PDB level (PDB snapshots are
controlled by `AWR_PDB_AUTOFLUSH_ENABLED`).

### Reading an AWR report in ten minutes

| Section | Look for |
|---|---|
| Header | Elapsed versus **DB time**: divide to get AAS. Compare with CPU count |
| **Load profile** | Per-second redo, logical/physical reads, executes, hard parses, transactions. Compare with a normal period |
| Instance efficiency | Soft parse %, execute-to-parse. Context only |
| **Top 10 foreground events** | Which events and wait classes own the DB time, and the **average wait**. `DB CPU` appears here too |
| Time model | SQL execution, parse time, hard parse time, PL/SQL time |
| **SQL ordered by** elapsed time / CPU / gets / reads / executions | The statements that own the time. Note `sql_id` and per-execution figures |
| Segments by logical / physical reads, row lock waits, buffer busy waits | Which objects |
| Advisory sections | SGA, PGA and buffer cache advice |
| Parameter changes | What changed |

Choose a short interval that brackets the problem. A 24-hour report averages a
20-minute incident into invisibility.

## 4. ASH

**Active Session History** samples every active session **once a second** into
memory (`V$ACTIVE_SESSION_HISTORY`); one sample in ten is kept in AWR
(`DBA_HIST_ACTIVE_SESS_HISTORY`). Each sample is roughly one second of DB time,
so counting samples measures time.

```sql
-- Top SQL and events for a 15-minute window
SELECT sql_id, NVL(event, 'ON CPU') AS event, COUNT(*) AS seconds
FROM   v$active_session_history
WHERE  sample_time BETWEEN TIMESTAMP '2026-03-14 10:00:00' AND TIMESTAMP '2026-03-14 10:15:00'
GROUP  BY sql_id, event
ORDER  BY seconds DESC FETCH FIRST 10 ROWS ONLY;

-- Who was blocking whom?
SELECT blocking_session, COUNT(*) AS blocked_seconds, MIN(sample_time), MAX(sample_time)
FROM   v$active_session_history
WHERE  event = 'enq: TX - row lock contention'
GROUP  BY blocking_session ORDER BY 2 DESC;
```

AWR tells you *what* was heavy over an hour. ASH tells you *who, when and why*
to the second: by SQL, plan line, module, user, object, blocker. For transient
problems ASH is the tool.

## 5. ADDM and the advisors

**ADDM** runs after every snapshot and writes findings ranked by impact in DB
time, with recommendations (tune this SQL, add CPU, resize the SGA, application
lock contention on this object). Read it first; verify before acting.

Others: **SQL Tuning Advisor** (profiles, indexes, restructuring; Tuning Pack),
**SQL Access Advisor** (indexes, MVs, partitions), **Segment Advisor**,
memory advisors.

## 6. Real-Time SQL Monitoring

Statements that run longer than 5 seconds of CPU/I/O, or in parallel, are
monitored automatically (or with the `MONITOR` hint).

```sql
SELECT DBMS_SQL_MONITOR.REPORT_SQL_MONITOR(sql_id => '&sql_id', type => 'TEXT', report_level => 'ALL')
FROM   dual;
```

The report shows, per plan line and live: estimated versus actual rows, time,
I/O, memory and temp, and where the statement is right now. It is the best
single tool for a long-running query.

Without it: `V$SESSION_LONGOPS` (progress of scans, sorts and RMAN),
`V$SQL_PLAN_STATISTICS_ALL`, and SQL trace:

```sql
EXEC DBMS_MONITOR.SESSION_TRACE_ENABLE(session_id => 123, serial_num => 45678, waits => TRUE, binds => TRUE);
-- reproduce, then
EXEC DBMS_MONITOR.SESSION_TRACE_DISABLE(123, 45678);
-- tkprof trace_file.trc out.txt sort=exeela,fchela
```

## 7. Latches and mutexes

Locks (enqueues) protect *data* and are held for the length of a transaction;
sessions queue in order. **Latches** and **mutexes** protect *memory
structures* and are held for microseconds; a session that cannot get one spins
on CPU and then sleeps.

| Contention | Structure | Usual root cause |
|---|---|---|
| `latch: cache buffers chains` | Buffer cache hash chains | A few very hot blocks: inefficient SQL repeatedly reading the same blocks, hot index root or leaf |
| `latch: shared pool`, `library cache: mutex X` | Shared pool / library cache | Hard parsing (no binds), shared pool too small |
| `cursor: pin S wait on X` | A cursor being compiled | Many sessions parsing the same statement at once; high version counts |
| `buffer busy waits` | A buffer being read or changed by another session | Concurrent inserts into the same blocks (right-hand index growth); too few ITL slots |
| `enq: HW - contention` | Segment high-water mark | Many sessions extending one segment (LOBs) |
| `row cache lock` | Dictionary cache | Sequences with `NOCACHE`, heavy DDL |

Latch contention is nearly always a **symptom of workload**: fix the SQL or the
design, not latch parameters.

## 8. Bottleneck patterns

| Pattern | Evidence | Typical causes | Response |
|---|---|---|---|
| **CPU** | `DB CPU` dominates; AAS ≥ cores; run queue on the host | Inefficient SQL (high buffer gets), hard parsing, too many active sessions, PL/SQL row-by-row | Tune top SQL by gets; binds; smaller pools; Resource Manager |
| **I/O** | User I/O dominates; average `db file sequential read` above expectations | Full scans, poor indexing, small buffer cache, slow storage | Tune SQL first; then cache; then storage |
| **Memory** | `direct path read/write temp`; PGA advisory shows multi-pass; `ORA-04031` | Large sorts and hash joins; shared pool pressure; swapping | Size PGA/SGA; fix parsing; HugePages |
| **Locking** | Application class; `enq: TX` | Long transactions, unindexed foreign keys, hot rows | Find the blocker; fix transaction design |
| **Commit** | `log file sync` high | Commit per row; slow redo storage; sync Data Guard latency | Batch commits; faster redo device |
| **Configuration** | `log file switch`, `free buffer waits` | Small redo logs, slow DBWn | Resize logs; check I/O |

## 9. Baselines and benchmarking

- **AWR baselines** keep a set of snapshots forever (`DBMS_WORKLOAD_REPOSITORY.CREATE_BASELINE`) for "compare with last month's peak". The **moving window baseline** feeds adaptive alert thresholds.
- Capture a baseline for every important period: month-end, peak sale day, before each upgrade.
- **Benchmarking rules:** production-like data volume and skew; realistic concurrency and think time; warm-up; measure response-time percentiles (p95, p99), not averages; change one thing at a time; record the configuration with the result.
- **Real Application Testing** (:material-license: option): *Database Replay* captures a real production workload and replays it against a test system; *SQL Performance Analyzer* runs each captured statement before and after a change and reports regressions.

## 10. Capacity planning from AWR

`DBA_HIST_SYSMETRIC_SUMMARY`, `DBA_HIST_OSSTAT` and segment growth history give
trends for CPU use, I/O rate, redo rate and storage. Plan on **peak** hours, not
averages, and express capacity as headroom: "at the current growth of 4% a
month, peak AAS reaches 80% of cores in 9 months." Method in
[FreshMart scaling](../grocery-application/05-scaling.md).

## 11. Common mistakes

- Tuning by hit ratios or by "the top SQL by executions".
- Reading a report for too long an interval.
- Treating idle waits as a problem.
- Adding CPUs to a system whose time is spent on locks.
- Using AWR/ASH views without the Diagnostics Pack licence (queries on `DBA_HIST_*` and `V$ACTIVE_SESSION_HISTORY` count as use).

## FreshMart example

=== "Scenario"

    During a Saturday promotion, checkout slows from 200 ms to 6 seconds
    between 11:00 and 11:20. CPU on the host is only 35%.

=== "Diagnosis"

    ```sql
    SELECT NVL(event, 'ON CPU') AS event, COUNT(*) AS seconds,
           ROUND(100 * RATIO_TO_REPORT(COUNT(*)) OVER (), 1) AS pct
    FROM   v$active_session_history
    WHERE  sample_time BETWEEN TIMESTAMP '2026-03-14 11:00:00' AND TIMESTAMP '2026-03-14 11:20:00'
    GROUP  BY event ORDER BY seconds DESC FETCH FIRST 5 ROWS ONLY;
    ```

    *Illustrative result:*

    | EVENT | SECONDS | PCT |
    |---|---:|---:|
    | enq: TX - row lock contention | 41200 | 78.4 |
    | ON CPU | 6100 | 11.6 |
    | log file sync | 2900 | 5.5 |
    | db file sequential read | 1800 | 3.4 |

    78% of DB time is lock waiting, so CPU is idle. Next: on what?

    ```sql
    SELECT o.object_name, a.sql_id, COUNT(*) AS seconds
    FROM   v$active_session_history a
    JOIN   dba_objects o ON o.object_id = a.current_obj#
    WHERE  a.event = 'enq: TX - row lock contention'
    AND    a.sample_time BETWEEN TIMESTAMP '2026-03-14 11:00:00' AND TIMESTAMP '2026-03-14 11:20:00'
    GROUP  BY o.object_name, a.sql_id ORDER BY seconds DESC;
    -- INVENTORY, the reservation UPDATE: one promoted product in one warehouse
    ```

=== "Fix"

    Every checkout of the promoted product updates the **same inventory row**
    and holds the lock until its transaction commits, which included a call to
    the payment gateway. Fix: reserve stock in a short transaction of its own
    and commit *before* calling the gateway (releasing the reservation if
    payment fails). Lock hold time falls from seconds to milliseconds. See
    [incident 3](../performance-incidents/01-incidents.md).

=== "Takeaway"

    The host looked healthy and the database "was not busy". Time-based
    analysis found the cause in two queries: sessions were not working, they
    were waiting in line. More hardware would have changed nothing.

## Check yourself

??? question "Interview questions"
    1. **(Intermediate)** What is DB time?
    2. **(Intermediate)** `db file sequential read` versus `db file scattered read`?
    3. **(Senior)** When do you use ASH instead of AWR?
    4. **(Senior)** High `log file sync`: how do you tell an application cause from a storage cause? *Compare with `log file parallel write` (LGWR's own I/O time) and the commit rate; a large gap or very high commits per second points to the application or CPU starvation of LGWR.*
    5. **(Architect)** How do you set performance objectives a database team can be held to? *Response-time percentiles per business transaction measured at the service boundary, tied to services in the database (`V$SERVICE_STATS`), with AWR baselines for peak periods and alerting on deviation, not on raw resource thresholds.*

??? example "Exercises"
    1. Generate an AWR report for the last hour and compute AAS.
    2. Create a row-lock wait between two sessions and find it in `V$ACTIVE_SESSION_HISTORY`.
    3. Trace a session with `DBMS_MONITOR`, run `tkprof`, and identify the statement with the most elapsed time.

## Related

Next: [3.8 RAC, Clusterware and ASM](../high-availability/01-rac-asm.md).
Practice: [performance incidents](../performance-incidents/01-incidents.md).
