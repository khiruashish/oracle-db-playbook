---
tags: [glossary]
---

# Glossary

Short definitions, with the chapter where each term is explained.

| Term | Definition | Chapter |
|---|---|---|
| **ACID** | Atomicity, consistency, isolation, durability: the guarantees of a transaction | [1.8](../sql-fundamentals/04-dml-and-transactions.md) |
| **Active Data Guard** | Licensed option: a physical standby open read-only while applying redo, plus related features | [3.9](../high-availability/02-data-guard.md) |
| **ADDM** | Automatic Database Diagnostic Monitor: automated analysis of an AWR period | [3.7](../performance-engineering/03-awr-ash-waits.md) |
| **ADR** | Automatic Diagnostic Repository: directory tree of alert log, traces and incidents | [3.3](../database-administration/01-administration.md) |
| **ADR (decision)** | Architecture decision record | [5.3](../enterprise-architecture/02-strategy-governance.md) |
| **Anti join** | Rows of A with no match in B (`NOT EXISTS`) | [2.1](../advanced-sql/01-joins.md) |
| **Archived redo log** | A copy of a filled online redo log, needed for media recovery | [3.2](../storage-management/01-storage.md) |
| **ASH** | Active Session History: per-second samples of active sessions | [3.7](../performance-engineering/03-awr-ash-waits.md) |
| **ASM** | Automatic Storage Management: Oracle's volume manager and file system | [3.8](../high-availability/01-rac-asm.md) |
| **ASSM** | Automatic Segment Space Management: bitmap tracking of free space in segments | [3.2](../storage-management/01-storage.md) |
| **AWR** | Automatic Workload Repository: periodic performance snapshots | [3.7](../performance-engineering/03-awr-ash-waits.md) |
| **Bind variable** | A placeholder in SQL whose value is supplied at execution | [2.15](../performance-engineering/01-execution-plans.md) |
| **Block** | Smallest unit of database storage and I/O (usually 8 KB) | [3.2](../storage-management/01-storage.md) |
| **Buffer cache** | SGA area holding copies of data blocks | [3.1](../oracle-architecture/01-architecture.md) |
| **Cache Fusion** | Block transfer between RAC instances over the interconnect | [3.8](../high-availability/01-rac-asm.md) |
| **Cardinality** | Number of rows; in plans, the optimizer's row estimate | [2.12](../indexing/01-indexing.md) |
| **CBO** | Cost-based optimizer | [3.6](../performance-engineering/02-optimizer-statistics-spm.md) |
| **CDB / PDB** | Container database and the pluggable databases inside it | [3.3](../database-administration/01-administration.md) |
| **CDC** | Change data capture | [4.5](../data-integration/01-data-integration.md) |
| **Checkpoint** | Point up to which changes are written to data files | [3.1](../oracle-architecture/01-architecture.md) |
| **Clustering factor** | How closely table row order follows an index's order | [2.12](../indexing/01-indexing.md) |
| **Context switch** | Hand-off between the SQL and PL/SQL engines | [2.7](../plsql/01-fundamentals.md) |
| **Control file** | File recording the physical structure and state of the database | [3.2](../storage-management/01-storage.md) |
| **CTE** | Common table expression: a named subquery in a `WITH` clause | [2.3](../advanced-sql/03-cte-hierarchical.md) |
| **Cursor** | Handle on the memory area where a SQL statement is processed | [2.8](../plsql/02-cursors-collections-bulk.md) |
| **Data Guard** | Standby databases kept in sync by shipping and applying redo | [3.9](../high-availability/02-data-guard.md) |
| **Data Pump** | Logical export and import utilities (`expdp`, `impdp`) | [3.4](../backup-recovery/01-backup-recovery.md) |
| **DB time** | Time foreground sessions spend on CPU or in non-idle waits | [3.7](../performance-engineering/03-awr-ash-waits.md) |
| **Deadlock** | Sessions waiting on each other in a cycle; Oracle fails one statement | [2.11](../transactions/01-transactions-concurrency.md) |
| **Direct-path insert** | Load that writes formatted blocks above the high-water mark | [4.5](../data-integration/01-data-integration.md) |
| **Duality view** | JSON Relational Duality view: updatable JSON documents over tables | [4.7](../oracle-26ai/01-oracle-26ai.md) |
| **EBR** | Edition-Based Redefinition: online application upgrades | [4.9](../database-devops/01-devops.md) |
| **Embedding** | A vector representing the meaning of text or other content | [4.7](../oracle-26ai/01-oracle-26ai.md) |
| **Extent** | Contiguous blocks allocated to a segment | [3.2](../storage-management/01-storage.md) |
| **FAN** | Fast Application Notification: events that tell pools about failures | [3.8](../high-availability/01-rac-asm.md) |
| **Far Sync** | Light instance that receives redo synchronously and forwards it | [3.9](../high-availability/02-data-guard.md) |
| **Flashback** | Family of features for viewing or rewinding past states | [3.4](../backup-recovery/01-backup-recovery.md) |
| **FRA** | Fast recovery area: managed storage for recovery files | [3.2](../storage-management/01-storage.md) |
| **FSFO** | Fast-Start Failover: automatic Data Guard failover by an observer | [3.9](../high-availability/02-data-guard.md) |
| **Functional dependency** | A → B: the same A always has the same B | [1.4](../data-modeling/02-normalization.md) |
| **GoldenGate** | Oracle's logical replication product | [4.2](../high-availability/04-goldengate-replication.md) |
| **Hard parse** | Full parse and optimization of a new statement | [2.15](../performance-engineering/01-execution-plans.md) |
| **Histogram** | Statistics describing a column's value distribution | [3.6](../performance-engineering/02-optimizer-statistics-spm.md) |
| **HNSW / IVF** | Vector index types: in-memory graph and neighbor partitions | [4.7](../oracle-26ai/01-oracle-26ai.md) |
| **HWM** | High-water mark: boundary of formatted blocks in a segment | [3.2](../storage-management/01-storage.md) |
| **Idempotent** | Safe to perform more than once | [4.3](../distributed-databases/01-distributed.md) |
| **Instance** | The memory and processes that operate a database | [3.1](../oracle-architecture/01-architecture.md) |
| **IOT** | Index-organized table | [2.12](../indexing/01-indexing.md) |
| **ITL** | Interested transaction list: lock slots in a block header | [2.11](../transactions/01-transactions-concurrency.md) |
| **Latch / mutex** | Short-duration protection of memory structures | [3.7](../performance-engineering/03-awr-ash-waits.md) |
| **LGWR** | Log writer process | [3.1](../oracle-architecture/01-architecture.md) |
| **Listener** | Process that accepts connection requests | [3.1](../oracle-architecture/01-architecture.md) |
| **MAA** | Maximum Availability Architecture: Oracle's HA reference tiers | [4.1](../high-availability/03-ha-dr-architecture.md) |
| **Materialized view** | Stored query result maintained by the database | [2.14](../database-objects/01-database-objects.md) |
| **MVCC** | Multiversion concurrency control: readers see a consistent snapshot | [2.11](../transactions/01-transactions-concurrency.md) |
| **Normalization** | Structuring tables so each fact is stored once | [1.4](../data-modeling/02-normalization.md) |
| **OLTP / OLAP** | Transaction processing / analytical processing | [1.1](../database-fundamentals/01-data-and-databases.md) |
| **Outbox** | Table of events written in the same transaction as the data | [4.3](../distributed-databases/01-distributed.md) |
| **Partition pruning** | Skipping partitions that cannot contain requested rows | [2.13](../partitioning/01-partitioning.md) |
| **PGA** | Program Global Area: private memory of a server process | [3.1](../oracle-architecture/01-architecture.md) |
| **Plan baseline** | Accepted execution plans for a statement (SQL Plan Management) | [3.6](../performance-engineering/02-optimizer-statistics-spm.md) |
| **RAC** | Real Application Clusters: several instances, one database | [3.8](../high-availability/01-rac-asm.md) |
| **Redo** | The log of all changes, used for recovery and replication | [3.1](../oracle-architecture/01-architecture.md) |
| **RMAN** | Recovery Manager: physical backup and recovery tool | [3.4](../backup-recovery/01-backup-recovery.md) |
| **Rowid** | Physical address of a row | [1.11](../sql-fundamentals/07-first-index.md) |
| **RPO / RTO** | Recovery point objective / recovery time objective | [3.4](../backup-recovery/01-backup-recovery.md) |
| **RU** | Release Update: quarterly patch bundle | [3.3](../database-administration/01-administration.md) |
| **Saga** | Sequence of local transactions with compensations | [4.3](../distributed-databases/01-distributed.md) |
| **SCD** | Slowly changing dimension | [4.6](../data-warehousing/01-data-warehousing.md) |
| **SCN** | System change number: Oracle's logical clock | [2.11](../transactions/01-transactions-concurrency.md) |
| **Segment** | The storage of one object or partition | [3.2](../storage-management/01-storage.md) |
| **Selectivity** | Fraction of rows a predicate returns | [2.12](../indexing/01-indexing.md) |
| **Semi join** | Rows of A with at least one match in B (`EXISTS`) | [2.1](../advanced-sql/01-joins.md) |
| **Service** | A named workload that clients connect to | [3.1](../oracle-architecture/01-architecture.md) |
| **SGA** | System Global Area: shared memory of an instance | [3.1](../oracle-architecture/01-architecture.md) |
| **Sharding** | Horizontal partitioning of data across databases | [4.3](../distributed-databases/01-distributed.md) |
| **Soft parse** | Reuse of an existing cursor | [2.15](../performance-engineering/01-execution-plans.md) |
| **SPM** | SQL Plan Management | [3.6](../performance-engineering/02-optimizer-statistics-spm.md) |
| **Standby redo log** | Log on a standby that receives redo from the primary | [3.9](../high-availability/02-data-guard.md) |
| **Star schema** | Fact table surrounded by denormalized dimensions | [4.6](../data-warehousing/01-data-warehousing.md) |
| **Surrogate key** | Generated key with no business meaning | [1.2](../database-fundamentals/02-relational-model.md) |
| **Tablespace** | Logical container of segments, made of data files | [3.2](../storage-management/01-storage.md) |
| **TAC** | Transparent Application Continuity | [3.8](../high-availability/01-rac-asm.md) |
| **TDE** | Transparent Data Encryption | [3.5](../security/01-security.md) |
| **Two-phase commit** | Prepare then commit protocol for distributed transactions | [2.11](../transactions/01-transactions-concurrency.md) |
| **Undo** | Before-images used for rollback, read consistency and flashback | [3.2](../storage-management/01-storage.md) |
| **Unified Auditing** | Policy-based auditing with a single trail | [3.5](../security/01-security.md) |
| **Vector** | A list of numbers; in 23ai+ a data type for embeddings | [4.7](../oracle-26ai/01-oracle-26ai.md) |
| **VPD** | Virtual Private Database: policy-driven row-level security | [3.5](../security/01-security.md) |
| **Wait event** | Named reason a session is not on CPU | [3.7](../performance-engineering/03-awr-ash-waits.md) |
| **Window function** | Function computed over a set of rows related to the current row | [2.5](../advanced-sql/05-window-functions.md) |
