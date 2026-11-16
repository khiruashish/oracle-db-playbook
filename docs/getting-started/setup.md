# Set up your lab database

You need one Oracle database you are allowed to break. Three free options:

| Option | Best for | Limits (check current docs) |
|---|---|---|
| **Oracle AI Database 26ai Free** in a container | Stages 1 to 3 on your laptop | Free edition caps CPU, memory and user data; no RAC or Data Guard |
| **Oracle LiveSQL** (browser) | Stage 1 and most of Stage 2 | No DBA access, no files, sessions expire |
| **OCI Always Free Autonomous Database** | Stages 1, 2 and parts of 4 | No SYSDBA, no OS access, managed backups |

RAC, Data Guard and GoldenGate (Stages 3 and 4) need more than the free edition.
Use Oracle's free LiveLabs workshops for those hands-on parts.

## Option 1: Free edition in a container

```bash
# Official image from Oracle Container Registry (accept the terms on the site first).
docker run -d --name oracle-free \
  -p 1521:1521 \
  -e ORACLE_PWD='ChangeMe_Lab_2026' \
  -v oracle-free-data:/opt/oracle/oradata \
  container-registry.oracle.com/database/free:latest

docker logs -f oracle-free    # wait for "DATABASE IS READY TO USE!"
```

The image creates a container database `FREE` with one pluggable database
`FREEPDB1`. Always work inside the PDB, not in the root container.

!!! note "Not executed here"
    These commands were not run while writing this playbook (no container
    runtime was available). They follow Oracle's published image usage; if a tag
    or variable name has changed, the image page on container-registry.oracle.com
    is authoritative.

## Install a client

Install **SQLcl** (`sql`, needs Java 17+) or use **SQL Developer for VS Code**.
SQL*Plus also works for every script here.

```bash
sql system@//localhost:1521/FREEPDB1
```

## Install FreshMart

```bash
# 1. Create the schema owner (prompts for a password)
sql system@//localhost:1521/FREEPDB1 @sql/grocery-application/00_create_user.sql

# 2. Build tables, load data, compile PL/SQL, verify
cd sql/grocery-application
sql freshmart@//localhost:1521/FREEPDB1 @install.sql
```

The final step prints one line per check. Every line must start with `PASS`:

```text
PASS customers                                actual=6 expected=6
PASS net merchandise value                    actual=3668 expected=3668
...
```

If a line says `FAIL`, your data differs from the documentation and printed
results will not match. Drop and reinstall:

!!! danger "Destructive: lab schema only"
    `sql/schema/99_drop_all.sql` drops all FreshMart tables with `PURGE`. There
    is no undo. Never point it at a shared or production schema.

## Check the client settings used in this playbook

```sql
ALTER SESSION SET nls_date_format = 'YYYY-MM-DD';
SET LINESIZE 200 PAGESIZE 100
```

Date output in the chapters assumes this `nls_date_format`. Production code must
never depend on session NLS settings: use `TO_CHAR` with an explicit format
(chapter [1.6](../sql-fundamentals/02-null-and-functions.md)).

## Next

Go to [Stage 1](stage-1.md).
