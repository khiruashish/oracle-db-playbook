---
tags: [stage-4, performance, scalability]
---

# 4.4 Scalability: Resource Manager, In-Memory, compression

!!! abstract "Chapter card"
    **Stage:** 4 · **Prerequisites:** 3.6, 3.7 · **Time:** 4 hours ·
    :material-license: In-Memory and Advanced Compression are options; Resource Manager is part of EE

## At a glance

| Subtopic | In one line |
|---|---|
| Scaling model | Up, out, and "do less work" |
| Workload isolation | Services, PDBs, instances, replicas |
| Resource Manager | Share CPU, I/O and parallelism by policy |
| Database In-Memory | A columnar copy for analytics |
| Compression | Basic, Advanced, Hybrid Columnar |
| Result cache, True Cache | Avoid repeated work |
| Consolidation | Many databases, few platforms |

## 1. A scaling model

| Lever | Examples | When |
|---|---|---|
| **Do less work** | SQL tuning, indexes, partitions, MVs, caching, fewer round trips | Always first: often 10x to 1000x |
| **Scale up** | More cores, memory, faster storage, Exadata | Simple; limited by the largest machine and licence cost |
| **Scale reads out** | Active Data Guard, True Cache, MVs in a reporting database | Read-heavy workloads |
| **Scale writes out** | RAC (if the workload partitions), sharding | Last: highest complexity |

