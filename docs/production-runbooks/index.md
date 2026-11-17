---
tags: [runbooks, operations]
---

# Production runbooks

A runbook is a procedure someone can follow correctly at 03:00. Each one here
has the same sections: **objective, prerequisites and privileges, commands,
expected output, verification, rollback, troubleshooting, safety**.

!!! warning "Before you use these in production"
    The commands were written from Oracle's documented behavior and were **not
    executed** while building this playbook. Expected output is illustrative.
    Test every runbook in a lab, adapt names and paths, and have it reviewed
    under your own change process.

## Index

| # | Runbook | Page | Changes state? |
|---|---|---|---|
| 1 | Database startup and shutdown | [Instance, sessions, locks](01-instance-sessions-locks.md) | Yes |
| 2 | Session investigation | [Instance, sessions, locks](01-instance-sessions-locks.md) | No |
| 3 | Blocking session investigation | [Instance, sessions, locks](01-instance-sessions-locks.md) | Optional kill |
| 4 | Deadlock investigation | [Instance, sessions, locks](01-instance-sessions-locks.md) | No |
| 5 | Long-running SQL investigation | [Instance, sessions, locks](01-instance-sessions-locks.md) | Optional cancel |
| 6 | Tablespace monitoring | [Space, undo, redo, archive](02-space-undo-redo.md) | No |
| 7 | Datafile management | [Space, undo, redo, archive](02-space-undo-redo.md) | Yes |
| 8 | Undo monitoring | [Space, undo, redo, archive](02-space-undo-redo.md) | No |
| 9 | Redo monitoring | [Space, undo, redo, archive](02-space-undo-redo.md) | Optional |
| 10 | Archive log monitoring | [Space, undo, redo, archive](02-space-undo-redo.md) | Optional |
| 11 | SQL performance diagnosis | [SQL, objects, users, indexes](03-sql-objects-users.md) | No |
| 12 | Invalid object investigation | [SQL, objects, users, indexes](03-sql-objects-users.md) | Recompile |
| 13 | User and privilege management | [SQL, objects, users, indexes](03-sql-objects-users.md) | Yes |
| 14 | Index health investigation | [SQL, objects, users, indexes](03-sql-objects-users.md) | Optional rebuild |
| 15 | RMAN backup | [RMAN and Data Pump](04-rman-datapump.md) | Writes backups |
| 16 | Backup validation | [RMAN and Data Pump](04-rman-datapump.md) | No |
| 17 | RMAN recovery | [RMAN and Data Pump](04-rman-datapump.md) | **Destructive** |
| 18 | Data Pump export and import | [RMAN and Data Pump](04-rman-datapump.md) | Import changes data |
| 19 | PDB creation and management | [PDB, patching, upgrades](05-pdb-patching-upgrade.md) | Yes |
| 20 | Database patching | [PDB, patching, upgrades](05-pdb-patching-upgrade.md) | Yes |
| 21 | Database upgrades | [PDB, patching, upgrades](05-pdb-patching-upgrade.md) | Yes |
| 22 | Data Guard health checks | [Data Guard, RAC, capacity, alert log](06-dataguard-rac-capacity.md) | No |
| 23 | RAC health checks | [Data Guard, RAC, capacity, alert log](06-dataguard-rac-capacity.md) | No |
| 24 | Capacity reports | [Data Guard, RAC, capacity, alert log](06-dataguard-rac-capacity.md) | No |
| 25 | Alert-log analysis | [Data Guard, RAC, capacity, alert log](06-dataguard-rac-capacity.md) | No |

## Rules for every operational change

| Rule | Detail |
|---|---|
| Know where you are | Check the prompt: `SELECT name, database_role FROM v$database; SHOW CON_NAME` before every state-changing command |
| Record | Ticket number, who, when, exact commands, output |
| Two-person rule | A second engineer confirms destructive commands |
| Backups first | Confirm the last successful backup and, for risky changes, create a guaranteed restore point |
| Smallest tool | Cancel a statement before killing a session; recover a table before a database |
| Verify | Every runbook ends with a check that the objective was met |
| Clean up | Drop restore points, temporary objects and traces you created |

## Scripts

| Script | Used by |
|---|---|
| `sql/administration/sessions_locks.sql` | Runbooks 2, 3, 5 |
| `sql/administration/space_undo_redo.sql` | Runbooks 6, 8, 9, 10 |
| `sql/administration/objects_users.sql` | Runbooks 12, 13, 14 |
| `sql/performance/sql_diagnosis.sql` | Runbook 11 |
| `sql/backup-recovery/rman_backup.rman`, `rman_recovery.rman` | Runbooks 15 to 17 |
| `sql/administration/health_capacity.sql` | Runbooks 24, 25 and the daily health check |
