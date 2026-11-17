---
tags: [runbooks, storage]
---

# Runbooks: space, undo, redo, archive

## 6. Tablespace monitoring

| | |
|---|---|
| **Objective** | Know how full each tablespace is against its **maximum** size, and who uses temp |
| **Privileges** | `SELECT` on `DBA_TABLESPACE_USAGE_METRICS`, `DBA_DATA_FILES`, `V$TEMPSEG_USAGE` |

```sql
--8<-- "sql/administration/space_undo_redo.sql:tablespace"
```

**Expected output (illustrative):**

| TABLESPACE_NAME | USED_GB | MAX_GB | PCT_OF_MAX |
|---|---:|---:|---:|
| FM_DATA | 171.4 | 200.0 | 85.7 |
| SYSAUX | 9.8 | 32.0 | 30.6 |
| UNDOTBS1 | 6.1 | 32.0 | 19.1 |

**Thresholds:** warn at 80% of max, act at 90%, and alert on *days until full*
from the growth trend rather than on the percentage alone.

**Troubleshooting**

| Symptom | Cause / action |
|---|---|
| `ORA-01653` / `ORA-01654` unable to extend | Tablespace at max, or the disk/ASM group is full: runbook 7 |
| `ORA-01652` unable to extend temp segment | A statement needs more temp than exists: find it in the temp query; usually a bad plan |
| `SYSAUX` growing | AWR retention, optimizer statistics history, audit trail: check `V$SYSAUX_OCCUPANTS` |
| Space "used" by dropped objects | `SELECT * FROM dba_recyclebin`; purge with approval |

**Safety:** monitoring only.

---

## 7. Datafile management

| | |
|---|---|
| **Objective** | Add or resize storage safely |
| **Prerequisites** | Free space confirmed on the filesystem or ASM disk group (`USABLE_FILE_MB`); standby storage checked too |
| **Privileges** | `ALTER TABLESPACE`, `ALTER DATABASE` |

```sql
-- Extend an existing file's limit
ALTER DATABASE DATAFILE '/u02/oradata/FMPRD/fm_data01.dbf' AUTOEXTEND ON NEXT 1G MAXSIZE 31G;

-- Resize now
ALTER DATABASE DATAFILE '/u02/oradata/FMPRD/fm_data01.dbf' RESIZE 20G;

-- Add a file (OMF / ASM: no name needed)
ALTER TABLESPACE fm_data ADD DATAFILE SIZE 10G AUTOEXTEND ON NEXT 1G MAXSIZE 31G;

-- Bigfile tablespace
ALTER TABLESPACE fm_big RESIZE 500G;

-- Temp
ALTER TABLESPACE temp ADD TEMPFILE SIZE 10G AUTOEXTEND ON NEXT 1G MAXSIZE 31G;
```

**Verification:** rerun runbook 6; confirm the new file on the standby
(`STANDBY_FILE_MANAGEMENT = AUTO` creates it there).

**Rollback**

!!! danger "Destructive"
    ```sql
    ALTER TABLESPACE fm_data DROP DATAFILE '/u02/oradata/FMPRD/fm_data05.dbf';
    ```
    Works only if the file is **empty** and is not the first file of the
    tablespace. Never delete a data file at the operating system level. A
    resize down fails with `ORA-03297` if data exists beyond the new size.

**Troubleshooting:** `ORA-01119`/`ORA-27040` (path or permission);
`ORA-01144`/`ORA-01237` (file size beyond the block-size limit: add a file or
use a bigfile tablespace); new file missing on the standby (set
`STANDBY_FILE_MANAGEMENT` and check the alert log there).

---

## 8. Undo monitoring

| | |
|---|---|
| **Objective** | Detect undo pressure before `ORA-01555` or `ORA-30036` reach users |
| **Privileges** | `DBA_UNDO_EXTENTS`, `V$UNDOSTAT`, `V$TRANSACTION` |

```sql
--8<-- "sql/administration/space_undo_redo.sql:undo"
```

**Reading it**

