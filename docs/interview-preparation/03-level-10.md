---
tags: [interview, stage-3]
---

# Interview bank: 10 years (senior DBA and performance)

55 questions (worked ones included). Chapters: Stage 3, runbooks, incidents.

## Worked questions :material-star:

### W1. Users report the system is slow. Walk me through your first fifteen minutes.

**Answer.**

1. **Scope**: everyone or one function? Since when? What changed (release, load, statistics job, patch)?
2. **Where is the time?** Active sessions by wait class now (`V$SESSION`, ASH). Compare average active sessions with CPU cores.
3. **Branch on the dominant class**: Application → find the blocker; CPU → top SQL by CPU/gets, hard parses; User I/O → top SQL by reads, plan changes; Commit → `log file sync` versus `log file parallel write`; Configuration → logs, space.
4. **Which SQL?** `sql_id`, per-execution elapsed and buffer gets, `plan_hash_value` history.
5. **Stabilize**: cancel a runaway statement, release a blocker, restore the previous plan with a baseline. One change at a time, recorded.
6. **Preserve evidence**: AWR snapshot, ASH extract, the plans.

**Scenario.** [Incident 3](../performance-incidents/01-incidents.md): low CPU, 78% of DB time in row-lock waits.
**Follow-ups.** What if there is no Diagnostics Pack? (Statspack, `V$` sampling, SQL trace.) What would you never do first? (Restart, flush the shared pool, add hints blind.)
**Common wrong answer.** "Check the buffer cache hit ratio" or "increase the SGA".

### W2. A developer dropped a table in production ten minutes ago. Options?

**Answer, in order of preference.**

1. `FLASHBACK TABLE t TO BEFORE DROP` if it is in the recycle bin (not `PURGE`d). Seconds. Rename indexes and constraints afterwards; foreign keys *to* the table from others must be recreated.
2. If purged: `RECOVER TABLE ... UNTIL TIME ... AUXILIARY DESTINATION ...` from RMAN backups into a new name, then put it in place.
3. Data Pump import from a recent export, plus reapplying later changes if available.
4. PDB or database point-in-time recovery only if the damage is wide, because it discards everything after the target time.

**Follow-ups.** What does Flashback Database need? What is lost in a PITR? How do you stop this happening again? (No DDL rights for people in production; Database Vault command rules; pipeline-only changes.)
**Common wrong answer.** "Restore the database to before the drop" as the first move.

### W3. Explain what happens between `COMMIT` and the data being safe on disk.

**Answer.** The change was already made in the buffer cache, with undo recorded
and redo generated into the log buffer. `COMMIT` adds a commit record and
signals LGWR, which writes the log buffer to the online redo log; the session
waits on `log file sync` until that write is acknowledged. That is durability.
DBWn writes the modified data blocks later, in the background. After a crash,
instance recovery rolls forward from the redo and rolls back uncommitted
transactions using undo.

**Follow-ups.** Why multiplex redo? What is group commit? What does `COMMIT WRITE NOWAIT` trade away? What does SYNC Data Guard add to the wait?
**Common wrong answer.** "Commit writes the changed blocks to the data files."

### W4. A critical query changed plan overnight and is 100 times slower. What do you do now, and what afterwards?

**Now.** Confirm the plan change (`V$SQL`/`DBA_HIST_SQLSTAT` by
`plan_hash_value`). Load the previous good plan into a SQL plan baseline from
the cursor cache or AWR, verify it is used, and purge the bad cursor if needed.

**Afterwards.** Find why: statistics gathered (compare history, restore if
wrong), a histogram gained or lost, bind peeking with an atypical value, a new
index, a parameter or patch change. Fix the cause (statistics preferences,
extended statistics), then let the baseline evolve.

**Follow-ups.** Profile versus baseline versus patch? How do you prevent it across an upgrade?
**Common wrong answer.** Adding a hint to the application as the fix.

### W5. RAC or Data Guard: which one do I need?

**Answer.** They solve different problems. RAC protects against instance and
server failure and allows rolling maintenance; all instances share one
database, so it does not protect against storage loss, site loss, corruption or
human error. Data Guard keeps a separate synchronized copy, covering those,
with a role transition of about a minute. Most critical systems need Data
Guard; RAC is added when server-failure RTO must be seconds or patch windows
are unavailable.

**Follow-ups.** What does neither cover? (Logical errors: flashback and backups.) What is Active Data Guard? What is Fast-Start Failover?

## Architecture and storage

