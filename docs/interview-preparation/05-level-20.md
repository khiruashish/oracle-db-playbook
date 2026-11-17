---
tags: [interview, stage-5]
---

# Interview bank: 20 years (enterprise architect)

33 questions (worked ones included). Chapters: Stage 5.

There are no single correct answers here. Strong answers show how you **frame**
the decision, what **evidence** you would gather, the **options and their
costs**, your **recommendation**, and **what would change it**.

## Worked questions :material-star:

### W1. The CEO asks: "Why are we spending this much on databases, and can we halve it?"

**Frame.** Separate the cost into licences and support, infrastructure, people,
and risk. Ask what "halve" is measured against and by when.

**Evidence.** Licence position versus actual feature usage; utilization of
licensed cores at peak; environment count and non-production running hours;
storage by age; staff time on manual work; cost of the last outages.

**Options.**

| Lever | Typical effect | Risk |
|---|---|---|
| Right-size and consolidate (multitenant, fewer cores) | Large, recurring | Noisy neighbors without caps |
| Remove unused options and environments | Moderate, fast | Low |
| Tier storage and retention | Moderate | Retrieval expectations |
| Automate operations | Frees people, slowly | Investment first |
| Move tiers to cheaper editions or managed services | Variable | Feature gaps, migration cost |
| Replace the platform | Uncertain, late | High: years, dual running |

**Recommend** a sequenced plan: quick savings from usage and sizing in two
quarters, consolidation in a year, and a separate, evidence-based decision on
platform strategy. State the saving as a range with confidence.

