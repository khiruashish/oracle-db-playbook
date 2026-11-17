---
tags: [freshmart, capacity-planning, architecture]
---

# FreshMart 5: Scaling from 10 thousand to 10 million customers

!!! warning "Every number here is an assumption"
    This page is a **method** shown with illustrative figures. The workload
    assumptions are stated first; change them and the conclusions change.
    Measure your own system before buying anything.

## Workload assumptions

| Assumption | Value |
|---|---|
| Orders per active customer per month | 1.5 |
| Lines per order | 4 |
| Peak hour share of a day | 12% |
| Promotion day versus normal day | 3x |
| Reads per order (catalog, search, cart views) | 200 SQL executions |
| Writes per order (cart changes, order, payment, shipment, stock) | 25 SQL executions |
| Average row sizes | order 150 B, order line 60 B, payment 120 B, shipment 150 B, stock movement 80 B, cart activity 200 B per order |
| Index overhead | 80% of table size |
| Redo per order (all tables and indexes) | 20 KB |
| Database CPU per SQL execution, tuned workload | 0.3 ms average |
| Online retention | 2 years, then archive; legal retention 7 years |

## Derived volumes

Peak orders per second = monthly orders ÷ 30 × 3 (promotion) × 12% ÷ 3600.

| | 10K customers | 100K | 1M | 10M |
|---|---:|---:|---:|---:|
| Orders per month | 15,000 | 150,000 | 1.5 million | 15 million |
| Orders per normal day | 500 | 5,000 | 50,000 | 500,000 |
| **Peak orders per second** (promotion day, peak hour) | 0.05 | 0.5 | 5 | 50 |
| Peak SQL executions per second (225 per order) | 11 | 113 | 1,125 | 11,250 |
| Peak CPU cores busy (0.3 ms each) | 0.01 | 0.03 | 0.34 | 3.4 |
| Redo per normal day | 10 MB | 100 MB | 1 GB | 10 GB |
| Peak redo rate | 1 KB/s | 10 KB/s | 100 KB/s | 1 MB/s |
| Order lines per year | 720,000 | 7.2 million | 72 million | 720 million |
| Data growth per year, tables + indexes (about 2.1 KB per order: 1.2 KB of rows × 1.8) | 0.4 GB | 4 GB | 38 GB | 380 GB |
| Online data at 2 years, plus catalog and customers | 1 GB | 9 GB | 80 GB | 800 GB |

Read these numbers twice. **Even at 10 million customers the tuned transactional
workload needs a handful of CPU cores and under a terabyte online.** The
order volume of a successful grocery business does not, by itself, require
exotic technology. What grows with scale is the cost of mistakes (an untuned
query at 11,000 executions a second), the size of maintenance operations, the
blast radius of an outage, and the analytics load.

## What each tier actually needs

### Tier 1: 10 thousand customers

| Aspect | Design |
|---|---|
| Database | One small instance: Free/SE2/a small cloud shape; 2 to 4 cores, 8 to 16 GB memory |
| Schema | As installed. No partitioning |
| Pool | 5 to 10 connections in total |
| Backup | Daily level 1, weekly level 0, archive logs hourly, off-site copy; restore tested quarterly |
| HA / DR | Restart on failure; restore to a spare. RTO hours, RPO up to the archive interval |
| Monitoring | Availability, space, backup success, slow SQL log |
| Priority | Correctness: constraints, the transactional API, migrations in Git |

### Tier 2: 100 thousand customers

| Aspect | Change from tier 1 |
|---|---|
| Database | 4 to 8 cores, 32 GB. Enterprise Edition becomes worthwhile for online operations and Data Guard |
| Indexing | Review top SQL monthly; composite indexes for the main read paths; search needs a text index |
| Pool | 10 to 20 total, fixed size |
| HA / DR | **A standby database** (Data Guard) with Fast-Start Failover: an outage now costs real money. RTO about a minute, RPO 0 in-region |
| Backup | As before, on the standby |
| Housekeeping | Scheduled purge of abandoned carts; audit log growth watched |
| Priority | Availability and operational routine (patching, restore tests) |

### Tier 3: 1 million customers

| Aspect | Change from tier 2 |
|---|---|
| Database | 8 to 16 cores, 64 to 128 GB. Still one primary instance |
| Partitioning | `orders` and children by month (interval + reference); `audit_log`, `stock_movements` by month. Reason: purge and maintenance, not query speed |
| Reads | Reports and dashboards moved to an Active Data Guard standby; materialized views for common aggregates |
| Pool | 30 to 60 total across all services, by measurement |
| HA / DR | Local SYNC standby plus a remote ASYNC standby. Switchover tested twice a year |
| Backup | Incrementally updated copies, block change tracking, immutable off-site copy |
| Isolation | Services per workload and a Resource Manager plan |
| Monitoring | AWR baselines for peak days, lag, top-SQL regression alerts, capacity trend |
| Priority | Workload isolation and lifecycle management |

