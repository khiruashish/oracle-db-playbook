---
tags: [labs]
---

# Hands-on labs

Fifteen labs, in study order. Each has the same parts: **objective,
prerequisites, setup, steps, expected results, validation, challenge, solution,
further exploration**.

| Stage | Labs | Needs |
|---|---|---|
| [Stage 1](01-stage-1.md) | 1.1 Explore the schema · 1.2 Query and filter · 1.3 Change data safely · 1.4 Build and constrain a table | FreshMart installed; schema-owner access |
| [Stage 2](02-stage-2.md) | 2.1 Reporting with analytic SQL · 2.2 A PL/SQL API · 2.3 Locks and deadlocks · 2.4 Indexes and plans · 2.5 Partitioning | Same; two sessions for 2.3; Partitioning option (Free/EE) for 2.5 |
| [Stages 3 to 5](03-stage-3-5.md) | 3.1 Instance tour · 3.2 Backup and recover · 3.3 Flashback · 3.4 Security · 3.5 Performance diagnosis · 4.1 Design review | SYSDBA on a lab database you may destroy |

## Rules of the lab

1. **Use a lab database.** Several labs drop objects, kill sessions or restore files.
2. Type the statements; do not paste whole labs.
3. Predict each result before running it.
4. Run `ROLLBACK` after labs that change sample data, or reinstall with
   `sql/grocery-application/install.sql` after `sql/schema/99_drop_all.sql`.
5. Expected results are derived from the sample data (and cross-checked where
   noted). Output of DBA commands is illustrative.

## Reset the sample data

```sql
@sql/schema/99_drop_all.sql
@sql/grocery-application/install.sql
```

!!! danger "Lab schema only"
    `99_drop_all.sql` drops all FreshMart tables with `PURGE`.
