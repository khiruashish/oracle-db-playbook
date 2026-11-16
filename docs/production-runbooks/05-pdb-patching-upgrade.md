---
tags: [runbooks, multitenant, patching, upgrade]
---

# Runbooks: PDB management, patching, upgrades

## 19. PDB creation and management

| | |
|---|---|
| **Objective** | Create, clone, open, close, unplug and drop pluggable databases |
| **Prerequisites** | CDB in ARCHIVELOG with local undo; space; OMF or file name conversion set; licence position checked (more than 3 user PDBs needs the Multitenant option) |
| **Privileges** | `CREATE PLUGGABLE DATABASE` as a common user in the root |

```sql
-- From the seed
CREATE PLUGGABLE DATABASE fm_test ADMIN USER fm_admin IDENTIFIED BY "&password";
ALTER PLUGGABLE DATABASE fm_test OPEN;
ALTER PLUGGABLE DATABASE fm_test SAVE STATE;

-- Hot clone (source stays open)
CREATE PLUGGABLE DATABASE fm_copy FROM freshmart;

-- Open and close
ALTER PLUGGABLE DATABASE fm_test CLOSE IMMEDIATE;
ALTER PLUGGABLE DATABASE fm_test OPEN READ ONLY;

-- Limits
ALTER SESSION SET CONTAINER = fm_test;
ALTER SYSTEM SET sga_target = 4G SCOPE = BOTH;
ALTER SYSTEM SET max_iops = 2000 SCOPE = BOTH;

-- Unplug and plug elsewhere
ALTER PLUGGABLE DATABASE fm_test CLOSE IMMEDIATE;
ALTER PLUGGABLE DATABASE fm_test UNPLUG INTO '/u01/stage/fm_test.pdb';   -- archive with data files
```

**Expected:** `Pluggable database created.` / `altered.`

**Verification**

```sql
SELECT con_id, name, open_mode, restricted FROM v$pdbs;
SELECT name, cause, type, message, status FROM pdb_plug_in_violations
WHERE  status <> 'RESOLVED' ORDER BY time;
```

A PDB that opens `RESTRICTED` has plug-in violations (patch level, options,
character set): resolve them (often by running `datapatch`). Confirm the
service is registered (`lsnrctl services`), add the PDB to backups, and with
Data Guard confirm the standby created it (clones from a remote source need
extra steps on the standby).

**Rollback**

!!! danger "Destructive"
    ```sql
    ALTER PLUGGABLE DATABASE fm_test CLOSE IMMEDIATE;
    DROP PLUGGABLE DATABASE fm_test INCLUDING DATAFILES;
    ```
    Removes the PDB and its files. There is no recycle bin. Confirm the name
    twice, confirm a backup or unplugged copy exists, and require approval.

**Troubleshooting:** `ORA-65016` (set `PDB_FILE_NAME_CONVERT` or OMF);
`ORA-65035`/`ORA-17628` on remote clone (source not in ARCHIVELOG/local undo,
or link privileges); TDE-encrypted sources need keys exported and imported
(`ADMINISTER KEY MANAGEMENT EXPORT/IMPORT KEYS`).

---

## 20. Database patching (Release Update)

| | |
|---|---|
| **Objective** | Apply a quarterly Release Update with minimal downtime and a fast way back |
| **Prerequisites** | RU and latest OPatch downloaded and checksummed; README read; conflicts checked; tested in non-production; backup verified; change approved |
| **Privileges** | OS software owner (and root for Grid Infrastructure); `SYSDBA` |

**Out-of-place method (recommended)**

```bash
# 1. Prepare a new home containing the RU (gold image, or clone + opatch apply)
export NEW_HOME=/u01/app/oracle/product/23.26.2/dbhome_1
$NEW_HOME/OPatch/opatch lspatches          # confirm contents

# 2. Guaranteed restore point (single instance without standby-first)
sqlplus / as sysdba <<'SQL'
CREATE RESTORE POINT before_ru GUARANTEE FLASHBACK DATABASE;
SQL

# 3. Stop the database from the old home, start it from the new one
srvctl stop database -db FMPRD
srvctl modify database -db FMPRD -oraclehome $NEW_HOME
srvctl start database -db FMPRD

# 4. Apply the SQL changes to the CDB and all open PDBs
$NEW_HOME/OPatch/datapatch -verbose
```