| Signal | Meaning |
|---|---|
| Mostly `ACTIVE` extents, one session with huge `USED_UBLK` | One large transaction: find its owner |
| `ORA_1555 > 0` | Queries lost their read-consistent view |
| `LONGEST_QUERY_S` far above `UNDO_RETENTION` | Retention too low for the workload, or a query that should be tuned |
| `NO_SPACE > 0` | Undo tablespace too small |

**Actions, in order:** tune or reschedule the long query; fix code that fetches
across commits; size undo as peak undo rate × longest legitimate query;
raise `UNDO_RETENTION`; add space (runbook 7).

**Rollback:** parameter changes are reversible with `ALTER SYSTEM SET`.

!!! danger "Safety"
    Do not kill a session with a very large transaction to "free undo": its
    rollback will use the same undo and take a long time. Do not switch undo
    tablespaces during an incident without a plan.

---

## 9. Redo monitoring

| | |
|---|---|
| **Objective** | Confirm redo logs are sized and healthy; find heavy redo generators |
| **Privileges** | `V$LOG`, `V$LOG_HISTORY`, `V$SESSTAT`; `ALTER DATABASE` for changes |

```sql
--8<-- "sql/administration/space_undo_redo.sql:redo"
```

**Expected:** every group has two members; exactly one `CURRENT`; others
`INACTIVE` or `ACTIVE`; a handful of switches per hour at peak.

**Fix undersized logs** (many switches per hour, `checkpoint not complete`):

```sql
ALTER DATABASE ADD LOGFILE THREAD 1 GROUP 11 SIZE 4G;
ALTER DATABASE ADD LOGFILE THREAD 1 GROUP 12 SIZE 4G;
ALTER DATABASE ADD LOGFILE THREAD 1 GROUP 13 SIZE 4G;
ALTER SYSTEM SWITCH LOGFILE;            -- repeat until old groups are INACTIVE
ALTER SYSTEM CHECKPOINT;
ALTER DATABASE DROP LOGFILE GROUP 1;    -- only when INACTIVE and archived
```

With Data Guard, resize the **standby redo logs** to match (one more group than
online groups per thread) on both primary and standby.

**Verification:** `V$LOG` shows the new sizes; switch rate drops.

!!! danger "Safety"
    Never drop a group whose status is `CURRENT` or `ACTIVE`, or that is not
    yet archived. Oracle refuses in most cases; do not look for ways around it.
    Losing the current redo group means losing committed data.

---

## 10. Archive log monitoring

| | |
|---|---|
| **Objective** | Keep the archive destination from filling (which hangs the database) |
| **Privileges** | `V$RECOVERY_FILE_DEST`, `V$RECOVERY_AREA_USAGE`, `V$ARCHIVED_LOG`; RMAN |

```sql
--8<-- "sql/administration/space_undo_redo.sql:archive"
```

**Thresholds:** alert when unreclaimable use exceeds 80% of the limit.

**If the destination is full** (`ORA-00257: archiver error`, `ORA-19809`,
sessions hanging on `log file switch (archiving needed)`):

1. Confirm: alert log and the first query above.
2. Free space the supported way:

```text
RMAN> BACKUP ARCHIVELOG ALL NOT BACKED UP 1 TIMES;
RMAN> DELETE NOPROMPT ARCHIVELOG ALL BACKED UP 1 TIMES TO DISK;
```

3. Or raise the limit if the disk has room: `ALTER SYSTEM SET db_recovery_file_dest_size = 400G;`
4. Look for the cause: a forgotten **guaranteed restore point** (`V$RESTORE_POINT`), a standby that stopped receiving redo (logs are kept until shipped), a failed backup job, or an unusual redo spike.

**Verification:** the hang clears within seconds; `V$ARCHIVE_DEST_STATUS` shows
`VALID`.

!!! danger "Safety"
    Never delete archived logs with `rm`: RMAN and the standby lose track of
    them. Never delete logs a standby has not received or that are not backed
    up. If you must remove files manually in an emergency, follow with
    `RMAN> CROSSCHECK ARCHIVELOG ALL;` and take a new backup immediately.
