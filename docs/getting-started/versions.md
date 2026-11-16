---
tags: [versions, licensing]
---

# Versions, editions and licensing

Whether a feature exists for you depends on three independent things: the
**release**, the **edition/deployment**, and the **options and packs** you are
licensed for. Check all three before you design around a feature.

## Releases

| Release | Type | Notes |
|---|---|---|
| **19c** | Long-term support | Final release of the 12.2 family. Still the most widely deployed on-premises release. Last release that supports the non-CDB architecture. |
| **21c** | Innovation | Short support window, no extended support. Multitenant only. Many of its features were the preview of 23ai. Not a target for new production systems. |
| **23ai** | Long-term support | Announced as 23c, renamed 23ai in 2024. Over 300 features: AI Vector Search, JSON Relational Duality, SQL property graphs, BOOLEAN, domains, and more. |
| **26ai** | Long-term support | Oracle AI Database 26ai replaced 23ai in October 2025. It is delivered as a release update of the same code line (23.26.x), so moving from 23ai is a patch, not an upgrade. On-premises availability started with the January 2026 release update on Linux x86-64. |

!!! warning "Dates move"
    Support end dates and platform availability change. The authoritative
    source is My Oracle Support note **742060.1** (Release Schedule of Current
    Database Releases). Do not plan a roadmap from a table in any playbook,
    including this one.

Upgrade paths: you can upgrade directly to 23ai/26ai from **19c and 21c** only.
Older releases must reach 19c first. Because 23ai+ supports only the multitenant
architecture, a 19c non-CDB must be converted to a PDB as part of the move
(chapter [3.3](../database-administration/01-administration.md)).

## Version numbers and release updates

A version such as `19.25.0` is *release.RU.revision*. Release Updates (RUs) ship
quarterly (January, April, July, October) and contain security and functional
fixes. Monthly Recommended Patches (MRPs) sit on top of an RU. From 26ai the RU
number carries the year: `23.26.1` is the first quarterly update of 2026.

```sql
SELECT banner_full FROM v$version;
SELECT version_full FROM v$instance;
```

## What arrived when (the items this playbook uses most)

| Feature | First available | Chapter |
|---|---|---|
| Identity columns, `FETCH FIRST`, `LATERAL`, multitenant | 12.1 | 1.7, 2.6 |
| `LISTAGG ... ON OVERFLOW`, long identifiers (128 bytes) | 12.2 | 2.4 |
| Private temporary tables, polymorphic table functions | 18c | 2.14 |
| `LISTAGG(DISTINCT)`, `ANY_VALUE`, automatic indexing (Exadata/cloud only), hybrid partitioned tables | 19c | 2.4, 2.12 |
| Native `JSON` data type, SQL macros, blockchain tables | 21c (some backported to 19c RUs) | 2.6 |
| `BOOLEAN` in SQL, `IF [NOT] EXISTS`, `SELECT` without `FROM`, `GROUP BY` alias, table value constructor, `UPDATE ... FROM` joins, domains, annotations, schema-level privileges, `DB_DEVELOPER_ROLE`, SQL Firewall, lock-free reservations | 23ai | 1.7, 2.6, 3.5 |
| `VECTOR` type and AI Vector Search, JSON Relational Duality, SQL property graphs (`GRAPH_TABLE`), JavaScript stored procedures (MLE), True Cache | 23ai | 4.7 |
| SQL assertions (`CREATE ASSERTION`), `QUALIFY`, later 23.26.x additions | 26ai release updates | 1.9, 2.5, 4.7 |

Rows in the last line come from Oracle's 26ai feature announcements. Confirm
each one in the *New Features Guide* for the exact release update you run,
because 26ai features arrive RU by RU.

## Removed or changed: things that break old habits

| Item | Status | Use instead |
|---|---|---|
| Non-CDB architecture | Deprecated 12.1.0.2, **desupported from 21c** | A CDB with PDBs |
| Traditional auditing (`AUDIT_TRAIL`, `AUDIT` statements) | **Desupported in 23ai** | Unified Auditing |
| Rule-based optimizer (`/*+ RULE */`) | Unsupported for many releases | Cost-based optimizer with good statistics |
| Original `exp` / `imp` | `exp` desupported since 11g for general use | Data Pump `expdp` / `impdp` |
| `DBMS_JOB` | Superseded; jobs are converted to Scheduler jobs on upgrade to 19c | `DBMS_SCHEDULER` |
| Oracle Streams, Advanced Replication | Desupported (19c / 12.2) | GoldenGate |
| `LONG` / `LONG RAW` | Supported only for backward compatibility | `CLOB` / `BLOB` |
| Native network encryption only | Still works; TLS is the recommended direction (TLS 1.3 from 23ai) | TLS |
| 32K `VARCHAR2` requires `MAX_STRING_SIZE=EXTENDED` | Not the default before 23ai | Check the parameter before using `VARCHAR2(32767)` |

## Editions and deployments

| Edition / deployment | What to remember |
|---|---|
| **Free** (formerly XE) | Resource caps; for learning and small apps; no support contract |
| **Standard Edition 2 (SE2)** | Socket-limited. **No** Partitioning, Data Guard, parallel query, Diagnostics/Tuning Pack, online index rebuild, Flashback Database, bitmap indexes. RAC is not available in SE2 from 19c (SE High Availability replaces it). |
| **Enterprise Edition (EE)** | Everything is installable; many features are **extra-cost options** |
| **Exadata / Engineered Systems** | Adds Smart Scan, storage indexes, Hybrid Columnar Compression, and unlocks some features (for example automatic indexing) |
| **Autonomous Database** | Managed; most options included; no SYSDBA/OS access; some features behave differently |
| **Base Database Service / Exadata Database Service (OCI)** | Edition bundles decide which options are included |

## Options and management packs (Enterprise Edition)

Using these without a license is the most common audit finding.

| Option or pack | Examples of what triggers usage |
|---|---|
| **Diagnostics Pack** | AWR reports, ASH (`v$active_session_history`), ADDM |
| **Tuning Pack** (needs Diagnostics) | SQL Tuning Advisor, SQL profiles, Real-Time SQL Monitoring |
| **Partitioning** | Any partitioned table or index |
| **Advanced Compression** | `ROW STORE COMPRESS ADVANCED`, index advanced compression, Data Pump compression |
| **Advanced Security** | Transparent Data Encryption, Data Redaction |
| **Active Data Guard** | Opening a physical standby read-only while redo apply runs; Far Sync |
| **Real Application Clusters** | Running RAC on EE |
| **Database In-Memory** | `INMEMORY` column store (a small base-level allowance exists from 19.8/20c) |
| **Multitenant** | More than 3 user PDBs per CDB (19c and later allow up to 3 without the option) |
| **Database Vault, Label Security** | Realms, command rules, label policies |

`CONTROL_MANAGEMENT_PACK_ACCESS` controls pack access; `DBA_FEATURE_USAGE_STATISTICS`
shows what has been used. Licensing terms are contractual: confirm with the
*Database Licensing Information User Manual* and your Oracle agreement.

```sql
SELECT name, detected_usages, currently_used, last_usage_date
FROM   dba_feature_usage_statistics
WHERE  detected_usages > 0
ORDER  BY name;
```

## Related

- [3.3 Administration and multitenant](../database-administration/01-administration.md): patching and upgrades
- [4.7 Oracle AI Database 26ai](../oracle-26ai/01-oracle-26ai.md)
- [References](../references/index.md)
