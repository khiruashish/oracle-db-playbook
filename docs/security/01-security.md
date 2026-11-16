---
tags: [stage-3, security]
---

# 3.5 Security

!!! abstract "Chapter card"
    **Stage:** 3 · **Prerequisites:** 3.3 · **Time:** 6 hours · **Applies to:** 19c+ (23ai items marked)

## At a glance

| Layer | Subtopics |
|---|---|
| Who are you? | Authentication, password management, centrally managed users |
| What may you do? | System and object privileges, roles, least privilege, schema privileges |
| Which rows and columns? | VPD, Data Redaction, Label Security, Real Application Security |
| Protecting data at rest and in motion | TDE, key management, TLS and network encryption |
| Controlling administrators | Database Vault, separation of duties, privileged access |
| Seeing what happened | Unified Auditing |
| Application threats | SQL injection, SQL Firewall |
| Non-production and discovery | Data masking, sensitive data discovery |
| Hardening and compliance | Baselines, assessment tools |

:material-license: Several features are extra-cost options: **Advanced Security**
(TDE, Redaction), **Database Vault**, **Label Security**, **Data Masking and
Subsetting Pack**. Check [versions and licensing](../getting-started/versions.md).

## 1. Authentication

| Method | Use |
|---|---|
| Password (verifier in the database) | Application service accounts, simple setups |
| OS / wallet (Secure External Password Store) | Scripts without clear-text passwords |
| Kerberos, PKI certificates | Enterprise single sign-on |
| **Centrally Managed Users** (Active Directory, 18c+) | People authenticate with directory credentials and map to shared schemas and roles |
| Cloud IAM / Microsoft Entra ID tokens | Cloud and :material-tag: **23ai+** on-premises integrations |
| Proxy authentication | The pool user connects *as* the end user: `ALTER USER rahul GRANT CONNECT THROUGH fm_app` |
| `SYSDBA`, `SYSBACKUP`, `SYSDG`, `SYSKM`, `SYSRAC` | Administrative privileges authenticated by password file or OS group |

Password practice: case-sensitive verifiers at the 12c level only
(`SQLNET.ALLOWED_LOGON_VERSION_SERVER = 12a`), complexity through a verify
function, lockout on failures, **no shared personal accounts**, service account
secrets in a vault with rotation (gradual password rollover makes rotation
non-disruptive), and schema owners without a password
(`NO AUTHENTICATION`).

## 2. Authorization

| Kind | Example | Notes |
|---|---|---|
| **System privilege** | `CREATE SESSION`, `CREATE TABLE`, `SELECT ANY TABLE` | `ANY` privileges are powerful: avoid |
| **Object privilege** | `SELECT ON orders`, `EXECUTE ON order_pkg` | Granted by the owner |
| **Schema privilege** :material-tag: **23ai+** | `GRANT SELECT ANY TABLE ON SCHEMA freshmart TO reporting` | Covers current and future objects of one schema |
| **Role** | A named set of privileges | Enable by default or on demand (secure application roles) |

```sql
CREATE ROLE fm_read_role;
GRANT SELECT ON freshmart.v_order_summary TO fm_read_role;

CREATE ROLE fm_app_role;
GRANT EXECUTE ON freshmart.order_pkg TO fm_app_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON freshmart.carts      TO fm_app_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON freshmart.cart_items TO fm_app_role;
```

**Least privilege** in practice:

- The application account has `CREATE SESSION` plus object grants. No DDL, no `ANY` privileges, no `DBA`.
- Prefer `EXECUTE` on an API package over DML on tables.
- Avoid `WITH GRANT OPTION` / `WITH ADMIN OPTION`.
- Never grant to `PUBLIC`.
- **Privilege Analysis** (`DBMS_PRIVILEGE_CAPTURE`, included in EE from 19c) records which privileges are actually used, so unused ones can be revoked with evidence.
- `DB_DEVELOPER_ROLE` (:material-tag: **23ai+**) replaces the over-broad `CONNECT, RESOURCE` habit for developers.

Useful views: `DBA_SYS_PRIVS`, `DBA_TAB_PRIVS`, `DBA_ROLE_PRIVS`, `ROLE_SYS_PRIVS`,
`SESSION_PRIVS`, `DBA_SCHEMA_PRIVS`.

## 3. Row and column level control

### Virtual Private Database (VPD)

VPD (fine-grained access control, EE) appends a predicate to every statement on
a table, transparently.

