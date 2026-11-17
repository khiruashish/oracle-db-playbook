---
tags: [stage-3, backup, recovery, rman, flashback]
---

# 3.4 Backup and recovery

!!! abstract "Chapter card"
    **Stage:** 3 · **Prerequisites:** 3.1 to 3.3 · **Time:** 8 hours · **Applies to:** 19c+

## At a glance

| Subtopic | In one line |
|---|---|
| RTO and RPO | How long to restore; how much data you may lose |
| Physical and logical backups | Blocks (RMAN) versus rows and DDL (Data Pump) |
| RMAN | Full, incremental (differential, cumulative), archived logs, control file, SPFILE |
| Recovery catalog and retention | Where backup metadata lives; what is obsolete |
| Recovery | Complete, point-in-time, tablespace, PDB, table, block |
| Flashback | Query, Table, Drop, Transaction, Database |
| Validation and testing | A backup you have not restored is a hope |

## 1. RTO and RPO

| Term | Question | Driven by |
|---|---|---|
| **RPO** (recovery point objective) | How much committed data may be lost? | How quickly redo leaves the primary site |
| **RTO** (recovery time objective) | How long may the service be down? | Restore speed, or the existence of a standby |

Backups alone give an RTO of hours for a large database and an RPO equal to
the age of the last archived log that reached safe storage. Lower numbers need
Data Guard ([3.9](../high-availability/02-data-guard.md)). **Backups and
standbys are not substitutes**: a standby faithfully replicates a mistaken
`DELETE`; a backup protects against it.

## 2. What can go wrong

| Failure | Example | Tool |
|---|---|---|
| Statement / user process | A constraint error; a killed client | Automatic rollback (PMON) |
| Instance | Power loss | Automatic instance recovery |
| Media | A lost or corrupt data file | RMAN restore and recover |
| Human error | Wrong `DELETE`, dropped table | Flashback, then point-in-time recovery |
| Site | Data center lost | Standby database, off-site backups |
| Malicious | Ransomware, insider | Immutable backups, separation of duties |

## 3. Physical versus logical

| | Physical (RMAN) | Logical (Data Pump) |
|---|---|---|
| Copies | Data blocks, redo, control file | Rows and object definitions |
| Recover to any point in time | Yes, with archived logs | No: only the moment of export |
| Speed for large databases | Fast | Slow |
| Granularity | Database, PDB, tablespace, file, block (table via auxiliary) | Schema, table, row subset |
| Cross-version / platform | Limited | Yes |
| Role | **The** backup | Migration, refresh, extra safety for a schema |

## 4. RMAN essentials

Prerequisite: **ARCHIVELOG** mode. Recommended configuration:

```text
RMAN> CONFIGURE RETENTION POLICY TO RECOVERY WINDOW OF 14 DAYS;
RMAN> CONFIGURE CONTROLFILE AUTOBACKUP ON;
RMAN> CONFIGURE DEVICE TYPE DISK PARALLELISM 4 BACKUP TYPE TO COMPRESSED BACKUPSET;
RMAN> CONFIGURE ARCHIVELOG DELETION POLICY TO BACKED UP 1 TIMES TO DISK;
RMAN> CONFIGURE BACKUP OPTIMIZATION ON;
```

| Backup type | Contains | Notes |
|---|---|---|
| **Full** / level 0 | All used blocks | Level 0 is a full backup that can be the base of incrementals |
| **Incremental level 1, differential** (default) | Blocks changed since the last level 1 **or** 0 | Smallest backups; restore applies several |
| **Incremental level 1, cumulative** | Blocks changed since the last level **0** | Larger backups; faster restore |
| **Archived log backup** | Redo history | Needed to roll forward |
| **Control file and SPFILE autobackup** | Database structure and parameters | Taken automatically after each backup and structural change |
| **Image copy** | Exact file copies | Can be switched to instantly |
| **Backup set** | RMAN format; skips unused blocks; compresses | Default |

