-- FreshMart one-step install. Run with SQLcl or SQL*Plus from the repository root:
--
--   sql freshmart@//localhost:1521/FREEPDB1 @sql/grocery-application/install.sql
--
-- The script stops at the first error so that a half-built schema is obvious.

WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK
SET ECHO OFF FEEDBACK ON DEFINE OFF

PROMPT == 1/5 tables, constraints, indexes
@@../schema/01_tables.sql

PROMPT == 2/5 sample data
@@../sample-data/01_sample_data.sql

PROMPT == 3/5 identity reset
@@../schema/02_identity_reset.sql

PROMPT == 4/5 PL/SQL (views, triggers, packages)
@@../plsql/01_views.sql
@@../plsql/02_triggers.sql
@@../plsql/03_order_pkg.sql

PROMPT == 5/5 verification
@@verify.sql

PROMPT FreshMart installed.
