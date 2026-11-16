---
tags: [interview, stage-4]
---

# Interview bank: 15 years (principal engineer)

45 questions (worked ones included). Chapters: Stage 4, FreshMart scaling and architecture.

At this level the answer is a **structure**: clarify, state assumptions, give
options with trade-offs, recommend, name the residual risk.

## Worked questions :material-star:

### W1. Design availability for an order database: RPO zero for a data-center failure, RTO under five minutes, and reports must not affect checkout.

**Clarify.** RPO/RTO for a *regional* failure? Is planned downtime allowed?
Distance and latency between sites? Peak load versus one server?

**Options.**

| Option | Meets it? | Cost and risk |
|---|---|---|
| Backups only | No: RTO hours | Cheapest |
| RAC in one data center | No: same storage and site | Licence, complexity |
| Local SYNC standby + Fast-Start Failover, Active Data Guard for reports, remote ASYNC standby | Yes | Two extra full-size databases; ADG licence; commit latency + round trip |
| The above with RAC at each site | Yes, and seconds for server failure | Roughly double again |

**Recommend** the third, in Maximum Availability with an observer at a third
location, role-based services, Flashback Database on all members, and backups
on the standby.

**Residual risk.** A double failure (primary lost while the standby is out of
sync) can lose data; logical errors replicate, so flashback and immutable
backups remain necessary; the design is unproven until switchover is tested.

**Follow-ups.** What if the nearest second site is 1,000 km away? (Far Sync.) How do clients follow the role change? How do you patch?
**Common wrong answer.** "Use RAC for high availability and it covers disaster recovery."

### W2. Migrate a 5 TB 19c on-premises database to 26ai in the cloud with at most ten minutes of downtime and a way back.

**Answer.** Logical replication: prepare the target (26ai PDB); verify keys and
enable supplemental logging; start GoldenGate capture and note the SCN; initial
load consistent as of that SCN (Data Pump with `FLASHBACK_SCN`, or a physical
copy upgraded on the target side); apply changes until lag is seconds; validate
with counts and hashes; rehearse cutover twice; cut over by stopping writes,
draining lag, advancing sequences/identities, repointing services; start
reverse replication to the old system for the fallback window.

**Trade-offs.** Data Guard plus upgrade is simpler but gives a longer outage
and no fallback after users write; ZDM automates much of the logical path.
**Risks.** Plan regressions (SQL Performance Analyzer, baselines); unsupported
types or keyless tables; features used after cutover that 19c cannot receive;
network throughput for the initial load.
**Common wrong answer.** A weekend export/import with "we will test on Monday".

### W3. A team wants to split the monolith database into one database per microservice. What do you ask and advise?

**Ask.** What problem is being solved: release coupling, ownership, scale,
blast radius? Which transactions span the proposed boundaries? Who needs
reports across them?

**Advise.** Split along transaction boundaries; data that must change
atomically stays in one service. Start with logical separation (schemas, then
PDBs) and remove cross-schema access before moving anything. Replace
cross-service transactions with sagas, an outbox for events, and idempotent
consumers. Give analytics its own path. Expect more operational objects,
eventual consistency visible to users, and new failure modes.

**Follow-ups.** Why not XA across services? How do you keep a read model current? What does a PDB per service buy you?
**Common wrong answer.** "Each service gets its own database and they call each other when they need data", with no answer for consistency.

### W4. When is sharding the right answer?

**Answer.** When write volume or data size exceeds what one database can serve
with headroom after tuning, partitioning and scaling up; when law requires
data placement by geography; or when fault isolation per tenant group is a
requirement. And only if a sharding key exists that keeps almost all
transactions on one shard. Costs: cross-shard queries and transactions, global
constraints limited to the key, operations multiplied by shards, and near
irreversibility of the key choice.

**Scenario.** [FreshMart scaling](../grocery-application/05-scaling.md): 10
million customers produce about 50 orders per second, far below the need.
**Common wrong answer.** "When the table has more than N million rows."

### W5. How do you make a schema change on an 80-million-row table with no downtime?

**Answer.** Expand, migrate, contract across several releases: add the new
structure in a backward-compatible, metadata-only or online way; have the
application write both; backfill in restartable batches watching redo and
standby lag; validate; switch reads; remove the old structure later. Use
online DDL (`ONLINE` index builds, `NOVALIDATE` then `VALIDATE`,
`DBMS_REDEFINITION`), `DDL_LOCK_TIMEOUT`, and Edition-Based Redefinition where
PL/SQL must change under load. Rehearse on a full-size copy for lock time.

**Follow-ups.** What is the rollback at each step? What can make a "metadata-only" change block?

## High availability and replication

