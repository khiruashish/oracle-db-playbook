---
tags: [references]
---

# References

Official Oracle documentation is the authority for syntax, restrictions and
release availability. This playbook explains and connects; when the two
disagree, the documentation for **your release update** wins.

!!! note "Link policy"
    Links point to documentation library landing pages, which are stable.
    Deep links to individual pages change between releases, so navigate from
    the library to the book named in each row.

## Documentation libraries

| Release | Library |
|---|---|
| Oracle AI Database 26ai | <https://docs.oracle.com/en/database/oracle/oracle-database/26/> |
| Oracle Database 23ai | <https://docs.oracle.com/en/database/oracle/oracle-database/23/> |
| Oracle Database 21c | <https://docs.oracle.com/en/database/oracle/oracle-database/21/> |
| Oracle Database 19c | <https://docs.oracle.com/en/database/oracle/oracle-database/19/> |
| All database documentation | <https://docs.oracle.com/en/database/> |

## Books in the library, by chapter

| Playbook chapters | Oracle book |
|---|---|
| 1.1, 3.1, 3.2 | *Database Concepts* |
| 1.5 to 2.6 | *SQL Language Reference* |
| 2.4, 2.5, 4.6 | *Data Warehousing Guide* |
| 2.6 | *JSON Developer's Guide* |
| 2.7 to 2.10 | *PL/SQL Language Reference*; *PL/SQL Packages and Types Reference* |
| 2.11, 2.14 | *Database Development Guide* |
| 2.12, 3.3 | *Database Administrator's Guide* |
| 2.13 | *VLDB and Partitioning Guide* |
| 2.15, 3.6 | *SQL Tuning Guide* |
| 3.7 | *Database Performance Tuning Guide* |
| 3.3 | *Multitenant Administrator's Guide*; *Database Upgrade Guide*; *Database Utilities* |
| 3.4 | *Backup and Recovery User's Guide*; *Backup and Recovery Reference* |
| 3.5 | *Database Security Guide*; *Advanced Security Guide*; *Database Vault Administrator's Guide* |
| 3.8 | *Real Application Clusters Administration and Deployment Guide*; *Clusterware Administration and Deployment Guide*; *Automatic Storage Management Administrator's Guide* |
| 3.9 | *Data Guard Concepts and Administration*; *Data Guard Broker* |
| 4.1 | *High Availability Overview and Best Practices* (MAA) |
| 4.3 | *Globally Distributed Database Guide* (formerly *Using Oracle Sharding*) |
| 4.4 | *Database In-Memory Guide*; *Database Administrator's Guide* (Resource Manager) |
| 4.7 | *AI Vector Search User's Guide*; *JSON-Relational Duality Developer's Guide*; *Graph Developer's Guide for Property Graph*; *JavaScript Developer's Guide* |
| 4.8 | *JDBC Developer's Guide*; *Universal Connection Pool Developer's Guide* |
| Versions and licensing | *Database New Features*; *Database Licensing Information User Manual*; *Database Reference* |

## Other Oracle resources

| Resource | Link |
|---|---|
| GoldenGate documentation | <https://docs.oracle.com/en/middleware/goldengate/> |
| Oracle Cloud Infrastructure database services | <https://docs.oracle.com/en-us/iaas/Content/Database/home.htm> |
| Autonomous Database | <https://docs.oracle.com/en/cloud/paas/autonomous-database/> |
| Oracle LiveLabs (free hands-on workshops, including RAC and Data Guard) | <https://livelabs.oracle.com/> |
| Oracle LiveSQL (browser SQL) | <https://livesql.oracle.com/> |
| Oracle Container Registry (database images) | <https://container-registry.oracle.com/> |
| Maximum Availability Architecture | <https://www.oracle.com/database/technologies/high-availability/maa.html> |
| AutoUpgrade | <https://docs.oracle.com/en/database/oracle/oracle-database/26/upgrd/> |
| My Oracle Support (release schedule note 742060.1; requires a support account) | <https://support.oracle.com/> |
| Oracle Database blogs (feature announcements) | <https://blogs.oracle.com/database/> |

## Third-party tools referenced

| Tool | Link |
|---|---|
| Material for MkDocs | <https://squidfunk.github.io/mkdocs-material/> |
| utPLSQL | <https://www.utplsql.org/> |
| Flyway | <https://documentation.red-gate.com/flyway> |
| Liquibase | <https://docs.liquibase.com/> |
| Spring Boot reference | <https://docs.spring.io/spring-boot/> |
| HikariCP | <https://github.com/brettwooldridge/HikariCP> |
| Testcontainers Oracle module | <https://java.testcontainers.org/modules/databases/oraclefree/> |
| Terraform OCI provider | <https://registry.terraform.io/providers/oracle/oci/latest/docs> |

## Sources consulted while writing

Facts about the 26ai release (naming, on-premises availability, and features
that arrive in specific release updates) were checked against Oracle's public
announcements at the time of writing:

- [Oracle announces Oracle AI Database 26ai](https://blogs.oracle.com/database/oracle-announces-oracle-ai-database-26ai)
- [GA of Oracle AI Database 26ai for Linux x86-64 on-premises platforms](https://blogs.oracle.com/database/ga-of-oracle-ai-database-26ai-for-linux-x86-64-on-premises-platforms)
- [Oracle AI Database 26ai New Features](https://docs.oracle.com/en/database/oracle/oracle-database/26/nfcoa/all-nfg.html)
- [Material for MkDocs: Insiders now free for everyone](https://squidfunk.github.io/mkdocs-material/blog/2025/11/11/insiders-now-free-for-everyone/) (maintenance mode; successor project Zensical)

The mapping of individual SQL features (assertions, `QUALIFY`, filtered
aggregates and others) to exact 23.26.x release updates comes from Oracle blog
posts rather than the reference manuals and is marked in the chapters as
needing confirmation for your release update.

## Verification status of this playbook

| Content | Status |
|---|---|
| Query results marked *verified* | Reproduced by `tests/verify_outputs.py` on a SQLite copy of the sample data |
| Other query results | Derived by hand from the sample data |
| Oracle SQL, PL/SQL, RMAN, shell and Java | Written to documented syntax; **not executed** |
| Execution plans, wait figures, timings, command output | Illustrative |
| Site build | `mkdocs build --strict` passes |
