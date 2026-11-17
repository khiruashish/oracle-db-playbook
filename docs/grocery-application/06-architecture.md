---
tags: [freshmart, architecture]
---

# FreshMart 6: Production architecture

Reference architectures for FreshMart, from the simplest that works to the
1-million-customer target design. Diagram sources are in `diagrams/`.

## 1. Single-instance architecture (tiers 1 and 2)

```mermaid
--8<-- "diagrams/architecture/single-instance.mmd"
```

| Component | Role | Failure effect |
|---|---|---|
| Application instances with a fixed-size pool | Run business logic; hold few connections | Stateless: another instance takes over |
| Listener and service `fm_oltp` | Entry point; names the workload | Restarted by Oracle Restart |
| CDB with PDB `FRESHMART` | The database | Outage until restart or restore |
| Fast recovery area | Archived logs, flashback logs, local backups | Database hangs if it fills: monitored |
| Off-site backup store | Recovery from site or storage loss | |
| Monitoring | Availability, space, backups, slow SQL | |

Adequate while an outage of an hour or two is tolerable. The first upgrade is a
standby, not a cluster.

## 2. Data Guard architecture (tier 3 target)

```mermaid
--8<-- "diagrams/architecture/data-guard.mmd"
```

| Component | Role |
|---|---|
| Primary `fm_prd` (zone 1) | All writes |
| Local standby `fm_sby` (zone 2), SYNC, Active Data Guard | Zero-data-loss failover target; read-only service `fm_ro` for reports; backups run here |
| Remote standby `fm_dr` (second region), ASYNC | Regional disaster recovery |
| Observer (third location) | Fast-Start Failover: automatic failover to `fm_sby` after 30 s |
| Role-based services | `fm_oltp` runs on whichever database is primary; applications never change their connect string |
| Flashback Database on all three | Reinstate the old primary in minutes |

Objectives met: RPO 0 and RTO about 1 minute for server or zone loss; RPO
seconds and RTO about 15 minutes for regional loss. Details and trade-offs:
[3.9](../high-availability/02-data-guard.md),
[4.1](../high-availability/03-ha-dr-architecture.md).

## 3. RAC architecture (only where justified)

```mermaid
--8<-- "diagrams/architecture/rac.mmd"
```

Adopted at tier 4 **only if** the availability target moves to 99.99% or patch
windows are withdrawn ([3.8](../high-availability/01-rac-asm.md)). Data Guard
remains: RAC does not protect against site loss or corruption.

| Service | Preferred instances | Reason |
|---|---|---|
| `fm_oltp` | 1 and 2 | Checkout and catalog; Transparent Application Continuity |
| `fm_batch` | 2 (available: 1) | Keeps batch block activity on one instance |
| `fm_ro` | The standby | Reports off the cluster |

## 4. Multi-region disaster recovery

| Event | Action | Who decides |
|---|---|---|
| Zone or primary server lost | Automatic failover to `fm_sby` | Observer |
| Region lost | Manual failover to `fm_dr`; DNS/traffic manager moves application traffic to the DR region application tier | Incident commander, per the DR runbook |
| Logical corruption | Flashback or point-in-time recovery of the affected PDB or table; standbys do **not** help | DBA lead with business owner |
| Return to normal | Reinstate the former primary as a standby, resynchronize, planned switchover | Change process |

The DR region runs a scaled-down application tier that can scale out, the same
monitoring, and its own backups. It is exercised by a planned switchover twice
a year for a full business day.

## 5. Backup and recovery architecture

```mermaid
--8<-- "diagrams/architecture/backup.mmd"
```

| Layer | Protects against | Retention |
|---|---|---|
| Flashback (undo, flashback logs, restore points) | Recent human error, bad releases | Hours to days |
| RMAN to local disk (from the standby) | Media failure; fast restores | 7 days |
| RMAN copy to object storage, immutable | Site loss, ransomware, malicious deletion | 35 days + monthly for 7 years |
| Data Pump export of the schema, weekly | Logical copy; refresh of test | 4 weeks |
| Keystore backup, separate location | Loss of TDE keys | Every key rotation |

