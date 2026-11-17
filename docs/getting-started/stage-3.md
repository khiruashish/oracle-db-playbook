# Stage 3 · Senior DBA

**For:** senior developers, DBAs and performance engineers (roughly the 10-year level).
**Time:** about 10 weeks. **You need:** SYSDBA on a lab database you can destroy.

## What you will be able to do

- Describe what every major memory structure, process and file does, and what fails when it is lost.
- Create users, PDBs, tablespaces and scheduler jobs; patch and upgrade.
- Back up with RMAN and recover from the loss of any file, to any point in time.
- Secure a database: privileges, encryption, auditing.
- Diagnose a slow system from AWR, ASH and wait events, and stabilize plans.
- Explain how RAC and Data Guard protect availability and data.

## Reading order

1. [3.1 Oracle architecture](../oracle-architecture/01-architecture.md)
2. [3.2 Storage management](../storage-management/01-storage.md)
3. [3.3 Administration and multitenant](../database-administration/01-administration.md)
4. [3.4 Backup and recovery](../backup-recovery/01-backup-recovery.md)
5. [3.5 Security](../security/01-security.md)
6. [3.6 Optimizer, statistics, SPM](../performance-engineering/02-optimizer-statistics-spm.md)
7. [3.7 AWR, ASH and wait analysis](../performance-engineering/03-awr-ash-waits.md)
8. [3.8 RAC, Clusterware and ASM](../high-availability/01-rac-asm.md)
9. [3.9 Data Guard](../high-availability/02-data-guard.md)

Then work through every [runbook](../production-runbooks/index.md) and all twelve
[performance incidents](../performance-incidents/01-incidents.md).

## Exit test

- [ ] Trace one `UPDATE` from the client to the data file and name every structure it touches.
- [ ] Restore a dropped table three different ways and say which you would use in production.
- [ ] Perform a point-in-time recovery of a PDB in your lab.
- [ ] From an AWR report, state the top wait class and the SQL responsible.
- [ ] Explain the difference between switchover and failover and what each costs.