```sql
CREATE OR REPLACE FUNCTION orders_by_warehouse (p_schema VARCHAR2, p_object VARCHAR2)
    RETURN VARCHAR2
IS
BEGIN
    IF SYS_CONTEXT('FM_CTX', 'ROLE') = 'HQ' THEN
        RETURN NULL;                                   -- no restriction
    END IF;
    RETURN 'warehouse_id = SYS_CONTEXT(''FM_CTX'', ''WAREHOUSE_ID'')';
END;
/
BEGIN
    DBMS_RLS.ADD_POLICY(
        object_schema   => 'FRESHMART',  object_name => 'ORDERS',
        policy_name     => 'ORDERS_WH_POLICY',
        function_schema => 'FRESHMART',  policy_function => 'ORDERS_BY_WAREHOUSE',
        statement_types => 'SELECT,UPDATE,DELETE',
        policy_type     => DBMS_RLS.CONTEXT_SENSITIVE);
END;
/
```

`FM_CTX` is an **application context** set by a trusted package at session
start. A warehouse manager's `SELECT * FROM orders` now silently returns only
that warehouse's rows. Column-level VPD can hide column values
(`sec_relevant_cols`).

Cautions: the predicate becomes part of every plan (index it); a policy
function that builds different text per user causes hard parsing; and with
connection pools the context must be **reset on every borrow** or one user
inherits another's rights.

### Other mechanisms

| Feature | What it does |
|---|---|
| **Data Redaction** | Masks column values in query *results* (full, partial, regex, random) for chosen sessions. The stored data is unchanged; it is not a control against a determined user with ad hoc SQL |
| **Oracle Label Security** | Row access by sensitivity labels and clearances |
| **Real Application Security** | Application users, roles and ACLs known to the database |
| **Views** | The simplest column and row restriction; combine with `WITH READ ONLY` |
| SQL-level row security in newer releases | Oracle has announced additional declarative data-security features in 26ai release updates; verify availability for your RU |

## 4. Encryption

### Transparent Data Encryption (TDE)

TDE encrypts data files, so that stolen disks, files or backups are unreadable.
It is transparent to SQL: authorized sessions see clear text. It does **not**
protect against a privileged or compromised database account.

| Level | Notes |
|---|---|
| **Tablespace encryption** | Everything in the tablespace, including indexes. The normal choice; AES-256, hardware-accelerated |
| Column encryption | Selected columns; restricts index types. Rarely the right choice now |

Key hierarchy: a **master encryption key** in a keystore (software wallet, or
better **Oracle Key Vault** or an HSM / cloud KMS) protects per-tablespace
keys. Each PDB can have its own keys (isolated mode).

```sql
ADMINISTER KEY MANAGEMENT SET KEYSTORE OPEN IDENTIFIED BY "...";
ADMINISTER KEY MANAGEMENT SET KEY IDENTIFIED BY "..." WITH BACKUP;
CREATE TABLESPACE fm_secure DATAFILE SIZE 10G ENCRYPTION USING 'AES256' ENCRYPT;
ALTER  TABLESPACE fm_data ENCRYPTION ONLINE USING 'AES256' ENCRYPT;     -- online conversion
```

Operations that matter: back up the keystore separately from the data, never
lose it, rotate the master key on a schedule, and remember that RMAN, Data
Guard, cloning and unplug/plug all need the keys. Oracle Cloud databases are
encrypted by default.

### Network encryption

- **TLS** (`TCPS`): standard, certificate-based, authenticates the server (and optionally the client). TLS 1.3 from :material-tag: **23ai**. The recommended approach.
- **Native network encryption** (`SQLNET.ENCRYPTION_SERVER = REQUIRED`): no certificates, easy to enable; no server authentication.

Set the server side to **required**, not merely *requested*, or a downgraded
client connects in clear text.

## 5. Controlling privileged users

A DBA with `SELECT ANY TABLE` can read every salary and card token. Controls:

| Control | Effect |
|---|---|
| **Database Vault** | *Realms* fence application schemas off from `ANY` privileges, including from SYS-like administrators; *command rules* restrict statements (no `DROP TABLE` outside a change window); separation of duties between DBA, security admin and account admin |
| Task-specific admin privileges | `SYSBACKUP` for backups, `SYSDG` for Data Guard, `SYSKM` for keys, instead of `SYSDBA` |
| Privileged access management | Named accounts, just-in-time elevation, session recording, break-glass procedure |
| PDB lockdown profiles | Restrict what a PDB administrator may do |
| Unified Auditing of administrators | Top-level SYS statements are always audited |