Restore tests: quarterly full restore to scratch infrastructure with elapsed
time recorded; monthly `RESTORE ... VALIDATE`.

## 6. Monitoring architecture

| Layer | Signals | Tooling (examples) |
|---|---|---|
| Business | Orders per minute, checkout success rate, p95 checkout latency | Application metrics, synthetic checkout probe |
| Application | Pool active/pending, SQL error rates, slow endpoints | Micrometer, tracing |
| Database | DB time by wait class, top SQL, sessions, blockers, lag, hard parses | AWR/ASH (licensed) or exporter + `V$` views; Enterprise Manager / OCI Database Management |
| Storage and backup | Tablespace, FRA, ASM usable space; backup age and status; restore-test results | Scheduled checks |
| Security | Failed logins, privilege changes, non-application access to personal data | Unified audit → SIEM |
| Infrastructure | CPU, memory, I/O latency, network | Platform monitoring |

Alert rules: page a human only for symptoms that need action now (service
down, lag beyond RPO, space within 24 hours of full, backup missed twice); send
everything else to a dashboard or ticket. Every alert links to a
[runbook](../production-runbooks/index.md).

## 7. Security architecture

```mermaid
--8<-- "diagrams/architecture/security.mmd"
```

| Zone / control | Design |
|---|---|
| Network | Database in a private subnet; only application subnets and a bastion may reach the listener; TLS required |
| Accounts | `FRESHMART` owner without authentication; `FM_APP` per service with secrets from a vault; named personal accounts through central identity |
| Privileged access | Just-in-time elevation, recorded sessions, break-glass procedure |
| Data at rest | TDE on all application tablespaces; keys in a key management service; encrypted backups |
| Data exposure | Redaction for support roles; masked clones for non-production |
| Audit | Unified audit policies shipped to a SIEM the DBAs cannot modify |
| Change | Pipeline-only DDL |

## 8. Database DevOps architecture

```mermaid
--8<-- "diagrams/deployment/devops.mmd"
```

Every change flows through the same path; production differs only by the
approval gate and the guaranteed restore point
([4.9](../database-devops/01-devops.md)).

## 9. Cloud deployment architecture

```mermaid
--8<-- "diagrams/deployment/cloud.mmd"
```

| Decision | Choice | Reason |
|---|---|---|
| Database service | Managed database service with a cross-zone standby and a cross-region standby | Small platform team ([5.1](../cloud-database/01-cloud.md)) |
| Placement | Same region and private network as the Kubernetes cluster | Latency per round trip |
| Connectivity | Private endpoints; no public listener | Security |
| Secrets and keys | Cloud vault and key management | Rotation, audit |
| Infrastructure | Terraform | Reproducible environments |

## Architecture decisions in one table

| Decision | Chosen | Rejected | Revisit when |
|---|---|---|---|
| Write topology | Single primary | Multi-region writes | Regulation or latency requires local writes |
| Server failure cover | Data Guard FSFO | RAC | Target reaches 99.99% or patch windows end |
| Read scaling | Active Data Guard + MVs | Separate reporting copy by ETL | Analytics outgrows the standby |
| Order transaction | One database transaction in `order_pkg` | Saga across services | Teams and release cadence force a service split |
| Partitioning | Monthly on order tables from tier 3 | None; or daily | Table sizes or purge windows change |
| Platform | Managed cloud database | Self-managed VMs | Unit cost or control needs change |

## Check yourself

??? example "Exercises"
    1. For each diagram, name the single point of failure, if any.
    2. Walk through "primary region lost at peak": list every step, owner and expected duration.
    3. Write an ADR ([5.3](../enterprise-architecture/02-strategy-governance.md)) for the decision to stay on a single write region.
