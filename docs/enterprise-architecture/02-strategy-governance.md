---
tags: [stage-5, strategy, governance, adr]
---

# 5.3 Strategy, governance and architecture decisions

!!! abstract "Chapter card"
    **Stage:** 5 · **Prerequisites:** 5.1, 5.2 · **Time:** 5 hours

## At a glance

| Subtopic | In one line |
|---|---|
| Architecture decision records | Writing decisions down so they survive their authors |
| Design reviews | A checklist that finds problems before production does |
| Platform engineering and standardization | A small menu of well-run options |
| Data governance | Ownership, classification, quality, lifecycle |
| Modernization and legacy transformation | Changing an estate without stopping the business |
| Technical debt | Making it visible and paying it deliberately |
| Technology and vendor evaluation | Comparing options without fashion |
| Roadmaps and executive communication | From engineering facts to business choices |

## 1. Architecture decision records (ADRs)

An ADR is one page that records **one** decision: its context, the options, the
choice and its consequences. It is immutable; a later decision supersedes it.

```markdown
# ADR-014: Single write region with in-country standby for the order database

Status: Accepted (2026-03-14). Supersedes: none. Owner: Database platform lead.

## Context
Availability target 99.95%. RPO 0 for a server or zone failure, 30 s for a region
failure. Customers transact only in their own country. Team of 4 platform engineers.

## Options considered
1. Single instance + local SYNC standby + remote ASYNC standby (Data Guard, FSFO).
2. Option 1 with 2-node RAC at each site.
3. Active-active across two regions with GoldenGate.

## Decision
Option 1.

## Rationale
Meets the targets (see downtime budget in appendix). Option 2 adds licence and
operational cost for a patch-window benefit we do not need. Option 3 introduces
conflict handling for inventory with no requirement that justifies it.

## Consequences
+ Simple operations; one write path; strong consistency.
- About 1 minute of interruption on a server failure; patching needs a switchover.
- Standby must be sized as production.

## Revisit when
Availability target reaches 99.99%; patch windows are withdrawn; peak load passes
70% of the largest available server.
```

What makes an ADR useful: the **rejected options and why**, the consequences
you accept, and explicit **revisit triggers**. Keep ADRs in the repository next
to the code they govern.

## 2. Design reviews

Review designs before build and again before go-live. A checklist turns
individual experience into an organizational habit.

| Area | Questions |
|---|---|
| Requirements | RTO/RPO per failure class? Peak volumes for year 1 and year 3? Data classification? |
| Data model | Keys and constraints declared? Growth per table? Retention and purge designed? Hot rows? |
| Workload | Transaction boundaries? Remote calls inside transactions? Batch windows? Read/write ratio? |
| Access | Bind variables? Pool sizes versus cores? Service names? Least-privilege accounts? |
| Performance | Top 10 statements identified with plans on production-size data? Indexes justified? |
| Availability | Failure walk-through done ([4.1](../high-availability/03-ha-dr-architecture.md))? Client failover tested? |
| Recovery | Backup, restore test, logical-error recovery path? |
| Security | Encryption, auditing, masking for non-production, secrets handling? |
| Operations | Monitoring and alerts with runbooks? Patching path? Capacity headroom? Owner on call? |
| Change | Migration strategy, backward compatibility, rollback, drift control? |
| Cost and licensing | Options and packs used? Environment count? Growth cost curve? |
| Exit | How would we leave this platform or product? |

Outcome of a review: a short list of risks with owners and dates, not a
verdict. Track them to closure.

## 3. Platform engineering and standardization

The database platform is a **product** whose customers are application teams.

| Element | Example standard |
|---|---|
| Supported versions | Current long-term release, maximum one RU behind plus a quarter |
| Service tiers | Bronze / Silver / Gold with fixed architectures, SLAs and prices ([4.1](../high-availability/03-ha-dr-architecture.md)) |
| Sizes | Small, medium, large shapes rather than bespoke servers |
| Provisioning | Self-service through a pipeline or portal: a PDB in minutes |
| Guardrails | Naming, default profiles, audit policies, resource plans, lockdown profiles |
| Golden paths | Templates for connection pools, migrations, monitoring dashboards |
| Operations | Automated patching, backup, restore tests; one observability stack |
| Reporting | Inventory, cost showback, compliance posture per database |

**Standardization trade-off:** fewer variants mean lower cost, faster patching
and transferable skills; too rigid a standard pushes teams to shadow platforms.
Run an **exception process**: time-limited, with an owner, a reason and a
revisit date. Count the exceptions; a frequently requested exception is a
signal the standard needs another option.