| # | Question | Answer |
|---|---|---|
| 1 | Instance versus database? | Memory and processes versus files. |
| 2 | Main SGA components? | Buffer cache, shared pool (library and dictionary caches), redo log buffer, large pool, optional In-Memory area. |
| 3 | What is the PGA used for? | Session memory and SQL work areas for sorts and hash joins. |
| 4 | What do DBWn, LGWR, CKPT, SMON, PMON, ARCn do? | Write dirty buffers; write redo; record checkpoints; instance recovery and cleanup; clean up failed sessions; archive redo logs. |
| 5 | Hard parse versus soft parse? | Full optimization and plan creation versus reuse of a cached cursor. |
| 6 | Logical versus physical I/O? | Block read from the buffer cache versus from disk. |
| 7 | What is a checkpoint? | The point up to which all changes are in the data files; bounds crash recovery time. |
| 8 | What is the high-water mark? | The boundary of formatted blocks in a segment; full scans read up to it; `DELETE` does not lower it. |
| 9 | Causes of `ORA-01555`? | Needed undo overwritten: long queries, small undo, fetch across commit. |
| 10 | Dedicated versus shared server? | One server process per session versus a shared pool of server processes. |
| 11 | What is a service and why connect to one? | A named workload; the unit of measurement, placement and failover. |
| 12 | CDB versus PDB; common versus local user? | Container with shared instance versus a pluggable application database; a `C##` user in all containers versus a user in one PDB. |
| 13 | What happens when the archive destination fills? | Log switches cannot complete and the database hangs (`ORA-00257`). |
| 14 | What does `NOLOGGING` risk? | Unrecoverable blocks after media recovery and corrupt blocks on a standby unless `FORCE LOGGING` is set. |
| 15 | Startup stages? | NOMOUNT (parameter file), MOUNT (control file), OPEN (data files and redo). |

## Backup, recovery, security

| # | Question | Answer |
|---|---|---|
| 16 | RTO versus RPO? | Time to restore service versus the data you may lose. |
| 17 | Differential versus cumulative incremental? | Changes since the last level 1 or 0 versus since the last level 0. |
| 18 | What is block change tracking? | A file recording changed blocks so incrementals avoid full scans. |
| 19 | What requires `OPEN RESETLOGS`? | Incomplete recovery, recovery with a backup control file, failover/flashback of a database. |
| 20 | How do you validate backups? | `RESTORE ... VALIDATE`, `BACKUP VALIDATE CHECK LOGICAL`, and periodic real restores. |
| 21 | Recovery catalog versus control file? | A separate schema with long history for many databases versus limited local history. |
| 22 | Name the flashback features. | Query, Versions, Table, Drop, Transaction, Data Archive, Database. |
| 23 | What is a guaranteed restore point? | A point the database can always flash back to; it retains flashback logs until dropped. |
| 24 | Is a standby a backup? | No. It replicates mistakes. |
| 25 | What does TDE protect against? | Theft of files, disks and backups; not privileged database users. |
| 26 | What is VPD? | A policy that appends predicates to statements for row-level security. |
| 27 | Unified Auditing versus traditional? | One trail and policy-based; traditional is desupported in 23ai. |
| 28 | How do you restrict DBAs from reading application data? | Database Vault realms, separation of duties, privileged access management, audit. |
| 29 | Least privilege for an application account? | `CREATE SESSION` plus `EXECUTE` on APIs and needed object grants; no DDL, no `ANY`. |
| 30 | How do you rotate a service password without an outage? | Gradual password rollover: old and new both valid for a period. |

## Performance

| # | Question | Answer |
|---|---|---|
| 31 | What is DB time? | Foreground session time on CPU or in non-idle waits. |
| 32 | AWR versus ASH versus ADDM? | Periodic workload snapshots; per-second samples of active sessions; automated analysis of AWR. |
| 33 | `db file sequential read` versus `scattered read`? | Single-block reads (indexes) versus multiblock reads (full scans). |
| 34 | What does high `log file sync` indicate? | Commit waits: too many commits, slow redo storage, LGWR starved, or SYNC standby latency. |
| 35 | Latch versus enqueue? | Short memory-structure protection with spinning versus queued, transaction-length locks. |
| 36 | What causes `cursor: pin S wait on X` and shared pool latch contention? | Hard parsing and high version counts. |
| 37 | What is a histogram and when is it created? | Column value distribution for skewed data; created when the column is skewed and used in predicates. |
| 38 | What are extended statistics? | Statistics on column groups or expressions to fix correlation and function estimates. |
| 39 | What is adaptive cursor sharing? | Several plans for one statement depending on bind selectivity. |
| 40 | SQL profile versus plan baseline? | Estimate corrections versus a set of accepted plans. |
| 41 | When is parallel query appropriate? | Large scans in warehouse and batch workloads with spare resources; rarely in OLTP. |
| 42 | What is the clustering factor? | How well table order follows index order; drives the cost of range scans. |
| 43 | How do you diagnose one slow session? | SQL trace with waits and binds, `tkprof`; or SQL Monitor. |
| 44 | Why can adding CPUs not help? | The time is in waits (locks, I/O, commits), not CPU. |

## Availability and operations

| # | Question | Answer |
|---|---|---|
| 45 | What is Cache Fusion? | Transfer of blocks between RAC instances over the interconnect. |
| 46 | SCAN and VIPs? | A single cluster address resolving to listeners; node addresses that fail over for fast error detection. |
| 47 | Data Guard protection modes? | Maximum Performance (ASYNC), Availability (SYNC, continues if the standby is lost), Protection (SYNC, primary stops rather than lose data). |
| 48 | Switchover versus failover? | Planned, no loss, reversible versus unplanned, possible loss, old primary needs reinstating. |
| 49 | How do you patch with minimal downtime? | Out-of-place homes; RAC rolling; standby-first with switchover; `datapatch`. |
| 50 | How do you upgrade 19c to 26ai? | AutoUpgrade (analyze, fixups, deploy) with a restore point; non-CDB converted to a PDB; baselines captured; `COMPATIBLE` raised later. |