| # | Question | Answer in brief |
|---|---|---|
| 1 | Describe the MAA tiers. | Bronze: single instance + backups. Silver: + RAC or local HA. Gold: + Data Guard. Platinum: + GoldenGate, Application Continuity, EBR. |
| 2 | Active-passive versus active-active? | One write site with failover versus several write sites with conflict management. Choose the first unless a requirement forces the second. |
| 3 | How does Far Sync work? | A light instance near the primary receives redo synchronously and forwards it asynchronously to a distant standby. |
| 4 | What makes a DR test meaningful? | Running production from the DR site for a business cycle, measuring RTO/RPO, including dependencies and failback. |
| 5 | Physical versus logical replication? | Block-identical copy for HA/DR versus row-change apply for heterogeneity, subsets and writable targets. |
| 6 | How do you avoid GoldenGate conflicts? | Ownership partitioning, non-overlapping keys, soft deletes, delta resolution for additive columns. |
| 7 | Why is supplemental logging needed? | So redo carries key columns needed to identify rows on the target. |
| 8 | What is Application Continuity? | Replay of in-flight requests after a failover so the application sees no error. |
| 9 | How do you size a standby? | Like production: it must carry peak load after failover. |
| 10 | Which failures does Data Guard not cover? | Logical errors and malicious changes, which replicate. |

## Scale and performance

| # | Question | Answer in brief |
|---|---|---|
| 11 | In what order do you scale? | Remove waste; isolate workloads; scale up; scale reads out; scale writes out last. |
| 12 | What does Resource Manager do? | Allocates CPU, parallelism and limits by consumer group or PDB when resources are contended. |
| 13 | When does In-Memory help? | Analytic scans and aggregations over many rows and few columns; not key lookups. |
| 14 | Advanced Row versus Hybrid Columnar compression? | OLTP-capable row compression versus much higher ratios for bulk-loaded, rarely updated data on Exadata. |
| 15 | How do you isolate reporting from OLTP? | Services with a resource plan, an Active Data Guard standby, materialized views, or a warehouse. |
| 16 | What limits RAC scalability? | Cross-instance block contention: hot blocks, right-growing indexes, unpartitioned workloads. |
| 17 | How do you size connection pools across many services? | Total active connections near 1 to 2 times database cores; fixed-size pools; multiplexing if instances are many. |
| 18 | How do you consolidate databases safely? | PDBs grouped by tier and patch cadence, caps per PDB, headroom for coinciding peaks and node loss. |
| 19 | How do you manage a hot row? | Short transactions, conditional updates, lock-free reservations, bucketing, or queueing. |
| 20 | How do you forecast capacity? | Unit cost per business transaction from AWR × forecast peak volume, plus headroom. |

## Distributed data and integration

| # | Question | Answer in brief |
|---|---|---|
| 21 | Explain CAP and PACELC with an Oracle example. | Under partition choose consistency or availability; otherwise latency or consistency. Max Protection versus ASYNC Data Guard. |
| 22 | Weakness of two-phase commit? | Blocking in-doubt transactions and coupled availability. |
| 23 | What is a saga? | Local transactions with compensations giving eventual consistency. |
| 24 | What is the outbox pattern? | Write the event in the same transaction as the data, relay it afterwards; delivery at least once. |
| 25 | Why idempotency? | Retries and redelivery are certain; duplicates must be harmless. |
| 26 | Log-based versus query-based CDC? | Reads redo: complete, low impact, captures deletes; versus polling with watermarks: simple, misses deletes and late commits. |
| 27 | Why can timestamp-based incremental loads miss rows? | A transaction that started before the watermark can commit after it. |
| 28 | Star schema versus 3NF for analytics? | Fewer joins, history via dimensions and simpler queries versus update efficiency. |
| 29 | SCD Type 2? | New dimension row per change with validity dates and surrogate keys. |
| 30 | How do you prove a pipeline is correct? | Automated reconciliation: counts, control totals, hashes, with stored results and alerts. |

## 26ai, application integration, DevOps

| # | Question | Answer in brief |
|---|---|---|
| 31 | What is a vector embedding and when is vector search appropriate? | A numeric representation of meaning; for semantic search and RAG, not exact lookups. |
| 32 | HNSW versus IVF? | In-memory graph: fastest, needs memory; versus partitioned on disk: scales to larger sets. |
| 33 | What does JSON Relational Duality provide? | Updatable JSON document views over normalized tables with optimistic concurrency. |
| 34 | Stored procedures or ORM? | Both by workload: ORM for aggregate CRUD; SQL/PLSQL for hot multi-row transactions and set processing. |
| 35 | What is the N+1 problem? | One query for parents plus one per child access; fix with fetch joins, projections or batch fetching. |
| 36 | Why no remote calls inside a transaction? | They hold locks and a pooled connection for the duration of the call. |
| 37 | Migration-based versus state-based schema management? | Ordered change scripts versus diff from a desired model; generated diffs need review. |
| 38 | What is Edition-Based Redefinition? | Running old and new PL/SQL and views side by side through editions for online application upgrades. |
| 39 | How do you roll back a database release after data was written? | Roll forward, or roll back the application against a backward-compatible schema; restore points only before writes. |
| 40 | What belongs in a database pipeline? | Lint, build from scratch, migrate a production copy, tests, lock and plan checks, approval, deploy with verification, drift detection. |