**What would change it.** A contract event (renewal, audit), a compliance
finding, or a business change in growth.
**Common weak answer.** A technology answer ("move to open source", "move to
cloud") before knowing where the money goes.

### W2. Two regions, each with customers who must be served locally, and a regulator requiring data to stay in-country. Sketch the data architecture.

**Answer.** Classify data: regional and owned by a country (customers, orders,
payments, inventory); global reference (catalog definitions); derived
(analytics). Store regional data only in-country with an in-country standby and
backups. Author reference data in one place and replicate it one way.
Aggregate or anonymize in-region before anything crosses a border. Run one
automation code base with regional deployments and regional access controls.
Prefer separate regional databases, or user-defined sharding if the number of
regions is large; avoid multi-writer replication.

**Evidence to produce for the regulator.** A data flow register, replication
topology, backup and key locations, access logs, and tested controls preventing
cross-border replication.
**What would change it.** Customers transacting across countries, or a global
shared inventory: then the "global, frequently written" problem must be
designed explicitly.

### W3. A business unit wants to adopt a different database product for a new system. How do you decide?

**Answer.** Start from weighted requirements and constraints, not from the
product. Check the incumbent against them honestly. Shortlist on hard
constraints. Run a proof of concept on the real workload, including failure,
backup/restore and upgrade. Compare five-year total cost including skills,
tooling, security review, on-call and exit. Decide in an ADR with revisit
triggers. If approved, bring it onto the same platform standards (backup,
monitoring, patching, access) from day one.

**Principle.** A second engine has a fixed organizational cost; it is justified
by a requirement the incumbent does not meet well, not by a preference.
**Common weak answer.** "We only use X" or "let every team choose".

## Strategy and economics

| # | Question | What a strong answer covers |
|---|---|---|
| 1 | How do you build a three-year database roadmap? | Outcomes not technologies; risk removal first; support timelines; capacity; cost; decisions needed, with owners and dates. |
| 2 | How do you decide between renewing an unlimited licence agreement and moving to cloud licence-included? | Five-year TCO under growth scenarios; certification and exit positions; migration cost and risk; separating licence from platform decisions. |
| 3 | When is cloud not cheaper? | Steady, well-utilized workloads lifted without right-sizing; egress-heavy designs; when on-premises support costs continue in parallel. |
| 4 | How do you justify a DR investment? | Expected loss (probability × impact) against cost; regulatory duty; evidence from tests and past incidents. |
| 5 | How do you measure a database platform team? | Availability and recovery evidence, lead time and failure rate of changes, patch currency, cost per unit of workload, customer satisfaction. |
| 6 | What is your approach to vendor lock-in? | Quantify exit cost; use standards where cheap; accept lock-in knowingly where the feature value exceeds it; keep data portable and tested. |
| 7 | How do you forecast capacity for an uncertain business? | Driver-based model, scenarios, lead times, quarterly correction against actuals. |
| 8 | How do you prioritize technical debt against features? | Cost of delay, risk and effort; a fixed capacity share; tie to roadmap events. |

## Architecture and governance

| # | Question | What a strong answer covers |
|---|---|---|
| 9 | What belongs in an architecture decision record? | Context, options, decision, rationale, consequences accepted, revisit triggers. |
| 10 | How do you balance standards with team autonomy? | A small menu of supported options, a paved road, time-limited exceptions with owners, and learning from exception patterns. |
| 11 | How do you run a design review that people value? | Early, checklist-based, focused on risks with owners; reviewers accountable for speed. |
| 12 | How do you choose between a converged database and specialized stores? | Requirement fit, consistency and security benefits of one engine, versus scale or feature needs that justify another system's fixed cost. |
| 13 | Describe four multi-region data patterns. | Single writer with passive DR; read-local replicas; partitioned writers; multi-writer. Use the simplest that meets the need. |
| 14 | How do you explain eventual consistency to a product owner? | In user-visible behaviors: what a customer sees after a write, during failover, and under partition. |
| 15 | How do you tier systems for availability? | Business impact analysis to RTO/RPO per tier; a standard architecture and price per tier. |
| 16 | How do you design for ransomware? | Immutable, isolated backups with retention beyond dwell time; restore tests in a clean room; separation of duties; detection. |
| 17 | What is data governance in practice? | Ownership, classification, catalog and lineage, quality rules, access policy and lifecycle, implemented as defaults in pipelines. |
| 18 | How do you implement the right to erasure with seven-year tax retention? | Separate personal attributes from commercial records; anonymize; document legal bases; cover replicas, warehouses and backups by policy. |
| 19 | How do you approach modernizing a 20-year-old schema that many systems read directly? | Discover consumers; put views or APIs in front; strangle capability by capability; CDC bridge; never big-bang. |
| 20 | When do you say no to active-active? | When a tested failover meets the requirement; when data has global write hot spots or cross-row invariants. |

## Leadership and judgment

| # | Question | What a strong answer covers |
|---|---|---|
| 21 | Tell me about a decision you got wrong. | The reasoning at the time, the signal you missed, the cost, and what you changed in your process. |
| 22 | How do you handle an outage that is your platform's fault? | Restore, communicate plainly, blameless review, owned actions, report on completion. |
| 23 | Two senior engineers disagree on a design. What do you do? | Make the criteria explicit, get evidence (prototype, test), decide, record, and set a revisit trigger. |
| 24 | How do you present risk to a board? | Likelihood, impact in business terms, current controls, options with cost, and a recommendation. |
| 25 | How do you grow database skills in application teams? | Golden paths, reviews as teaching, shared incident learning, embedded specialists for a time. |
| 26 | How do you evaluate an AI feature request such as natural-language queries on production data? | Use case and value, data exposure and access control, accuracy and guardrails, cost, and a limited pilot with measurement. |
| 27 | What would make you recommend staying on the current platform? | It meets requirements, the migration return is negative or uncertain, and risk reduction is achievable in place. |
| 28 | How do you keep an estate patch-current? | Standard images, automation, a maximum-age policy, visibility of exceptions, and executive backing for maintenance windows. |
| 29 | How do you know when an architecture has outlived its assumptions? | Revisit triggers in ADRs, rising exceptions and incidents, capacity model divergence, changed business model. |
| 30 | What is the first thing you do in a new organization? | Inventory and risk: what exists, who owns it, can it be recovered, how current is it. Then listen before changing. |
