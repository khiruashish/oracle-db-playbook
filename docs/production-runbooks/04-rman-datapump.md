---
tags: [runbooks, backup, recovery]
---

# Runbooks: RMAN and Data Pump

## 15. RMAN backup

| | |
|---|---|
| **Objective** | Take backups that meet the recovery window |
| **Prerequisites** | ARCHIVELOG mode; destination space; block change tracking enabled (EE) for fast incrementals; keystore open if TDE is used |
| **Privileges** | `SYSBACKUP` (preferred) or `SYSDBA` |

One-time configuration:

```text
--8<-- "sql/backup-recovery/rman_backup.rman:config"
```

Weekly level 0, daily level 1, frequent archive logs:

```text
--8<-- "sql/backup-recovery/rman_backup.rman:level0"
--8<-- "sql/backup-recovery/rman_backup.rman:level1"
--8<-- "sql/backup-recovery/rman_backup.rman:arch"
```

**Expected output (illustrative, end of job):**

```text
Finished backup at 14-MAR-26
Starting Control File and SPFILE Autobackup at 14-MAR-26
piece handle=+RECO/FMPRD/AUTOBACKUP/2026_03_14/s_1195833021.289.1195833023 comment=NONE
Finished Control File and SPFILE Autobackup at 14-MAR-26
```

**Verification**

```sql
SELECT input_type, status, start_time, end_time,
       ROUND(output_bytes / 1073741824, 1) AS output_gb
FROM   v$rman_backup_job_details
WHERE  start_time > SYSDATE - 2 ORDER BY start_time DESC;
```

Status must be `COMPLETED` (not `COMPLETED WITH WARNINGS` without review). Then
`RMAN> REPORT NEED BACKUP;` returns nothing.

**Rollback:** not applicable. A failed backup leaves earlier backups intact.

**Troubleshooting**

| Error | Cause |
|---|---|
| `ORA-19809` / `ORA-19804` | Recovery area full: runbook 10 |
| `RMAN-06059` expected archived log not found | Logs deleted outside RMAN: `CROSSCHECK ARCHIVELOG ALL;` then back up, and take a new level 0 |
| `ORA-19502` / `ORA-27072` | Destination full or I/O error |
| `RMAN-08137` cannot delete archived log | Still needed by a standby or GoldenGate: correct behavior |
| Backup much slower than usual | Block change tracking disabled, or a level 1 without a level 0 base |

!!! danger "Safety"
    `DELETE OBSOLETE` removes backups outside the retention policy: confirm
    the policy (`SHOW RETENTION POLICY`) before the first run, and protect
    long-term backups with `KEEP`. Backups on the same storage as the database
    are not backups.

---

## 16. Backup validation

| | |
|---|---|
| **Objective** | Prove backups are readable and the database is free of corruption |
| **Privileges** | `SYSBACKUP` |

```text
--8<-- "sql/backup-recovery/rman_backup.rman:validate"
```

```sql
SELECT * FROM v$database_block_corruption;      -- must return no rows
```

**Expected:** "validation succeeded" for every piece; no rows of corruption.

**The real test: restore.** At least quarterly, restore to scratch
infrastructure and open the database:

```text
RMAN> DUPLICATE DATABASE TO fmtest BACKUP LOCATION '/backup/FMPRD' NOFILENAMECHECK;
```

Record: backup used, elapsed restore and recovery time (your real RTO), any
missing pieces, any missing keys, and the row-count checks run afterwards.

**Troubleshooting:** a failed validation is an incident. Take a new backup now,
find out when the piece went bad, and check the standby and other copies.

**Safety:** `VALIDATE` is read-only but I/O-intensive: schedule it. Never run a
restore test with the production `DB_NAME` on a host that can see production
storage.

---

## 17. RMAN recovery

| | |
|---|---|
| **Objective** | Restore service after loss or corruption with the smallest possible impact |
| **Prerequisites** | Incident declared; cause understood (what is lost?); the failed files preserved if possible; decision on recovery target approved |
| **Privileges** | `SYSDBA` or `SYSBACKUP` |

**First, diagnose. Do not start restoring.**

```sql
SELECT file#, error, online_status, change#, time FROM v$recover_file;
SELECT file#, name, status FROM v$datafile WHERE status NOT IN ('ONLINE', 'SYSTEM');
SELECT * FROM v$database_block_corruption;
```

```text
RMAN> LIST FAILURE;                       -- Data Recovery Advisor (deprecated, still informative)
RMAN> RESTORE DATABASE PREVIEW SUMMARY;   -- which backups would be used
```

| Situation | Procedure |
|---|---|
| One non-system data file lost | Database stays open |
| A few corrupt blocks | Block media recovery |
| Logical error in one PDB | PDB point-in-time recovery |
| One table damaged, long ago | Table recovery to a new name |
| Everything lost | Full restore and recovery |