With Data Guard: patch the **standby** home first, switch over, patch the old
primary, then run `datapatch` once on the primary (*standby-first*). With RAC:
roll node by node, draining services. Version numbers above are illustrative.

**Verification**

```sql
SELECT patch_id, action, status, description, action_time
FROM   dba_registry_sqlpatch ORDER BY action_time DESC;
SELECT comp_id, version_full, status FROM dba_registry;
SELECT COUNT(*) FROM dba_objects WHERE status = 'INVALID';
```

All patches `SUCCESS`, components `VALID`, PDBs open unrestricted, invalid
count no higher than before, application smoke test passed. Then drop the
restore point.

**Rollback:** switch the database back to the old home and run
`datapatch -rollback` logic from that home as the RU README describes (or
flash back to the restore point if SQL changes cannot be rolled back and no
business data has been written). Keep the old home until the next cycle.

**Troubleshooting:** `datapatch` errors are logged under
`$ORACLE_BASE/cfgtoollogs/sqlpatch`; PDBs closed during `datapatch` remain
unpatched and open restricted later (open them and rerun); OPatch version too
old; inventory lock or permission problems.

!!! danger "Safety"
    Never patch a home in place while the database runs from it. Do not
    leave the guaranteed restore point behind. Do not skip `datapatch`:
    binaries and dictionary would disagree.

---

## 21. Database upgrades

| | |
|---|---|
| **Objective** | Upgrade to a new release (for example 19c to 26ai) with a tested fallback |
| **Prerequisites** | Direct upgrade path confirmed (19c or 21c to 23ai/26ai); application certified; rehearsed on a full copy; performance baseline and SQL plan baselines captured; `COMPATIBLE` plan decided; downtime or rolling method agreed |
| **Privileges** | OS software owner; `SYSDBA` |

```bash
# autoupgrade.cfg (illustrative)
# global.autoupg_log_dir=/u01/autoupgrade
# upg1.sid=FMPRD
# upg1.source_home=/u01/app/oracle/product/19.0.0/dbhome_1
# upg1.target_home=/u01/app/oracle/product/23.26.0/dbhome_1
# upg1.target_cdb=CDB26          # non-CDB source is converted and plugged in
# upg1.restoration=yes           # guaranteed restore point for fallback

java -jar autoupgrade.jar -config autoupgrade.cfg -mode analyze    # report only
java -jar autoupgrade.jar -config autoupgrade.cfg -mode fixups     # apply pre-upgrade fixes
java -jar autoupgrade.jar -config autoupgrade.cfg -mode deploy     # upgrade
```

Always download the latest `autoupgrade.jar`; check option names in its
documentation for your version.

**Phases**

| Phase | Checks |
|---|---|
| Analyze | Read the HTML report: required and recommended actions, time zone file, invalid objects, deprecated parameters |
| Before | Gather dictionary statistics; purge the recycle bin; back up; capture SQL tuning set / baselines |
| Deploy | AutoUpgrade creates a restore point, upgrades, recompiles, runs post-fixups |
| After | Verify; gather dictionary and fixed-object statistics; test performance; keep `COMPATIBLE` unchanged for an agreed soak period |
| Finalize | Drop the restore point; raise `COMPATIBLE` (irreversible); remove the old home later |

**Verification**

```sql
SELECT version_full FROM v$instance;
SELECT comp_id, version_full, status FROM dba_registry;
SELECT COUNT(*) FROM dba_objects WHERE status = 'INVALID';
SELECT name, open_mode, restricted FROM v$pdbs;
```

Plus application regression and performance tests against the baseline.

**Rollback**

| When | Method |
|---|---|
| Before users return | `autoupgrade -restore`, or `FLASHBACK DATABASE` to the restore point from the old home |
| After users have written data | Downgrade (only while `COMPATIBLE` is unchanged, and not for a non-CDB converted to a PDB), or a GoldenGate reverse-replication fallback prepared in advance |

!!! danger "Points of no return"
    Raising `COMPATIBLE` removes the downgrade and flashback path. Converting
    a non-CDB to a PDB cannot be reversed except by restore. Decide who
    declares the upgrade final, and when.

**Lower-downtime alternatives:** transient logical standby rolling upgrade
(`DBMS_ROLLING`), GoldenGate ([4.2](../high-availability/04-goldengate-replication.md)),
or refreshable-clone PDB upgrade into a new CDB.
