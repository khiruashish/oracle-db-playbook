---
tags: [meta]
---

# Master prompt: review and revised version

The playbook was generated from a "master prompt". This page records what was
checked in that prompt, what was changed and why, and the revised prompt to use
for future extensions.

## Review findings

| # | Finding in the original prompt | Problem | Change |
|---|---|---|---|
| 1 | The entire prompt was pasted **twice** (the second copy starts mid-line after "generating content quickly.") | Doubles the input and risks contradictory edits | Deduplicated |
| 2 | No single **reading order**. Five "independent" paths, but the user's goal is to study one chapter after another | A learner cannot tell what to read next | One numbered path (1.1 to 5.3); the five levels become its five stages, each with prerequisites and an exit test |
| 3 | "Every topic and every subtopic must follow" a 17-section template, alongside "no repeated filler content" | The two rules conflict: forcing 17 sections on small subtopics produces filler | Tiered template: a fixed chapter shape (at a glance, short sections, FreshMart example tab, check yourself, related); the full set of concerns applied per chapter, not per subtopic |
| 4 | Interview banks of 100 / 150 / 200 / 150 / 100 with seven parts per question (700 fully worked questions) | Not achievable at consistent quality in one pass; invites padding | A smaller bank per level with model answers, a few fully worked questions per level, and a stated count. Extension format defined |
| 5 | "Never fabricate execution results" **and** "Expected output: show the actual expected output" with no database assumed | Without a database, outputs cannot be "actual" | Explicit verification policy: small sample data; results derived from it and cross-checked by a script; everything not executed on Oracle is labeled; plans and command output are always illustrative |
| 6 | "Use Oracle AI Database 26ai as the baseline" without explaining the release | 26ai is delivered as a release update of the 23ai code line (23.26.x); features arrive per RU and per platform | Baseline stated precisely; version markers per feature; a versions and licensing chapter; RU-specific features flagged for confirmation |
| 7 | 21c listed as an equal target | 21c was an innovation release with a short support window | Covered for history and feature origin; not presented as a deployment target |
| 8 | "Spring Boot 3.x" fixed | Spring Boot 4 has since been released | Concepts taught on 3.x with a note to check the current major version |
| 9 | "Latest stable Material for MkDocs" | The project is in maintenance mode (last feature release 9.7; successor Zensical) | Pin a tested version range; avoid plugins that need extra system libraries; note the successor |
| 10 | Section 4-V mixes real features with marketing phrases ("AI-assisted application development", "AI-powered database operations") | Not testable topics | Mapped to concrete features (Select AI, automatic indexing, real-time SPM) with availability caveats |
| 11 | Suggested 35 documentation directories, some overlapping (transactions and concurrency; high-availability and disaster-recovery; relational-theory and database-fundamentals; oracle-sql and advanced-sql) | Fragmentation | Merged overlapping folders; added `database-objects`, `enterprise-architecture`, `standards` |
| 12 | "Assertions and their version-specific availability" | Correct to flag: `CREATE ASSERTION` is not available before the 26ai release updates | Kept, with alternatives for 19c to 23ai |
| 13 | Deliverables list `LICENSE` without naming one | Ambiguous | MIT chosen for the playbook's own content; change it if you prefer another |
| 14 | No instruction about destructive commands in labs | Risk | Lab-only warnings and a standard "danger" box |
| 15 | Phase 6 asks for sizing at four scales and warns not to assume RAC or sharding | Good requirement, kept | Implemented as an explicit, assumption-driven model |

## Revised master prompt

Use this version to regenerate or extend the playbook.

