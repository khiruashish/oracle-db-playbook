---
tags: [runbooks, data-guard, rac, capacity]
---

# Runbooks: Data Guard, RAC, capacity, alert log

## 22. Data Guard health checks

| | |
|---|---|
| **Objective** | Confirm the standby can take over within the agreed RPO and RTO |
| **Privileges** | `SYSDG` (or `SYSDBA`); `dgmgrl` access |

```text
DGMGRL> SHOW CONFIGURATION VERBOSE;
DGMGRL> SHOW DATABASE fm_sby;
DGMGRL> VALIDATE DATABASE fm_sby;
DGMGRL> VALIDATE NETWORK CONFIGURATION FOR ALL;
DGMGRL> SHOW FAST_START FAILOVER;
```

```sql
-- On the standby
SELECT name, value, time_computed, datum_time FROM v$dataguard_stats
WHERE  name IN ('transport lag', 'apply lag', 'apply finish time');

SELECT process, status, thread#, sequence#, block# FROM v$managed_standby
WHERE  process LIKE 'MRP%' OR process LIKE 'RFS%';

-- On the primary
SELECT dest_id, status, error, gap_status FROM v$archive_dest_status WHERE dest_id IN (2, 3);
SELECT database_role, protection_mode, protection_level, switchover_status,
       flashback_on, force_logging FROM v$database;
```

(`V$MANAGED_STANDBY` is deprecated in favor of `V$DATAGUARD_PROCESS` in recent
releases.)

**Expected (illustrative):**

```text
Configuration - fm_dg
  Protection Mode: MaxAvailability
  Members:
  fm_prd - Primary database
    fm_sby - (*) Physical standby database
    fm_dr  - Physical standby database
Fast-Start Failover: Enabled in Zero Data Loss Mode
Configuration Status: SUCCESS
```

| Check | Healthy |
|---|---|
| Configuration status | `SUCCESS` |
| Transport lag, apply lag | Near zero for SYNC; seconds for ASYNC; within the RPO alert threshold |
| `VALIDATE DATABASE` | "Ready for Switchover: Yes", "Ready for Failover: Yes"; standby redo logs correct |
| `gap_status` | `NO GAP` |
| `protection_level` equals `protection_mode` | Otherwise the configuration has fallen back |
| Flashback on, force logging on | Both `YES` |
| Observer | Present and connected |

**Troubleshooting**

| Symptom | Cause / action |
|---|---|
| `ORA-16853` / growing apply lag | Standby I/O or CPU; MRP stopped; check its alert log |
| `ORA-12541`, `ORA-12154`, `ORA-16198` transport errors | Network, listener, firewall, TNS |
| Gap not resolving | Archived log missing on the primary: restore it from backup, or roll the standby forward with `RECOVER STANDBY DATABASE FROM SERVICE` |
| `ORA-01017` on transport | Password file out of sync: copy it to the standby |
| New data file not created on standby | `STANDBY_FILE_MANAGEMENT = MANUAL` |
| `protection_level` is `RESYNCHRONIZATION` | SYNC standby was unreachable; wait or investigate |

**Rollback:** not applicable.

!!! danger "Safety"
    Health checks are read-only. `SWITCHOVER` and `FAILOVER` are **not** part
    of a health check: they follow the DR runbook and need approval. Never open
    a standby read-write outside a controlled snapshot-standby conversion.

---

## 23. RAC health checks

| | |
|---|---|
| **Objective** | Confirm all cluster components are up and the cluster can lose a node |
| **Privileges** | Grid Infrastructure owner (and root for some `crsctl` commands); `SYSDBA`/`SYSRAC` |

```bash
crsctl check cluster -all
crsctl stat res -t                       # all resources and their state per node
olsnodes -n -s -t
srvctl status database -db FMPRD -verbose
srvctl status service  -db FMPRD
srvctl status scan_listener
srvctl status asm
crsctl query css votedisk
ocrcheck
cluvfy comp healthcheck -collect cluster          # or: orachk / exachk
```

```sql
SELECT inst_id, instance_name, status, host_name FROM gv$instance;

-- Interconnect: private network in use
SELECT inst_id, name, ip_address, is_public FROM gv$cluster_interconnects;

-- Global cache health: lost blocks must stay at zero
SELECT inst_id, name, value FROM gv$sysstat
WHERE  name IN ('gc blocks lost', 'gc cr blocks received', 'gc current blocks received');

SELECT name, type, total_mb, free_mb, usable_file_mb, offline_disks FROM v$asm_diskgroup;
```

| Check | Healthy |
|---|---|
| CRS, CSS, EVM | Online on every node |
| Instances, listeners, SCAN, VIPs | `ONLINE` on their intended nodes (a VIP running on another node means its home node is down) |
| Services | Running on preferred instances |
| Voting disks | Odd number, all online |
| OCR | Integrity check succeeded; automatic backups present (`ocrconfig -showbackup`) |
| ASM | No offline disks; `USABLE_FILE_MB` positive; no stuck rebalance |
| `gc blocks lost` | Not increasing |
| Capacity | Remaining nodes can carry peak load if one fails |

