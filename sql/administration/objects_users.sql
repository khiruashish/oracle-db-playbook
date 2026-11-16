-- Invalid objects, users and privileges, index health. Not executed in this repository.

-- --8<-- [start:invalid]
SELECT owner, object_type, object_name, status, last_ddl_time
FROM   dba_objects
WHERE  status = 'INVALID' AND owner NOT IN ('SYS', 'SYSTEM')
ORDER  BY owner, object_type, object_name;

-- Compilation errors for one object
SELECT line, position, text FROM dba_errors
WHERE  owner = :owner AND name = :object_name ORDER BY sequence;

-- Recompile everything invalid in one schema (safe: only recompiles)
EXEC DBMS_UTILITY.COMPILE_SCHEMA(schema => 'FRESHMART', compile_all => FALSE)
-- --8<-- [end:invalid]

-- --8<-- [start:users]
SELECT username, account_status, profile, created, last_login, expiry_date, authentication_type
FROM   dba_users
WHERE  oracle_maintained = 'N' ORDER BY username;

-- Everything granted to one user or role
SELECT 'ROLE' AS kind, granted_role AS privilege, NULL AS on_object FROM dba_role_privs WHERE grantee = :grantee
UNION ALL
SELECT 'SYSTEM', privilege, NULL FROM dba_sys_privs WHERE grantee = :grantee
UNION ALL
SELECT 'OBJECT', privilege, owner || '.' || table_name FROM dba_tab_privs WHERE grantee = :grantee
ORDER  BY 1, 2;

-- Powerful privileges held by non-Oracle accounts
SELECT grantee, privilege FROM dba_sys_privs
WHERE  (privilege LIKE '%ANY%' OR privilege IN ('ALTER SYSTEM', 'ALTER DATABASE'))
AND    grantee NOT IN (SELECT username FROM dba_users WHERE oracle_maintained = 'Y')
AND    grantee NOT IN (SELECT role FROM dba_roles WHERE oracle_maintained = 'Y')
ORDER  BY grantee, privilege;
-- --8<-- [end:users]

-- --8<-- [start:indexes]
-- Unusable indexes and index partitions
SELECT owner, index_name, 'INDEX' AS kind, status FROM dba_indexes WHERE status = 'UNUSABLE'
UNION ALL
SELECT index_owner, index_name || ':' || partition_name, 'PARTITION', status
FROM   dba_ind_partitions WHERE status = 'UNUSABLE';

-- Invisible indexes, and indexes with a parallel degree left behind
SELECT owner, index_name, visibility, degree FROM dba_indexes
WHERE  owner = 'FRESHMART' AND (visibility = 'INVISIBLE' OR TRIM(degree) NOT IN ('1', '0'));

-- Foreign keys without a supporting index (leading columns must match)
SELECT c.table_name, c.constraint_name,
       LISTAGG(cc.column_name, ', ') WITHIN GROUP (ORDER BY cc.position) AS fk_columns
FROM   user_constraints c
JOIN   user_cons_columns cc ON cc.constraint_name = c.constraint_name
WHERE  c.constraint_type = 'R'
AND    NOT EXISTS (
         SELECT 1 FROM user_ind_columns ic
         WHERE  ic.table_name = c.table_name
         AND    ic.column_name = cc.column_name
         AND    ic.column_position = cc.position)
GROUP  BY c.table_name, c.constraint_name
ORDER  BY 1, 2;

-- Index usage (12.2+)
SELECT name, total_access_count, total_exec_count, last_used
FROM   dba_index_usage WHERE owner = 'FRESHMART' ORDER BY last_used NULLS FIRST;
-- --8<-- [end:indexes]