```text
ROLE
Act as an Oracle Database principal architect, DBA, SQL and PL/SQL expert,
performance engineer, security architect, data modeler and technical author.

GOAL
Maintain a sequential Oracle Database study path, from no database knowledge to
enterprise architect, as an MkDocs (Material) site. A learner reads chapters in
numbered order; each chapter depends only on earlier ones.

STRUCTURE
- One path in five stages: 1 Foundations (0 years), 2 Developer (5), 3 Senior
  DBA (10), 4 Principal (15), 5 Architect (20). Each stage has a landing page
  with goals, reading order and an exit test.
- Alongside the path: the FreshMart project (analysis, model, implementation,
  20 business queries, scaling 10K to 10M customers, production architecture),
  operations (runbooks, performance incidents, standards), practice (labs,
  interview banks), glossary, references.
- Cover the relational discipline as a whole (theory, modeling, normalization,
  SQL, integrity, indexing, transactions, PL/SQL, architecture, storage,
  objects, partitioning, performance, administration, backup and recovery,
  HA/DR, security, integration, warehousing, distributed data, 26ai features,
  application integration, DevOps), not only Oracle syntax.

CHAPTER FORMAT (W3Schools-like, but deeper)
1. Chapter card: stage, prerequisites, time, applicable releases, licence notes.
2. "At a glance": the topic in two sentences and a table of its subtopics.
3. Short sections, each: plain explanation, syntax, a FreshMart example, result.
4. For the chapter as a whole, where relevant: how Oracle does it internally,
   real-world use, trade-offs, performance, security, production guidance,
   common mistakes. Do not force a section that would only repeat generalities.
5. "FreshMart example": one content-tab block (Scenario / SQL / Result /
   Takeaway) that applies the chapter to the project.
6. "Check yourself": interview questions (beginner to architect) and exercises
   with solutions.
7. "Related": next chapter and deeper links.

VERSIONS
- Baseline: Oracle AI Database 26ai (release 23.26.x, the successor of 23ai).
- Everything unmarked must work on 19c. Mark later features with the release
  that introduced them; for 26ai, say that features arrive per release update
  and must be confirmed in the New Features Guide.
- State edition, platform and option/pack requirements for every feature that
  has them. Name deprecated and desupported features and their replacements.
- Distinguish standard SQL, Oracle-specific SQL and PL/SQL.

EXAMPLES AND VERIFICATION
- One sample schema (20 FreshMart tables) with deliberately small data so that
  results can be checked by hand. Scripts live under sql/ and are included in
  pages by snippet, never copied.
- A test script cross-checks documented results against the sample data without
  Oracle. Label each result as verified by that script, derived by hand, or
  illustrative. Never present unexecuted output as executed.
- Execution plans, timings, wait figures and DBA command output are always
  labeled illustrative unless captured from a real run.
- Where an Oracle instance is available, run sql/grocery-application/install.sql
  and the examples, and replace labels with real results.

SAFETY
- Destructive commands appear in a danger box with the required backup,
  approval and scope. Labs that destroy data say so at the top.
- No real passwords, hosts or personal data. Use example.com addresses.

QUALITY
- Plain language first; define every term on first use; depth grows by stage.
- No filler, no repeated boilerplate, no unsupported syntax, no performance
  claims without stated assumptions.
- Stage 4 and 5 chapters must contain options, trade-offs, costs, failure
  scenarios and a recorded decision, not feature lists.

INTERVIEW BANKS AND LABS
- Per level: a set of questions with model answers, and at least three fully
  worked questions (answer, explanation, SQL or scenario, follow-ups, common
  wrong answer). State the real count. Add SQL coding, debugging and
  plan-reading challenges on FreshMart data.
- Labs per stage with: objective, prerequisites, setup, steps, expected
  results, validation, challenge, solution, further exploration.

RUNBOOKS
- For each operational task: objective, prerequisites, privileges, commands,
  expected output, verification, rollback, troubleshooting, safety warnings.

BUILD
- mkdocs.yml with Material features (tabs, sections, instant navigation,
  search, code copy and annotations, light/dark, tags, Mermaid, admonitions,
  content tabs, snippets). Pin a tested version range in requirements.txt.
- `mkdocs build --strict` must pass: no broken links, no missing nav targets.
- README with install, preview, build, test and deploy commands.

WORKING METHOD
- Work stage by stage. After each stage: update navigation, run the checks,
  build, commit. When extending, continue from the last completed chapter and
  never rewrite completed work without a reason.

DEFINITION OF DONE
- Every nav entry exists and builds; every stage has a landing page and exit
  test; FreshMart installs from one script; verification status is stated on
  the home page; references are linked.
```

## What this edition does not contain

Stated plainly, so that nobody relies on something that is not there:

| Item requested originally | Status in this edition |
|---|---|
| Results executed on an Oracle database | **Not done.** No Oracle instance was available. Results are computed from the sample data; a script verifies the standard-SQL ones |
| 700 interview questions, each with seven parts | 271 questions; 23 fully worked; the rest with model answers |
| The 17-section template on every subtopic | Replaced by the chapter format above |
| A separate chapter for every bullet in section 4 of the prompt | Each bullet is covered inside one of the 47 study chapters; depth varies, with the most on SQL, transactions, indexing, performance, backup and HA |
| Java project source tree | Code excerpts in chapter 4.8, not a buildable project |
| Terraform and Kubernetes manifests | Illustrative fragments in chapters 4.9 and 5.1 |
| Version switcher for the site (for example `mike`) | Not configured; version differences are handled inline |