**Architecture governance** works when it is light: published principles, ADRs,
review at defined gates, automated policy checks in pipelines, and a small
group that can say yes quickly.

## 4. Data governance

| Capability | Meaning | Database-level mechanism |
|---|---|---|
| **Ownership** | A named business owner and steward for each data domain | Recorded in a catalog; schema and PDB naming aligned to domains |
| **Classification** | Public, internal, confidential, restricted; personal data flagged | Annotations (23ai+), sensitive data discovery, column comments |
| **Catalog and lineage** | What data exists, what it means, where it flows | Data dictionary, data catalog tools, documented pipelines |
| **Quality** | Fitness measured by rules | Constraints, reconciliation checks, quality dashboards |
| **Access policy** | Who may see and change what, for which purpose | Roles, VPD, Database Vault, audit |
| **Lifecycle** | Retention, archive, deletion | Partition lifecycle, ADO, purge jobs with evidence |
| **Master and reference data** | One authoritative source per entity | Ownership rules, replication from the master |

Governance fails as a committee and works as defaults: classification required
at table creation, retention required in the design review, masking built into
the clone pipeline.

### Regulatory compliance

Translate each regulation into controls and evidence
([3.5](../security/01-security.md)). Automate evidence collection
(configuration baselines, audit reports, restore-test results, access reviews)
so an audit is a report run, not a project.

## 5. Modernization and legacy transformation

| Strategy | Meaning | Database example |
|---|---|---|
| Retain | Leave as is, for now | A stable system near end of life |
| Rehost | Move unchanged | 19c on-premises to 19c on cloud infrastructure |
| Replatform | Move with limited change | Upgrade to 26ai as a PDB on a managed service |
| Refactor | Restructure | Split a shared schema by domain; replace database links with events |
| Replace | Buy or rebuild | Legacy application retired for a SaaS product |
| Retire | Switch off | Unused databases found during discovery (there are always some) |

Patterns for changing a live estate:

- **Strangler fig**: route one capability at a time to the new system; the old one shrinks.
- **Change data capture bridge**: keep old and new in sync during a long transition.
- **Schema decoupling first**: give each consumer its own views or APIs before moving tables.
- **Wave planning** by dependency group, with rehearsed cutovers ([5.1](../cloud-database/01-cloud.md)).

Large-scale migration is mostly logistics: inventory quality, dependency
discovery, a factory approach with repeatable runbooks, and honest reporting of
progress. The technology is rarely what fails.

Legacy traps: logic hidden in triggers and in batch scripts nobody owns;
undocumented consumers reading tables directly; data quality problems that the
old application silently tolerates; character set and data type conversions.

## 6. Technical debt

| Debt | Cost if left |
|---|---|
| Unsupported or unpatched versions | Security exposure; forced, rushed upgrades |
| Missing constraints, duplicated data | Wrong reports, expensive cleanups |
| Shared schemas and database links | Coupled releases, hidden outages |
| Hints, disabled features, pinned optimizer versions | Upgrades blocked or risky |
| Manual operations | Errors, key-person risk |
| Unbounded tables without lifecycle | Growing cost, slower everything |
| Oversized or unknown licences | Money and audit risk |

Manage it like any portfolio: keep a register with **cost of delay** and
**effort**, reserve capacity each quarter (a fixed share works better than
occasional "cleanup projects"), and tie items to roadmap events (pay version
debt before the migration that depends on it).

## 7. Technology and vendor evaluation

1. **Start from requirements and constraints**, weighted, before looking at products.
2. **Shortlist** on hard constraints (compliance, skills, integration).
3. **Prove** with a workload-representative proof of concept: your data shapes, your concurrency, your failure tests. Vendor benchmarks answer the vendor's question.
4. **Total cost** over the planning horizon, including migration, people, operations and exit.
5. **Risk**: vendor viability, lock-in, roadmap, support quality, community.
6. **Decide and record** in an ADR with revisit triggers.

| Criterion | Evidence to ask for |
|---|---|
| Correctness under concurrency and failure | Your own tests: kill nodes mid-transaction |
| Performance at your scale | PoC with production-like data and percentiles |
| Operability | Patch, backup, restore, upgrade demonstrated |
| Security and compliance | Certifications plus the controls you need |
| Ecosystem and skills | Hiring market, tooling, internal experience |
| Commercial terms | Licence metric, audit clauses, price protection |
| Exit | Data and code portability, measured |