## 6. Auditing

**Unified Auditing** writes all audit records to one trail (`UNIFIED_AUDIT_TRAIL`,
stored in the `AUDSYS` schema). Traditional auditing is desupported from 23ai.

```sql
CREATE AUDIT POLICY fm_sensitive_access
    ACTIONS SELECT ON freshmart.customers, UPDATE ON freshmart.products,
            DELETE ON freshmart.orders
    WHEN 'SYS_CONTEXT(''USERENV'', ''SESSION_USER'') <> ''FM_APP'''
    EVALUATE PER SESSION;

AUDIT POLICY fm_sensitive_access;
AUDIT POLICY ORA_SECURECONFIG;        -- predefined: account, privilege and structure changes
AUDIT POLICY ORA_LOGON_FAILURES WHENEVER NOT SUCCESSFUL;

SELECT event_timestamp, dbusername, action_name, object_name, sql_text
FROM   unified_audit_trail
WHERE  unified_audit_policies LIKE '%FM_SENSITIVE_ACCESS%'
ORDER  BY event_timestamp DESC;
```

Design rules: audit **privileged users always**, security-relevant changes
always, and sensitive data access *outside* the application account. Do not
audit every statement of the application pool: you will create noise and
overhead and miss the signal. Ship the trail to a system the DBAs cannot edit
(Audit Vault, a SIEM), and purge with `DBMS_AUDIT_MGMT`. Column-level audit
policies arrive in :material-tag: **23ai**.

Value-change history ("who changed the price from 68 to 70") is a different
need: use application audit tables, Flashback Data Archive, or immutable /
blockchain tables.

## 7. SQL injection

The attack: user input changes the *structure* of a statement.

```java
// VULNERABLE
String sql = "SELECT * FROM customers WHERE email = '" + email + "'";
// email =  ' OR '1'='1   ->  returns every customer

// SAFE: the value is bound, never parsed as SQL
PreparedStatement ps = conn.prepareStatement("SELECT * FROM customers WHERE email = ?");
ps.setString(1, email);
```

Defenses in depth: bind variables everywhere; validated identifiers in dynamic
SQL ([2.10](../plsql/04-exceptions-dynamic-advanced.md)); least-privilege
accounts so a successful injection can do little; no detailed errors to end
users; and **SQL Firewall** (:material-tag: **23ai+**, part of the kernel),
which learns the application's normal statements and connection paths and then
logs or blocks anything else.

## 8. Non-production data

A copy of production is production data.

| Tool | Purpose |
|---|---|
| **Data Masking and Subsetting** | Irreversibly replaces sensitive values with realistic ones while keeping referential integrity; subsets large databases |
| Data Pump `REMAP_DATA` | Simple masking during export |
| **Sensitive data discovery** | Finds columns holding personal data: Data Safe (cloud), `DBMS_TSDP`, EM Application Data Modeling |
| **Data Safe** | Cloud service: assessment, user risk, discovery, masking, audit collection |
| **DBSAT** (Database Security Assessment Tool) | Free script that reports configuration, users and sensitive data findings |

## 9. Hardening checklist

- [ ] Latest release update applied; unused options and sample schemas removed.
- [ ] Default accounts locked and expired; no default passwords (`DBA_USERS_WITH_DEFPWD`).
- [ ] No grants to `PUBLIC` beyond the defaults; no `ANY` privileges for applications.
- [ ] `REMOTE_OS_AUTHENT = FALSE`; only strong password verifiers (`SQLNET.ALLOWED_LOGON_VERSION_SERVER = 12a`).
- [ ] Listener restricted: valid node checking, no external procedures unless needed, admin over local IPC only.
- [ ] TDE on all application tablespaces; keystore backed up and escrowed.
- [ ] Network encryption required.
- [ ] Unified Audit policies enabled and shipped off-host.
- [ ] Backups encrypted and immutable.
- [ ] Directory objects and `UTL_FILE`, `UTL_HTTP`, `DBMS_SCHEDULER` external jobs restricted; network ACLs minimal.
- [ ] CIS Benchmark / STIG assessed with DBSAT or equivalent, exceptions documented.

## 10. Compliance mapping