```text
RMAN> BACKUP INCREMENTAL LEVEL 0 DATABASE PLUS ARCHIVELOG TAG 'WEEKLY_L0';
RMAN> BACKUP INCREMENTAL LEVEL 1 DATABASE PLUS ARCHIVELOG TAG 'DAILY_L1';
RMAN> BACKUP ARCHIVELOG ALL NOT BACKED UP 1 TIMES;
RMAN> BACKUP PLUGGABLE DATABASE freshmart;
```

**Block change tracking** (`ALTER DATABASE ENABLE BLOCK CHANGE TRACKING;`, EE)
records changed blocks so incrementals do not scan every file.

**Incrementally updated backups**: keep an image copy and roll yesterday's
incremental into it each night. You always have a recent full copy without ever
taking another full backup, and can `SWITCH DATABASE TO COPY` for a very fast
restore.

### Retention and housekeeping

```text
RMAN> REPORT NEED BACKUP;
RMAN> REPORT OBSOLETE;
RMAN> CROSSCHECK BACKUP;          -- reconcile catalog with what exists on media
RMAN> DELETE NOPROMPT OBSOLETE;   -- destructive: only per retention policy
RMAN> LIST BACKUP SUMMARY;
```

Retention is a **recovery window** (any point in the last N days) or
**redundancy** (N copies). Long-term copies use
`BACKUP ... KEEP UNTIL TIME 'SYSDATE + 2555'` (archival backups).

### Recovery catalog

RMAN metadata is always in the **control file** (limited history,
`CONTROL_FILE_RECORD_KEEP_TIME`). A **recovery catalog** is a schema in a
separate database that holds longer history for many databases, stored scripts
and Data Guard-aware metadata. Use one for any estate with more than a few
databases, and back the catalog database up too.

### The 3-2-1 rule and immutability

Three copies, two media types, one off-site; and at least one copy that
administrators of the database cannot alter or delete (object-storage
retention locks, Zero Data Loss Recovery Appliance, or equivalent). Encrypt
backups (`SET ENCRYPTION`, TDE keystore) and back up the **keystore**
separately: an encrypted backup without its key is noise.

## 5. Recovery scenarios

| Scenario | Approach |
|---|---|
| Lost non-system data file | `RESTORE DATAFILE n; RECOVER DATAFILE n;` then online. Database stays open |
| Lost SYSTEM / undo data file | Mount, restore, recover, open |
| Lost all control files | `RESTORE CONTROLFILE FROM AUTOBACKUP;` mount, recover, `OPEN RESETLOGS` |
| Lost a redo log member | Drop and re-add it; other member keeps the database running |
| Lost the *current* redo group (unmirrored) | Incomplete recovery to before the loss: **data loss** |
| Logical error at 10:14 | Flashback if possible; else point-in-time recovery of the smallest unit |
| Block corruption | `RECOVER CORRUPTION LIST;` (block media recovery, EE). With Active Data Guard blocks are repaired automatically from the standby |
| Whole server lost | Restore SPFILE and control file from autobackup, then restore and recover the database |

**Complete recovery** applies all redo: no data loss. **Incomplete
(point-in-time) recovery** stops earlier and requires `OPEN RESETLOGS`, which
starts a new **incarnation**.

```text
RMAN> RUN {
        SET UNTIL TIME "TO_DATE('2026-03-14 10:13:00', 'YYYY-MM-DD HH24:MI:SS')";
        RESTORE DATABASE;
        RECOVER DATABASE;
      }
RMAN> ALTER DATABASE OPEN RESETLOGS;
```

!!! danger "Database point-in-time recovery discards everything after the target time"
    All transactions after `UNTIL` are lost for the whole database. Prefer a
    narrower tool: flashback, **PDB PITR**
    (`RECOVER PLUGGABLE DATABASE ... UNTIL ...`), **tablespace PITR**, or
    **table recovery** (`RECOVER TABLE freshmart.orders UNTIL TIME ...
    AUXILIARY DESTINATION '/u01/aux' REMAP TABLE ...`, 12c+), which restores
    into a temporary auxiliary instance and imports just the table.

