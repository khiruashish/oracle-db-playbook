---
tags: [standards, best-practices]
---

# Production standards

Seventeen areas, each with a short rationale and a DO / DON'T table. Treat them
as defaults: deviations are allowed with a written reason
([ADRs](../enterprise-architecture/02-strategy-governance.md)).

## 1. SQL coding standards

| DO | DON'T |
|---|---|
| Use bind variables for every value | Concatenate values into SQL text |
| List columns explicitly | `SELECT *` in application code or views |
| Use ANSI join syntax and qualify every column with an alias | Mix `(+)` joins and comma joins in new code |
| Write `NOT EXISTS` for anti-joins | `NOT IN` against nullable columns |
| Compare like with like; convert literals explicitly | Rely on implicit conversion or session NLS settings |
| Keep columns bare in predicates | Wrap indexed columns in functions |
| State `ORDER BY` whenever order matters, with a unique tie-breaker | Rely on "natural" order |
| Prefer one set-based statement | Loop row by row |
| Format consistently; keywords upper case, one clause per line | Leave commented-out SQL in production code |

## 2. Naming conventions

| DO | DON'T |
|---|---|
| snake_case, unquoted identifiers | Quoted mixed-case names |
| Plural table names, singular column names | Prefixes like `tbl_`, Hungarian notation |
| `pk_`, `fk_`, `uq_`, `ck_`, `ix_` with table and purpose | System-generated constraint names |
| The same column name for the same thing everywhere (`customer_id`) | `id`, `cust`, `customer_no` for one concept |
| Suffixes that carry meaning: `_id`, `_date`, `_at`, `_amount`, `_qty` | Reserved words and abbreviations nobody can expand |
| `l_`, `p_`, `c_`, `g_` prefixes in PL/SQL | Variables named like columns |

## 3. Schema design standards

| DO | DON'T |
|---|---|
| A primary key on every table | Heap tables with no key |
| Declare every foreign key, unique key, `NOT NULL` and check | "The application guarantees it" |
| Normalize to 3NF; denormalize with evidence and a guard | Denormalize by habit |
| Exact types: `NUMBER(p,s)` for money, `DATE`/`TIMESTAMP` for time | Dates and numbers in `VARCHAR2`; `FLOAT` for money |
| Size columns from the domain | `VARCHAR2(4000)` everywhere |
| Snapshot historical facts (price at order time) | Join history to current master data |
| Design retention and purge with the table | Decide lifecycle after the table is 2 TB |
| Comment tables and columns; classify sensitive columns | Undocumented flags and magic values |

## 4. Indexing standards

| DO | DON'T |
|---|---|
| Index every foreign key | Leave child tables to be locked on parent DML |
| Design composite indexes per query: equality, then range/sort | One single-column index per column |
| Justify each index with a query or constraint | Add an index for every slow report |
| Test with invisible indexes; create `ONLINE` | Create or drop indexes on hot tables in peak hours |
| Review usage and remove redundant indexes | Rebuild indexes on a schedule |
| B-tree for OLTP | Bitmap indexes on tables with concurrent DML |

## 5. Transaction standards

| DO | DON'T |
|---|---|
| One business action = one short transaction | Hold a transaction across user think-time or remote calls |
| Let the caller own commit; no commit in reusable procedures | Commit inside loops without a restart design |
| Use conditional single-statement updates for check-and-change | Read, decide in the application, then write unguarded |
| Acquire locks in a consistent order | Lock in arbitrary order |
| Handle `ORA-00060`, `ORA-08177`, lock timeouts with bounded retry | Swallow errors and continue |
| Make operations idempotent (unique request keys) | Assume a request is delivered exactly once |
| Keep the default `READ COMMITTED` unless you can explain why not | `SERIALIZABLE` without retry logic |

## 6. Security standards

| DO | DON'T |
|---|---|
| Separate schema owner, application account and personal accounts | Let the application connect as the owner |
| Grant through roles; `EXECUTE` on APIs before DML on tables | `GRANT DBA`, `ANY` privileges, grants to `PUBLIC` |
| Secrets in a vault, rotated | Passwords in code, scripts or tickets |
| TLS required; TDE on application tablespaces | "Requested" encryption; clear-text backups |
| Audit privileged and non-application access; ship the trail off-host | Audit everything and review nothing |
| Mask production data before it leaves production | Unmasked clones in test |
| Patch quarterly | Run years behind on security fixes |

## 7. Backup standards

| DO | DON'T |
|---|---|
| ARCHIVELOG mode; RMAN level 0 + incrementals + frequent log backups | Rely on exports or storage snapshots alone |
| 3 copies, 2 media, 1 off-site, 1 immutable | Keep backups on the database's own storage |
| Control file and SPFILE autobackup | Forget the keystore and password file |
| Encrypt backups; back up keys separately | Store keys with the backups |
| Monitor every job and alert on failure or absence | Assume the schedule ran |
| Define retention from legal and recovery needs | Delete archived logs with OS commands |

## 8. Recovery standards

| DO | DON'T |
|---|---|
| Publish RTO and RPO per system and per failure class | One vague "we have backups" |
| Restore-test quarterly; record measured times | Treat validation as proof of recoverability |
| Use the narrowest tool: flashback, table, PDB, then database | Start with a full database point-in-time recovery |
| Create a guaranteed restore point before risky changes and drop it after | Leave restore points behind |
| Take a new full backup after any `RESETLOGS` | Continue on old backups after an incomplete recovery |
| Keep recovery runbooks rehearsed by more than one person | Depend on one expert |