| Requirement (GDPR, PCI DSS, HIPAA, SOX, DPDP) | Database control |
|---|---|
| Encrypt personal / card data | TDE, TLS |
| Restrict access to need-to-know | Roles, VPD, Database Vault |
| Record access and changes | Unified Auditing, off-host trail |
| Mask data outside production | Data Masking |
| Right to erasure | Designed delete/anonymize procedures; mind backups and archives |
| Retention limits | Partition-based purge ([2.13](../partitioning/01-partitioning.md)) |
| Segregation of duties | Database Vault, PAM |

Compliance is evidence that controls operate, not the existence of features.

## 11. Common mistakes

- The application connects as the schema owner.
- `GRANT DBA` to make an error go away.
- TDE treated as access control.
- Encryption "requested" rather than "required".
- Auditing everything, reviewing nothing.
- Production data copied to test unmasked.
- VPD context not cleared in pooled connections.

## FreshMart example

=== "Scenario"

    FreshMart must pass a security review: customer personal data
    (`customers`, `addresses`) must be encrypted at rest, support staff may see
    only masked phone numbers, and any access by a human account must be
    recorded.

=== "SQL"

    ```sql
    -- 1. Accounts: owner cannot log in; app user has only what it needs
    ALTER USER freshmart NO AUTHENTICATION;
    CREATE USER fm_app IDENTIFIED BY "..." PROFILE app_profile;
    GRANT fm_app_role TO fm_app;

    -- 2. Encrypt at rest (Advanced Security option)
    ALTER TABLESPACE fm_data ENCRYPTION ONLINE USING 'AES256' ENCRYPT;

    -- 3. Support sees masked phone numbers (Data Redaction)
    BEGIN
        DBMS_REDACT.ADD_POLICY(
            object_schema => 'FRESHMART', object_name => 'CUSTOMERS',
            policy_name   => 'REDACT_CUSTOMER_PHONE',
            column_name   => 'PHONE',
            function_type => DBMS_REDACT.PARTIAL,
            function_parameters => 'VVVVFVVVVVVVVVV,VVVV-VVVVVVVVVV,*,5,10',
            expression    => q'[SYS_CONTEXT('SYS_SESSION_ROLES', 'FM_SUPPORT_ROLE') = 'TRUE']');
    END;
    /

    -- 4. Audit every non-application access to personal data
    CREATE AUDIT POLICY fm_pii_access
        ACTIONS ALL ON freshmart.customers, ALL ON freshmart.addresses
        WHEN 'SYS_CONTEXT(''USERENV'', ''SESSION_USER'') <> ''FM_APP''' EVALUATE PER SESSION;
    AUDIT POLICY fm_pii_access;
    ```

=== "Result"

    | Who | `SELECT customer_name, phone FROM customers WHERE customer_id = 101` |
    |---|---|
    | `fm_app` (the application) | `Rahul Sharma`, `+91-9800000101` |
    | A user with `FM_SUPPORT_ROLE` | `Rahul Sharma`, `+91-*****00101` and an audit record |
    | A stolen data file or backup | Unreadable without the keystore |

    Illustrative: the redaction format string must be adapted and tested for
    your data; verify `DBMS_REDACT` parameters in the Advanced Security Guide.

=== "Takeaway"

    Each control answers a different threat: TDE for stolen media, redaction
    for casual exposure, auditing for accountability, least privilege for
    everything else. None of them replaces the others.

## Check yourself

??? question "Interview questions"
    1. **(Intermediate)** System privilege versus object privilege versus role?
    2. **(Intermediate)** What does TDE protect against, and what not?
    3. **(Senior)** How does VPD work and what are its pitfalls with connection pools?
    4. **(Senior)** How do you audit DBAs so that they cannot erase the evidence?
    5. **(Architect)** Design database access for 40 microservices and 25 engineers. *One least-privilege account per service with secrets in a vault and rotation; no human standing access to production, just-in-time elevation with audit; schema owners without authentication; pipeline-only DDL; TDE, TLS required, unified audit shipped to a SIEM; Database Vault for regulated data.*

??? example "Exercises"
    1. Create `fm_app` and `fm_app_role` and prove the user cannot `DROP TABLE` or read `employees.salary`.
    2. Create a unified audit policy on `products` updates, change a price, and find the record.
    3. Run a Privilege Analysis capture during a test run and list unused privileges.

## Related

Next: [3.6 Optimizer, statistics, SPM](../performance-engineering/02-optimizer-statistics-spm.md).