Throughput stops growing when one resource saturates or contention dominates
(Amdahl's law and the Universal Scalability Law): doubling cores doubles
nothing if sessions queue on one hot row.

## 2. Workload isolation

Different workloads (checkout, search, reports, batch) should not be able to
starve one another.

| Mechanism | Isolation |
|---|---|
| **Services** | Name, measure and control each workload; the unit for everything below |
| **Resource Manager** | CPU, parallelism, runaway queries, by consumer group or PDB |
| **PDBs** | Per-tenant or per-service resource plans, memory and I/O limits |
| **Instance affinity** (RAC) | Workloads on different nodes |
| **Read replicas** (Active Data Guard) | Reports off the primary |
| **Separate databases** | Strongest; most expensive |

## 3. Database Resource Manager

When CPU is saturated, the operating system gives every process an equal
chance. Resource Manager replaces that with a **plan**.

```sql
BEGIN
    DBMS_RESOURCE_MANAGER.CREATE_PENDING_AREA;

    DBMS_RESOURCE_MANAGER.CREATE_CONSUMER_GROUP('OLTP_GROUP',   'Checkout and catalog');
    DBMS_RESOURCE_MANAGER.CREATE_CONSUMER_GROUP('REPORT_GROUP', 'Dashboards and ad hoc');
    DBMS_RESOURCE_MANAGER.CREATE_CONSUMER_GROUP('BATCH_GROUP',  'Nightly jobs');

    DBMS_RESOURCE_MANAGER.CREATE_PLAN('FM_DAY_PLAN', 'Daytime priorities');

    DBMS_RESOURCE_MANAGER.CREATE_PLAN_DIRECTIVE(plan => 'FM_DAY_PLAN',
        group_or_subplan => 'OLTP_GROUP', shares => 8);
    DBMS_RESOURCE_MANAGER.CREATE_PLAN_DIRECTIVE(plan => 'FM_DAY_PLAN',
        group_or_subplan => 'REPORT_GROUP', shares => 2,
        parallel_degree_limit_p1 => 4,
        switch_time => 300, switch_group => 'CANCEL_SQL');     -- cancel statements over 5 minutes
    DBMS_RESOURCE_MANAGER.CREATE_PLAN_DIRECTIVE(plan => 'FM_DAY_PLAN',
        group_or_subplan => 'BATCH_GROUP', shares => 1, utilization_limit => 30);
    DBMS_RESOURCE_MANAGER.CREATE_PLAN_DIRECTIVE(plan => 'FM_DAY_PLAN',
        group_or_subplan => 'OTHER_GROUPS', shares => 1);

    -- Map sessions to groups by service
    DBMS_RESOURCE_MANAGER.SET_CONSUMER_GROUP_MAPPING(
        DBMS_RESOURCE_MANAGER.SERVICE_NAME, 'FM_REPORTS', 'REPORT_GROUP');

    DBMS_RESOURCE_MANAGER.VALIDATE_PENDING_AREA;
    DBMS_RESOURCE_MANAGER.SUBMIT_PENDING_AREA;
END;
/
ALTER SYSTEM SET resource_manager_plan = 'FM_DAY_PLAN';
```

*Illustrative: grant the groups to users/roles with
`DBMS_RESOURCE_MANAGER_PRIVS` and verify directive parameters for your release.*

| Control | Effect |
|---|---|
| **Shares** | Relative CPU when the system is busy. Nothing is wasted when it is idle |
| `utilization_limit` | A hard cap, even when CPU is free |
| Parallel degree limit, parallel queue timeout | Tames parallel queries |
| `switch_time`, `switch_io_reqs`, `switch_elapsed_time` + `switch_group` | Demote, cancel or kill runaway statements |
| `max_idle_blocker_time` | Kill idle sessions that block others |
| Active session pool | Limit concurrently active sessions in a group; the rest queue |
| **CDB plans** | Shares and limits per PDB; PDB **performance profiles** for fleets |
| **Instance caging** (`CPU_COUNT` + a plan) | Cap a whole instance when several share a server |
| I/O Resource Manager | On Exadata storage |

Throttled sessions wait on `resmgr:cpu quantum`. Seeing that event means the
plan is working, and that demand exceeds the allocation.

## 4. Database In-Memory

The **In-Memory column store (IM column store)** keeps a second, **columnar**
copy of chosen tables in memory alongside the normal row format. OLTP continues
to use rows and the buffer cache; analytic queries scan the columns. The two
are transactionally consistent and need no application change.

```sql
ALTER SYSTEM SET inmemory_size = 16G SCOPE = SPFILE;     -- then restart

ALTER TABLE order_items INMEMORY MEMCOMPRESS FOR QUERY LOW PRIORITY HIGH;
ALTER TABLE orders      INMEMORY NO INMEMORY (created_at, updated_at);

SELECT segment_name, populate_status, bytes, inmemory_size, bytes_not_populated
FROM   v$im_segments;
```

Why it is fast: only the needed columns are read; data is compressed and
scanned with SIMD vector instructions; **storage indexes** (min/max per
in-memory unit) skip data; **In-Memory aggregation** and **join groups** speed
star queries. Plans show `TABLE ACCESS INMEMORY FULL`.

| Good for | Not for |
|---|---|
| Aggregations and filters over many rows and few columns | Single-row lookups by key (an index is faster) |
| Ad hoc analytics on live OLTP data | Queries dominated by joins on unpopulated tables |
| Replacing analytic indexes (fewer indexes → faster DML) | Tiny memory budgets |

Options: compression levels (`FOR DML`, `QUERY LOW/HIGH`, `CAPACITY LOW/HIGH`),
population priority, **Automatic In-Memory** (manages population by usage),
population on an Active Data Guard standby, and the **Base Level** (up to 16 GB
with `INMEMORY_FORCE = BASE_LEVEL` without the option; confirm in the licensing
manual for your release).

## 5. Compression

| Type | How | Ratio (typical) | DML | Licence |
|---|---|---|---|---|
| **Basic** (`ROW STORE COMPRESS BASIC`) | Block-level dictionary, applied on direct-path load only | 2x to 4x | Updates decompress rows | EE |
| **Advanced Row** (`ROW STORE COMPRESS ADVANCED`) | Same format, maintained during conventional DML | 2x to 4x | Suitable for OLTP | Advanced Compression |
| **Hybrid Columnar** (`COLUMN STORE COMPRESS FOR QUERY / ARCHIVE`) | Columnar compression units | 6x to 15x and more | Bulk-loaded, rarely updated data | Exadata and certain Oracle storage |
| **Index** (`COMPRESS n`, `COMPRESS ADVANCED LOW/HIGH`) | Prefix or block-level | | | Prefix: EE. Advanced: option |
| **SecureFiles LOB** compress / deduplicate | | | | Advanced Compression |
| RMAN, Data Pump, Data Guard redo transport compression | | | | Advanced Compression (except RMAN `BASIC`) |

Ratios depend entirely on your data: estimate with
`DBMS_COMPRESSION.GET_COMPRESSION_RATIO` before committing.

Compression trades CPU for I/O and memory. For scan-heavy and I/O-bound
workloads it usually **improves** performance, because fewer blocks are read
and more data fits in the cache. Combine with partitioning and Automatic Data
Optimization so data is compressed harder as it ages
([2.13](../partitioning/01-partitioning.md)).

## 6. Caching

| Cache | What | Notes |
|---|---|---|
| Buffer cache | Blocks | Automatic |
| **Server result cache** | Results of queries (`/*+ RESULT_CACHE */`) and PL/SQL functions | Invalidated on any change to dependent tables; for read-mostly lookups only. Contention if misused |
| Client result cache | Results in the driver's memory | |
| **True Cache** (:material-tag: **23ai+**) | A diskless read-only instance kept current from redo, in front of the primary | A consistent SQL cache without cache-invalidation code; Active Data Guard licensing applies |
| Application caches (Redis and others) | Objects | You own invalidation and staleness |
| Materialized views | Precomputed results | [2.14](../database-objects/01-database-objects.md) |

## 7. Consolidation

| Model | Density | Isolation | Notes |
|---|---|---|---|
| Schema consolidation | Highest | Weak | Name clashes, shared patching, hard to move |
| **PDB consolidation** | High | Good, with resource plans and lockdown profiles | The standard model; one patch and backup process for many |
| Several instances per server (instance caging) | Medium | Good | More memory and process overhead |
| Virtual machines | Low | Strong | Licence implications depend on the hypervisor |

Rules of thumb: consolidate by **service tier** (do not mix Platinum and Bronze
in one CDB), by **patch cadence** and by **maintenance window**; cap each PDB;
plan for the *sum of peaks that coincide*, not the sum of averages; keep
headroom to host the load of a failed node.

**Fleet management**: PDB templates and gold images, performance profiles,
automated patching (Fleet Patching and Provisioning / Fleet Update), and a
single inventory with owner, tier and data classification per PDB.

## 8. Common mistakes

- Buying hardware before removing waste.
- A Resource Manager plan with only limits and no mapping (everything lands in `OTHER_GROUPS`).
- In-Memory used for OLTP lookups, or sized too small to hold the hot tables.
- Advanced compression enabled without the licence, or basic compression on a table that is updated heavily.
- Result cache on frequently changing tables.
- Consolidating without caps: one noisy tenant degrades all.

## FreshMart example

=== "Scenario"

    Every weekday at 09:00 the finance team opens dashboards that aggregate a
    year of `order_items`. Checkout latency doubles for 15 minutes.

=== "Options"

    | Option | Effect | Cost |
    |---|---|---|
    | Resource Manager plan (section 3) | Reports limited to their share when CPU is contended; runaway queries cancelled | None; immediate |
    | Move reports to the Active Data Guard standby | Removes the load from the primary | Already licensed in the 3.9 design |
    | Materialized views for the dashboard queries | Reports become cheap | MV logs on hot tables |
    | In-Memory column store on the standby | Sub-second ad hoc analytics | In-Memory option, memory |

=== "Decision"

    Step 1 (today): the plan, mapping the `fm_reports` service to
    `REPORT_GROUP`. Step 2 (this quarter): point `fm_reports` at the standby.
    Step 3 (only if ad hoc analysis is still slow): In-Memory on the standby.
    MVs were rejected because the fast-refresh logs would add write cost to
    `order_items`, the hottest insert table.

=== "Takeaway"

    Isolation first, relocation second, acceleration third. Each step is
    justified by what remains after the previous one, and the cheapest step
    fixed the customer-facing symptom.

## Check yourself

??? question "Interview questions"
    1. **(Senior)** What does Resource Manager do when the system is not busy? *Nothing, unless hard limits are set: shares apply only under contention.*
    2. **(Senior)** How does the In-Memory column store stay consistent with row data?
    3. **(Principal)** Advanced Row versus Hybrid Columnar compression: when each?
    4. **(Principal)** How do you size a consolidated CDB?
    5. **(Architect)** A division wants its own Exadata "for performance isolation". Response? *Quantify the isolation actually needed and show what CDB resource plans, instance caging and I/O Resource Manager provide; compare cost and operational burden; grant separate hardware only for regulatory or blast-radius reasons.*

??? example "Exercises"
    1. Create two consumer groups and a plan, map them by service, and observe `resmgr:cpu quantum` under load.
    2. Estimate the compression ratio of `order_items` with `DBMS_COMPRESSION`.
    3. List which FreshMart queries would and would not benefit from In-Memory.

## Related

Next: [4.5 Data movement and integration](../data-integration/01-data-integration.md).