## 9. Deployment standards

| DO | DON'T |
|---|---|
| All changes as versioned migrations in Git, deployed by pipeline | Manual DDL in production |
| Backward-compatible changes: expand, migrate, contract | Changes that require app and database to switch at the same instant |
| Test on a production-sized copy for locks and duration | Discover a 3-hour table rewrite in production |
| Online DDL; `DDL_LOCK_TIMEOUT` | Blocking DDL in business hours |
| Check invalid objects and run smoke tests after every deploy | Declare success when the script ends |
| A stated rollback and point of no return | "We will fix forward" as the only plan, unexamined |

## 10. Monitoring standards

| DO | DON'T |
|---|---|
| Monitor user-facing symptoms: latency, errors, throughput per service | Alert only on CPU and memory thresholds |
| Monitor leading indicators: space trend, lag, backup age, pool pending | Wait for `ORA-01653` |
| Every alert has an owner and a runbook link | Alerts nobody can act on |
| Page only what needs action now | Wake people for information |
| Keep baselines of normal peak behavior | Diagnose with nothing to compare against |
| Instrument applications (module, action, client id) | Anonymous sessions all named `JDBC Thin Client` |

## 11. Performance standards

| DO | DON'T |
|---|---|
| Define objectives as percentiles per business transaction | Use averages |
| Measure before changing; change one thing; measure again | Tune by folklore and hit ratios |
| Fix causes: estimates, SQL, design | Hints, underscore parameters and global optimizer switches |
| Test with production-like volume, skew and concurrency | Test on 1,000 rows |
| Size pools from database cores | Hundreds of connections per service |
| Keep automatic statistics; use preferences for exceptions | Disable the statistics job |
| Review the top SQL regularly | Wait for incidents |

## 12. Data retention

| DO | DON'T |
|---|---|
| A retention period per data class, agreed with legal and business owners | Keep everything forever "to be safe" |
| Implement retention by partition lifecycle | Mass deletes |
| Apply retention to replicas, warehouses, backups, exports, logs | Purge the primary only |
| Keep evidence that purges ran | Assume |
| Support erasure or anonymization of personal data | Hard-wire personal data into keys and free text |

## 13. Archiving

| DO | DON'T |
|---|---|
| Tier by age: compress, read-only, cheaper storage, then archive | Leave ten years of history on the fastest storage |
| Archive in a format you can read later (Data Pump with DDL, open formats) and test retrieval | Archive to a format tied to a release you will retire |
| Keep archived data queryable where the business needs it (hybrid/external partitions) | Promise retrieval "on request" with no tested procedure |
| Record what was archived, where, and until when | Lose track of archives |

## 14. Audit policies

| DO | DON'T |
|---|---|
| Unified Auditing with a small set of meaningful policies | Traditional auditing (desupported in 23ai) |
| Always audit: privileged users, logon failures, privilege and user changes, DDL, audit configuration changes | Exclude administrators |
| Audit sensitive data access outside the application path | Audit every application statement |
| Send the trail to a system the DBAs cannot alter; review it | Keep audit data only inside the audited database |
| Purge by policy with `DBMS_AUDIT_MGMT` | Let `AUDSYS` fill `SYSAUX` |

## 15. Change management

| DO | DON'T |
|---|---|
| Classify changes: standard (pre-approved, automated), normal, emergency | One heavyweight process for everything |
| Peer review every change; second person for destructive commands | Solo changes in production |
| Record what, why, who, when, outcome | Tribal memory |
| Rehearse risky changes; state the rollback | Improvise |
| Freeze before peak business periods | Deploy the day before the big sale |
| Review emergency changes afterwards and back-port to Git | Leave production different from the repository |

## 16. Incident management

| DO | DON'T |
|---|---|
| One incident commander; separate roles for communication and investigation | Ten people typing in the same database |
| Restore service first; preserve evidence (AWR snapshot, ASH dump, traces) | Restart everything and lose the diagnostics |
| Keep a timeline of observations and actions | Reconstruct from memory |
| Make one change at a time | Several fixes at once |
| Blameless post-incident review with owned actions | Close the ticket when the graph recovers |
| Track recurring causes | Treat each incident as new |

## 17. Disaster recovery testing

| DO | DON'T |
|---|---|
| Switch over and run production from the DR site at least twice a year | A "test" that only checks the standby is applying |
| Test the whole stack: DNS, apps, batch, interfaces, monitoring, access | Test the database alone |
| Measure and report achieved RTO and RPO | Quote design targets |
| Test failback | Assume the way back works |
| Rotate who performs it; update runbooks from each test | Depend on the same two people |
| Include restore-from-backup and logical-error scenarios | Consider only site loss |

## Using these standards

1. Automate what can be checked (naming, constraints, foreign-key indexes, grants, drift) in the pipeline.
2. Put the rest into the [design review checklist](../enterprise-architecture/02-strategy-governance.md).
3. Record exceptions with an owner and an expiry.
4. Review the standards yearly against incidents: a standard that never prevented anything, or is always waived, should change.