## 6. Flashback technologies

| Feature | Undoes | Uses | Requires |
|---|---|---|---|
| **Flashback Query** (`AS OF`) | Nothing: reads the past | Undo | Undo retention |
| **Flashback Versions / Transaction Query** | Shows row history and the undo SQL | Undo; supplemental logging for transaction details | |
| **Flashback Table** | A table to a past time | Undo | `ENABLE ROW MOVEMENT` |
| **Flashback Drop** | `DROP TABLE` | Recycle bin | Not `PURGE`d; space not reclaimed |
| **Flashback Data Archive** | Long-term row history | Dedicated archive tablespaces | Configured per table |
| **Flashback Database / PDB** | The whole database or PDB to a past SCN | Flashback logs in the FRA, or a guaranteed restore point | EE; ARCHIVELOG |

```sql
-- See the data as it was 15 minutes ago
SELECT * FROM products AS OF TIMESTAMP SYSTIMESTAMP - INTERVAL '15' MINUTE
WHERE  category_id = 4;

-- Bring back a dropped table
FLASHBACK TABLE reviews TO BEFORE DROP;

-- Rewind a table
ALTER TABLE products ENABLE ROW MOVEMENT;
FLASHBACK TABLE products TO TIMESTAMP SYSTIMESTAMP - INTERVAL '15' MINUTE;
```

**Guaranteed restore points** are the standard safety net for risky changes:

```sql
CREATE RESTORE POINT before_release_42 GUARANTEE FLASHBACK DATABASE;
-- deploy ... if it goes wrong:
-- SHUTDOWN IMMEDIATE; STARTUP MOUNT;
-- FLASHBACK DATABASE TO RESTORE POINT before_release_42;
-- ALTER DATABASE OPEN RESETLOGS;
DROP RESTORE POINT before_release_42;     -- always: it pins FRA space until dropped
```

A forgotten guaranteed restore point fills the FRA and hangs the database.

## 7. Data Pump

```bash
expdp system@//dbhost/FRESHMART schemas=FRESHMART directory=DP_DIR \
      dumpfile=fm_%U.dmp logfile=fm_exp.log parallel=4 \
      flashback_time=systimestamp compression=all

impdp system@//testhost/FMTEST schemas=FRESHMART directory=DP_DIR \
      dumpfile=fm_%U.dmp logfile=fm_imp.log parallel=4 \
      remap_schema=FRESHMART:FM_TEST remap_tablespace=FM_DATA:USERS \
      table_exists_action=replace
```

- `FLASHBACK_TIME` or `FLASHBACK_SCN` makes the export **consistent**. Without it, tables are exported at different moments.
- `COMPRESSION=ALL` needs the Advanced Compression option; `PARALLEL` needs EE.
- `table_exists_action=replace` drops existing tables: destructive on the target.
- Useful: `CONTENT=METADATA_ONLY`, `QUERY`, `EXCLUDE=STATISTICS`, `NETWORK_LINK` (no dump file), `SQLFILE` (generate DDL only), `REMAP_DATA` (mask during export).

## 8. Validation and recovery testing

```text
RMAN> BACKUP VALIDATE CHECK LOGICAL DATABASE;       -- reads the database, finds corruption
RMAN> RESTORE DATABASE VALIDATE;                    -- proves backups are readable
RMAN> RESTORE DATABASE PREVIEW SUMMARY;             -- which backups would be used
```

```sql
SELECT * FROM v$database_block_corruption;
```

Validation proves readability. Only a **restore test** proves recoverability
and measures RTO. Schedule a full restore to scratch hardware (or
`DUPLICATE ... BACKUP LOCATION`) at least quarterly, record the elapsed time,
and treat a failed test as a production incident.

## 9. A reference strategy

| Database tier | Backup | Extra |
|---|---|---|
| Small, non-critical | Weekly level 0, daily level 1, archive logs every few hours | Off-site copy |
| Business-critical OLTP | Weekly level 0 (or incrementally updated copy), daily level 1, archive logs every 15 to 30 minutes, block change tracking | Data Guard, guaranteed restore points for changes, immutable off-site copy |
| Very large | Incrementally updated image copies; read-only tablespaces backed up once; back up from the standby | Recovery Appliance or object storage with retention lock |