```text
--8<-- "sql/backup-recovery/rman_recovery.rman:datafile"
--8<-- "sql/backup-recovery/rman_recovery.rman:block"
```

!!! danger "Destructive: point-in-time recovery discards later transactions"
    ```text
    --8<-- "sql/backup-recovery/rman_recovery.rman:pdbpitr"
    ```
    Everything committed in that PDB after the target time is **gone**.
    Requires written approval from the business owner, a backup taken
    immediately before (so the pre-recovery state can be recovered if the
    target time was wrong), and confirmation that a narrower tool (Flashback
    Query, table recovery) cannot solve the problem.

Table recovery (non-destructive: creates a new table) and full recovery:

```text
--8<-- "sql/backup-recovery/rman_recovery.rman:table"
--8<-- "sql/backup-recovery/rman_recovery.rman:full"
```

**Verification:** no rows in `V$RECOVER_FILE`; database and PDBs open
read-write; application smoke tests; row-count and business reconciliation
checks; **take a new level 0 backup** after any `RESETLOGS`.

**Rollback:** a complete recovery needs none. After an incomplete recovery you
can return to the earlier incarnation only from the backup taken beforehand.

**Troubleshooting**

| Error | Meaning |
|---|---|
| `RMAN-06023` no backup or copy found | Wrong DBID/incarnation, expired or uncataloged backups: `CATALOG START WITH '...'` |
| `RMAN-06054` unknown archived log | Recovery has reached the end of available redo: either a gap (find the log) or the correct stopping point |
| `ORA-01152` file was not restored from a sufficiently old backup | More recovery needed |
| `ORA-28365` wallet is not open | Open the TDE keystore first |
| `ORA-19870` / `ORA-19913` | Backup encrypted: key or password missing |

---

## 18. Data Pump export and import

| | |
|---|---|
| **Objective** | Move or copy schemas and tables logically |
| **Prerequisites** | A directory object with space; source consistent point chosen; target tablespaces and quotas exist |
| **Privileges** | `DATAPUMP_EXP_FULL_DATABASE` / `DATAPUMP_IMP_FULL_DATABASE` for other schemas; `READ, WRITE` on the directory |

```sql
CREATE DIRECTORY dp_dir AS '/u01/datapump';
GRANT READ, WRITE ON DIRECTORY dp_dir TO dp_operator;
```

```bash
# Consistent schema export (parallel needs EE; compression=all needs Advanced Compression)
expdp dp_operator@//dbhost/FRESHMART schemas=FRESHMART directory=DP_DIR \
      dumpfile=fm_%U.dmp logfile=fm_exp.log parallel=4 \
      flashback_time=systimestamp exclude=statistics

# See what an import would do, without doing it
impdp dp_operator@//testhost/FMTEST directory=DP_DIR dumpfile=fm_%U.dmp \
      sqlfile=fm_ddl.sql

# Import under another name
impdp dp_operator@//testhost/FMTEST directory=DP_DIR dumpfile=fm_%U.dmp logfile=fm_imp.log \
      parallel=4 remap_schema=FRESHMART:FM_TEST remap_tablespace=FM_DATA:USERS \
      table_exists_action=skip
```

**Expected (illustrative):**

```text
Job "DP_OPERATOR"."SYS_EXPORT_SCHEMA_01" successfully completed at Sat Mar 14 02:14:09 2026 elapsed 0 00:03:41
```

**Verification:** "successfully completed" with no `ORA-` lines in the log;
compare object counts and row counts per table between source and target;
recompile and check invalid objects; gather statistics.

```sql
SELECT object_type, COUNT(*) FROM dba_objects WHERE owner = 'FM_TEST' GROUP BY object_type ORDER BY 1;
```

**Rollback:** for an import into a new schema, drop the schema (runbook 13
warnings apply). For an import into existing tables there is no automatic
rollback: take a restore point or export first.

!!! danger "Destructive options"
    `table_exists_action=replace` **drops** existing tables;
    `truncate` empties them. Use `skip` or `append` unless replacing is the
    stated intent, and double-check the connect string: importing into
    production instead of test is the classic Data Pump accident.

**Troubleshooting**

| Problem | Action |
|---|---|
| Job hangs or is interrupted | `expdp ... attach=JOB_NAME`, then `STATUS`, `CONTINUE_CLIENT`, or `KILL_JOB`; jobs are restartable |
| `ORA-39002` / `ORA-39070` | Directory missing or not writable by the database OS user |
| `ORA-01555` during export | Undo too small for a consistent export of that duration |
| `ORA-39083` / `ORA-01917` on import | Users, roles or tablespaces missing on the target: create them or remap |
| Orphaned master tables | `SELECT * FROM dba_datapump_jobs;` and drop leftover `SYS_EXPORT_%` tables of stopped jobs |
| Sensitive data leaving production | Use `REMAP_DATA` or mask after import; encrypt dump files |
