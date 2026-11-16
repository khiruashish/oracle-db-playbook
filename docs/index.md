---
title: Home
description: A sequential, zero-to-architect Oracle Database study path built around one real application.
---

# Oracle Database Production Engineering Playbook

A study path that starts at "what is a table?" and ends at multi-region
architecture reviews. Every chapter builds on the one before it, and every
example uses the same application: **FreshMart**, an online grocery store.

[Start with the study plan :material-arrow-right:](getting-started/study-plan.md){ .md-button .md-button--primary }
[Set up your lab database](getting-started/setup.md){ .md-button }

## How the playbook is organized

| Stage | Audience | What you can do at the end | Chapters |
|---|---|---|---|
| [1 · Foundations](getting-started/stage-1.md) | New to databases | Design a small schema, write CRUD SQL, joins and constraints | 1.1 to 1.11 |
| [2 · Developer](getting-started/stage-2.md) | About 5 years | Write analytic SQL and PL/SQL, design indexes, read plans | 2.1 to 2.15 |
| [3 · Senior DBA](getting-started/stage-3.md) | About 10 years | Run, back up, secure, tune and keep a database available | 3.1 to 3.9 |
| [4 · Principal](getting-started/stage-4.md) | About 15 years | Design HA/DR, replication, integration and delivery pipelines | 4.1 to 4.9 |
| [5 · Architect](getting-started/stage-5.md) | About 20 years | Choose platforms, set strategy, govern a database estate | 5.1 to 5.3 |

Alongside the stages:

- **[FreshMart project](grocery-application/index.md)**: requirements, ER model, full schema, 20 business queries, scaling from 10K to 10M customers, production architecture.
- **[Operations](production-runbooks/index.md)**: DBA runbooks, twelve worked performance incidents, production standards with DO / DON'T tables.
- **[Practice](hands-on-labs/index.md)**: labs for every stage and interview question banks for five experience levels.

## What is verified and what is not

!!! warning "Read this before you trust an example"
    This repository was built without access to an Oracle instance.

    - **Query results** printed in the chapters are computed from the sample data
      and cross-checked by `tests/verify_outputs.py`, which replays the standard-SQL
      queries against a SQLite copy of the same rows. Results that are not covered
      by that script are labeled *illustrative*.
    - **Oracle syntax, execution plans, wait-event figures and command output**
      have **not** been executed. Plans and DBA command output are always
      illustrative: your object names, costs and row counts will differ.
    - Run `sql/grocery-application/install.sql` on your own database
      ([setup guide](getting-started/setup.md)); its last step prints PASS/FAIL for
      the numbers this playbook relies on.

## Version baseline

The baseline is **Oracle AI Database 26ai** (release 23.26.x, the successor name
of 23ai). Anything that does not work on 19c is marked with the release that
introduced it, for example :material-tag: **23ai+**. See
[Versions, editions and licensing](getting-started/versions.md).

## Building this site

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
mkdocs serve          # preview on http://127.0.0.1:8000
mkdocs build --strict # fail on broken links or nav entries
```