## 10. Common mistakes

- No ARCHIVELOG mode in production.
- Backups on the same storage as the database.
- Never testing a restore; discovering missing archived logs or keys on the day.
- Treating a standby, a snapshot or a Data Pump export as "the backup".
- Deleting archived logs with `rm` instead of RMAN.
- Leaving guaranteed restore points behind.

## FreshMart example

=== "Scenario"

    At 10:14 a developer runs, in production,
    `UPDATE products SET unit_price = 0;` and commits. All 12 products are
    free. Orders are being placed. It is 10:16.

=== "Response"

    ```sql
    -- 1. Stop the damage: take the catalog offline in the application (feature flag).

    -- 2. Confirm what the data looked like before
    SELECT product_id, unit_price
    FROM   products AS OF TIMESTAMP TO_TIMESTAMP('2026-03-14 10:13:00', 'YYYY-MM-DD HH24:MI:SS');

    -- 3. Repair only the damaged column, keeping all other changes since 10:13
    MERGE INTO products p
    USING (SELECT product_id, unit_price
           FROM   products AS OF TIMESTAMP TO_TIMESTAMP('2026-03-14 10:13:00', 'YYYY-MM-DD HH24:MI:SS')) old
    ON    (p.product_id = old.product_id)
    WHEN MATCHED THEN UPDATE SET p.unit_price = old.unit_price
         WHERE p.unit_price <> old.unit_price;
    COMMIT;

    -- 4. Find orders placed at the wrong price
    SELECT oi.order_id, oi.product_id
    FROM   order_items oi JOIN orders o ON o.order_id = oi.order_id
    WHERE  oi.unit_price = 0
    AND    o.created_at >= TO_TIMESTAMP('2026-03-14 10:14:00', 'YYYY-MM-DD HH24:MI:SS');
    ```

=== "Why not the alternatives"

    | Option | Verdict |
    |---|---|
    | `FLASHBACK TABLE products` | Works, but also reverts legitimate changes made after 10:13 and needs row movement |
    | Database PITR to 10:13 | Loses every order since 10:13 and takes the site down for the restore |
    | Restore from last night's export | Loses a day of price changes |
    | **Flashback Query + targeted `MERGE`** | Surgical, online, minutes |

    Illustrative timeline and timestamps.

=== "Takeaway"

    Choose the narrowest tool that fixes the problem. This worked only because
    undo retention covered the two minutes; had it been discovered a day later,
    the same repair would need **table recovery** from RMAN into an auxiliary
    instance. And the root cause is access: no person should hold `UPDATE` on
    production tables in an interactive session ([3.5](../security/01-security.md)).

## Check yourself

??? question "Interview questions"
    1. **(Intermediate)** RTO versus RPO?
    2. **(Intermediate)** Differential versus cumulative incremental backups?
    3. **(Senior)** How do you recover one table to yesterday without affecting the rest?
    4. **(Senior)** What is `OPEN RESETLOGS` and when is it required?
    5. **(Architect)** Design backup for a 40 TB database with a 1-hour RTO. *A 1-hour RTO cannot come from restore: use Data Guard for RTO/RPO, and backups (incrementally updated copies, taken from the standby, immutable off-site) for logical errors and compliance. State both objectives separately.*

??? example "Exercises"
    1. Take a level 0 backup of your lab database, remove a data file of a test tablespace, and restore and recover it online.
    2. Drop a table and recover it with Flashback Drop; drop it with `PURGE` and recover it with `RECOVER TABLE`.
    3. Create a guaranteed restore point, make changes, flash back the database, and drop the restore point.
    4. Export the FRESHMART schema consistently and import it as `FM_TEST`.

## Related

Next: [3.5 Security](../security/01-security.md).
Runbooks: [RMAN and Data Pump](../production-runbooks/04-rman-datapump.md).