### Tier 4: 10 million customers

| Aspect | Change from tier 3 |
|---|---|
| Database | 32 to 64 cores, 256 GB or more, or Exadata; headroom for 3x promotions and failover |
| Hot spots | Promotions concentrate on a few inventory rows: short reservation transactions, lock-free reservations (23ai+), admission control |
| Partitioning | As tier 3 plus compression tiering (ADO), read-only old partitions |
| Reads | Catalog served from a cache (True Cache, application cache or CDN); search on text/vector indexes or a search service |
| Analytics | A separate warehouse fed by change events; no heavy analytics on the primary |
| HA / DR | **RAC becomes justifiable** if the availability target is 99.99% or patch windows are gone. Otherwise still Data Guard |
| Pool | Sized to cores; a multiplexing layer (DRCP/CMAN) if many application instances |
| Operations | Fleet automation, quarterly DR exercises, performance testing before every peak season |
| Priority | Resilience under peak and failure; cost control |

## When each technology is justified

| Technology | Justified when | Not justified by |
|---|---|---|
| A bigger server | Measured CPU, memory or I/O saturation after tuning | A slow query |
| Enterprise Edition | Need for online operations, Data Guard, partitioning, parallelism | Customer count alone |
| Data Guard | An outage of hours is unacceptable | Never too early for a revenue system |
| Active Data Guard | Reporting or backups disturb the primary; zero-data-loss at distance | |
| Partitioning | Tables in the tens of GB with a purge or pruning key | "Performance" without a pruning predicate |
| RAC | Server-failure RTO in seconds; no patch windows; or load beyond one server that partitions cleanly | Disaster recovery; a wish to scale an unscalable workload |
| In-Memory | Analytic queries on live data that indexes and MVs cannot serve | OLTP lookups |
| GoldenGate | Zero-downtime migration; feeding other systems; multi-region writes | Simple DR |
| Sharding | Write volume or data size beyond one database, or legal data placement | 10 million customers at 50 orders per second |

By this model FreshMart would consider sharding at roughly **100 times** the
tier 4 volume, or earlier only for data residency
([5.2](../enterprise-architecture/01-global-architecture.md)).

## Connection pool sizing example (tier 3)

| Input | Value |
|---|---|
| Database cores | 16 |
| Peak SQL rate | 1,125 per second |
| Average SQL service time | 1 ms (including waits) |
| Concurrent sessions needed = rate × time | About 1.1 |
| Headroom for bursts and slow calls | × 10 to 20 |
| **Total active connections needed** | **About 12 to 24** |
| Application instances | 6 pods |
| Pool per pod | 6 to 8 (36 to 48 in total, still close to 2 to 3 × cores) |

A common real-world configuration of 6 pods × 50 connections = 300 would add
nothing but risk ([incident 9](../performance-incidents/01-incidents.md)).

## Storage and backup sizing example (tier 3)

| Item | Estimate |
|---|---|
| Online data (2 years) | 80 GB |
| With 30% free space and temp/undo | 120 GB |
| Archived redo per day | 1 GB normal, 3 GB on promotion days |
| Backups: weekly level 0 (compressed about 2x) + daily incrementals + 14 days of logs | About 150 GB |
| Standby databases | 2 × 120 GB |
| 7-year archive (compressed about 4x) | About 70 GB |

## Monitoring by tier

| Signal | Tier 1 | Tier 2 | Tier 3 | Tier 4 |
|---|---|---|---|---|
| Availability, space, backups | Yes | Yes | Yes | Yes |
| Standby lag | | Yes | Yes | Yes |
| Top SQL and plan changes | | Monthly review | Alerts | Alerts + pre-peak tests |
| Business KPIs (orders per minute, checkout latency) | | Yes | Yes | Yes |
| Capacity forecast | | | Quarterly | Monthly |
| Synthetic checkout probe | | | Yes | Yes |

## Capacity planning loop

1. Measure unit costs from AWR on a peak day: CPU seconds, logical reads and redo **per order**.
2. Multiply by the forecast peak order rate; add headroom (failover, growth lead time).
3. Compare with installed capacity; find the first resource to saturate.
4. Decide: tune, isolate, scale up, or change architecture, in that order.
5. After each peak season, compare forecast with actual and correct the assumptions above.

## Check yourself

??? example "Exercises"
    1. Recompute the table for 3 orders per customer per month and 8 lines per order. Which conclusions change? *Volumes roughly double to quadruple; no tier boundary moves.*
    2. Your measured CPU per SQL execution is 3 ms, not 0.3 ms. What is the first action at tier 4? *Tune: the workload needs 34 cores busy at peak, ten times the tuned figure, so SQL efficiency is the lever, not hardware.*
    3. Argue against the tier 3 decision to stay on a single instance. What requirement would overturn it?

Next: [Production architecture](06-architecture.md).
