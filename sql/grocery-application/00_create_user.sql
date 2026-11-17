-- Create the FRESHMART schema owner. Run as a privileged user (for example
-- SYSTEM or the PDB admin) while connected to a PDB such as FREEPDB1.
-- Replace the password at the prompt: never commit real passwords.

ACCEPT fm_password CHAR PROMPT 'Password for FRESHMART: ' HIDE

CREATE USER freshmart IDENTIFIED BY "&fm_password"
    DEFAULT TABLESPACE users
    TEMPORARY TABLESPACE temp
    QUOTA 500M ON users;

-- Least privilege: only what a schema owner needs to build the application.
GRANT CREATE SESSION, CREATE TABLE, CREATE VIEW, CREATE SEQUENCE,
      CREATE PROCEDURE, CREATE TRIGGER, CREATE TYPE,
      CREATE MATERIALIZED VIEW, CREATE SYNONYM, CREATE JOB
TO freshmart;

-- 23ai/26ai alternative: one role that bundles the developer privileges.
-- GRANT DB_DEVELOPER_ROLE TO freshmart;