On "converged versus specialized": a second database technology has a fixed
cost in skills, tooling, security review and on-call. It is justified when a
requirement clearly exceeds what the incumbent does well, not when a feature
demo is attractive.

## 8. Roadmaps and communicating with executives

A database roadmap answers: what must change, why now, what it costs, what
happens if we do not.

| Horizon | Typical content |
|---|---|
| Now (0 to 6 months) | Risk removal: patch currency, backup verification, top incidents |
| Next (6 to 18 months) | Version upgrades before support ends, consolidation, automation, DR tests |
| Later (18 to 36 months) | Platform moves, modernization, new capabilities |

Rules for executive communication:

- Lead with the **decision needed** and the **options with prices and risks**.
- Use business units: revenue at risk per hour, customers affected, audit findings, cost per year. Not wait events.
- State **confidence** and what would change the recommendation.
- One page. Detail in an appendix.
- Report outcomes afterwards: predicted versus actual.

**Cost optimization** as a standing practice: licence position reviewed
quarterly (feature usage reports), right-sizing from measured peaks,
consolidation ratios, storage tiering, non-production schedules, and
showback so that teams see what their databases cost.

## 9. Common mistakes

- Decisions made in meetings and never written down.
- Standards without an exception path, or exceptions without expiry.
- Governance as a gate at the end rather than defaults at the start.
- Modernization that moves a mess to a more expensive place.
- Evaluations driven by benchmarks on someone else's workload.
- Roadmaps listing technologies instead of outcomes.

## FreshMart example

=== "Scenario"

    FreshMart's CTO asks for a three-year database strategy on one page. The
    estate: 14 Oracle databases (three on 19c non-CDB, eleven on 23ai),
    two PostgreSQL databases started by product teams, manual patching, no DR
    test in 18 months.

=== "One-page strategy"

    | Outcome | Action | By | Cost / risk note |
    |---|---|---|---|
    | No unsupported or stale software | Convert the three 19c non-CDBs to PDBs on 26ai; RUs within one quarter by automated out-of-place patching | Q3 | Engineering time; AutoUpgrade and one rehearsal each |
    | Proven recoverability | Quarterly restore tests and twice-yearly switchover tests, reported to the risk committee | Q2, then ongoing | One weekend per test until automated |
    | Fewer, standard platforms | Consolidate 14 databases into 3 CDBs by tier with resource plans | Q4 | Frees an estimated 30% of licensed cores |
    | Self-service with guardrails | PDB provisioning and schema migration pipelines; no manual production DDL | Year 2 | Platform team of 4 becomes sustainable |
    | A clear rule for new technology | ADR: Oracle is the default for transactional data; PostgreSQL is supported as a second option on the same platform standards; any third engine needs an ADR | Q2 | Stops unmanaged sprawl without banning choice |
    | Readiness for growth | Capacity model reviewed quarterly; Gold tier (remote standby) for the order database | Year 1 | Standby infrastructure cost |

=== "Decision asked of the CTO"

    1. Approve the Gold tier investment for the order database (cost of one
       standby environment against an estimated loss per outage hour).
    2. Approve a fixed 20% of platform capacity for debt reduction.
    3. Endorse "no manual production changes" as policy from a fixed date.

    Illustrative numbers.

=== "Takeaway"

    The page contains no feature names beyond what the decisions require. Each
    line has an outcome, an owner date and a cost, and the page ends with the
    three decisions only the executive can make.

## Check yourself

??? question "Interview questions"
    1. **(Principal)** What belongs in an ADR?
    2. **(Principal)** How do you run a database design review?
    3. **(Architect)** How do you balance standardization with team autonomy?
    4. **(Architect)** How do you prioritize technical debt?
    5. **(Architect)** How do you evaluate replacing Oracle with another database for a core system? *Requirements and constraints first; inventory of features and PL/SQL in use; a PoC on the real workload including failure and operations; 5-year TCO including migration, dual running and risk; a staged plan with an exit at each stage; and a clear statement of what the business gains besides licence savings.*

??? example "Exercises"
    1. Write an ADR for a decision made on a system you know, including two rejected options.
    2. Run the design-review checklist against the FreshMart design and list the top five risks.
    3. Draft a one-page roadmap with three decisions for an executive.

## Related

You have finished the study path. Test yourself with the
[20-years question bank](../interview-preparation/05-level-20.md) and review the
[production standards](../standards/01-standards.md).