**Troubleshooting**

| Symptom | Where to look |
|---|---|
| Node evicted | Clusterware alert log, `ocssd` trace: network heartbeat (interconnect) or disk heartbeat (voting disk) |
| `gc buffer busy`, slow global cache | Interconnect latency/errors, LMS CPU starvation, hot blocks ([3.8](../high-availability/01-rac-asm.md)) |
| Service on the wrong instance after a restart | `srvctl relocate service` back to the preferred instance |
| Instance will not start | Database alert log; ASM disk group mounted? |

Use **Trace File Analyzer** (`tfactl diagcollect`) to gather diagnostics across
nodes for Oracle Support.

!!! danger "Safety"
    `crsctl stop crs`, relocating services and rebalancing ASM change
    production state: they belong to change procedures, not health checks.
    Never remove or reformat ASM disks from the operating system.

---

## 24. Capacity reports

| | |
|---|---|
| **Objective** | Know current use and the date each resource runs out |
| **Privileges** | `DBA_SEGMENTS`, `DBA_DATA_FILES`, `V$RESOURCE_LIMIT`; AWR history views need the :material-license: Diagnostics Pack |

```sql
--8<-- "sql/administration/health_capacity.sql:capacity"
```

**Report content (monthly)**

| Resource | Current | Peak | Limit | Growth per month | Runs out |
|---|---|---|---|---|---|
| Storage: data | | | | | |
| Storage: recovery area, backups | | | | | |
| CPU at peak hour (average active sessions on CPU ÷ cores) | | | | | |
| Memory (SGA/PGA advisories) | | | | | |
| Sessions and processes | | | | | |
| Redo per day; standby network | | | | | |

Method: [5.2 capacity forecasting](../enterprise-architecture/01-global-architecture.md)
and the worked example in [FreshMart scaling](../grocery-application/05-scaling.md).

**Verification:** compare last quarter's forecast with actuals; correct the
growth assumptions.

**Without the Diagnostics Pack:** store a daily snapshot of
`DBA_TABLESPACE_USAGE_METRICS`, `DBA_SEGMENTS` (top 50) and `V$SYSMETRIC` peaks
in your own table with a scheduler job, and trend from that.

**Safety:** read-only. Large `DBA_SEGMENTS` queries can be slow on databases
with very many segments: run off-peak.

---

## 25. Alert-log analysis

| | |
|---|---|
| **Objective** | Detect and classify errors recorded by the instance |
| **Privileges** | `V$DIAG_ALERT_EXT` or OS access to the ADR home; `adrci` |

```sql
--8<-- "sql/administration/health_capacity.sql:alert"
```

```bash
adrci exec="show alert -tail 200"
adrci exec="show problem"
adrci exec="show incident -mode brief -last 20"
```

**Classification**

| Message | Severity | Action |
|---|---|---|
| `ORA-00600`, `ORA-07445` | High | Internal error: an incident was created. Search My Oracle Support with the first argument; package with `ips pack` and open a service request if it recurs or is not a known issue |
| `ORA-01578`, `ORA-01110`, "corrupt block" | Critical | Corruption: runbook 17 (block recovery); check the standby and storage |
| `ORA-00257`, `ORA-19809`, `ORA-16038` | Critical | Archiver stuck: runbook 10 |
| `ORA-01555` | Medium | Undo: runbook 8 |
| `ORA-00060` | Medium | Deadlock: runbook 4 |
| `ORA-04031` | High | Shared pool exhausted: hard parsing or undersized pool |
| `ORA-01652`, `ORA-01653` | High | Space: runbooks 6 and 7 |
| `Checkpoint not complete`, `Thread ... cannot allocate new log` | Medium | Redo logs too small: runbook 9 |
| `ORA-03113`, `ORA-03135`, `TNS-12535` in volume | Medium | Network or dead clients; firewalls dropping idle connections |
| `ORA-28` (session killed), `ORA-1013` | Low | Expected after administrative actions |
| `WARNING: inbound connection timed out` | Low to medium | Slow or abandoned logins; connection storms |
| Startup, shutdown, `ALTER SYSTEM` entries | Information | Correlate with changes |

**Daily health check** (combine with the checks above):

```sql
--8<-- "sql/administration/health_capacity.sql:health"
```

**Verification:** every new error class from the last 24 hours has an owner and
a ticket, or a documented reason to ignore it.

**Housekeeping:** ADR purges by policy (`adrci> show control`,
`set control (SHORTP_POLICY = 720)`); do not delete trace files that belong to
an open incident.

**Safety:** read-only. Automate this: an alert log that is read only after an
outage has no preventive value.
