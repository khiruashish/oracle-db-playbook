# Oracle Database Production Engineering Playbook

A sequential study path for Oracle Database, from "what is a table?" to
multi-region architecture reviews, built as an MkDocs Material site around one
sample application (FreshMart, an online grocery store).

- **Baseline:** Oracle AI Database 26ai (23.26.x), with 19c / 21c / 23ai differences marked.
- **Start reading:** `docs/getting-started/study-plan.md` (or the site's "Study plan" page).

## What is in the repository

| Path | Content |
|---|---|
| `docs/` | The site: 5 stages (47 chapters), FreshMart project, runbooks, incidents, standards, labs, interview banks, glossary, references |
| `sql/schema`, `sql/sample-data`, `sql/plsql` | FreshMart tables, sample rows, views, triggers, `ORDER_PKG` |
| `sql/grocery-application` | One-step install and verification scripts |
| `sql/queries` | 20 business queries |
| `sql/administration`, `sql/performance`, `sql/backup-recovery` | DBA, diagnosis and RMAN scripts used by the runbooks |
| `diagrams/` | Mermaid sources for the ER and architecture diagrams |
| `tests/` | Checks: documented results versus sample data; table formatting |
| `scripts/` | Build helper |

## Verification status

No Oracle instance was available when this was written.

- Query results marked *verified* are reproduced by `tests/verify_outputs.py` against a SQLite copy of the sample data.
- Oracle SQL, PL/SQL, RMAN, shell and Java examples follow documented syntax but **have not been executed**. Plans and command output are illustrative.
- Install FreshMart on your own database and run the examples before relying on them.

## Read the site locally

```bash
python -m venv .venv
```

```bash
source .venv/bin/activate
```

```bash
pip install -r requirements.txt
```

```bash
mkdocs serve
```

Open <http://127.0.0.1:8000>.

## Build and test

```bash
./scripts/build.sh
```

This runs the result checks, the formatting check and `mkdocs build --strict`
(which fails on broken links or missing navigation targets). Output goes to
`site/`.

The same script runs in GitHub Actions on every pull request and on pushes to
`main` (`.github/workflows/docs.yml`), and uploads the built site as an artifact.

## Install the FreshMart sample database

Needs an Oracle database (19c or later) and SQLcl or SQL*Plus. Full
instructions: `docs/getting-started/setup.md`.

```bash
sql system@//localhost:1521/FREEPDB1 @sql/grocery-application/00_create_user.sql
```

```bash
cd sql/grocery-application && sql freshmart@//localhost:1521/FREEPDB1 @install.sql
```

The last step prints `PASS`/`FAIL` lines for the figures the documentation uses.

## Deploy

The site is published to GitHub Pages by the `Docs` workflow
(`.github/workflows/docs.yml`): every push to `main` runs the checks, builds
the site and deploys it to <https://khiruashish.github.io/oracle-db-playbook/>.
The workflow can also be started by hand from the Actions tab.

One-time repository setting: **Settings → Pages → Build and deployment →
Source: GitHub Actions**. Until that is set, the deploy job fails and the build
job still passes.

Any other static host works too: publish the `site/` directory.

## Tooling notes

Tested with MkDocs 1.6 and Material for MkDocs 9.8 on Python 3.13. Material
for MkDocs is in maintenance mode; its successor, Zensical, reads `mkdocs.yml`.

## Licence

MIT for the playbook's own text and scripts (see `LICENSE`). Oracle is a
registered trademark of Oracle and/or its affiliates; this project is not
affiliated with Oracle.
