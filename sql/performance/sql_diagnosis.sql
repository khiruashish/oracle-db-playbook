-- SQL performance diagnosis from the cursor cache (no pack licence needed).
-- Queries on DBA_HIST_* and V$ACTIVE_SESSION_HISTORY need the Diagnostics Pack.
-- Not executed in this repository.

-- --8<-- [start:topsql]
SELECT sql_id, plan_hash_value, executions,
       ROUND(elapsed_time / 1e6)                              AS elapsed_s,
       ROUND(elapsed_time / NULLIF(executions, 0) / 1000, 1)  AS ms_per_exec,
       ROUND(buffer_gets  / NULLIF(executions, 0))            AS gets_per_exec,
       ROUND(rows_processed / NULLIF(executions, 0), 1)       AS rows_per_exec,
       SUBSTR(sql_text, 1, 80)                                AS sql_text
FROM   v$sqlstats
ORDER  BY elapsed_time DESC
FETCH  FIRST 20 ROWS ONLY;
-- --8<-- [end:topsql]

-- --8<-- [start:onesql]
-- One statement: every child cursor and plan
SELECT child_number, plan_hash_value, executions, is_bind_sensitive, is_bind_aware,
       ROUND(elapsed_time / NULLIF(executions, 0) / 1000, 1) AS ms_per_exec,
       ROUND(buffer_gets  / NULLIF(executions, 0))           AS gets_per_exec,
       last_active_time
FROM   v$sql WHERE sql_id = :sql_id ORDER BY child_number;

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR(:sql_id, NULL, 'ALLSTATS LAST +PEEKED_BINDS'));

-- Why are there many child cursors?
SELECT * FROM v$sql_shared_cursor WHERE sql_id = :sql_id;
-- --8<-- [end:onesql]

-- --8<-- [start:literals]
-- Statements that differ only by literals (candidates for bind variables)
SELECT force_matching_signature, COUNT(*) AS versions,
       SUM(executions) AS executions, MIN(sql_text) AS sample_text
FROM   v$sql
WHERE  force_matching_signature <> 0
GROUP  BY force_matching_signature
HAVING COUNT(*) > 50
ORDER  BY versions DESC;

SELECT name, value FROM v$sysstat
WHERE  name IN ('parse count (total)', 'parse count (hard)', 'execute count', 'user commits');
-- --8<-- [end:literals]

-- --8<-- [start:waits]
-- Current activity by wait class
SELECT NVL(wait_class, 'CPU') AS wait_class, NVL(event, 'ON CPU') AS event, COUNT(*) AS sessions
FROM   v$session
WHERE  type = 'USER' AND status = 'ACTIVE'
GROUP  BY wait_class, event ORDER BY sessions DESC;

-- Diagnostics Pack: last 15 minutes from ASH
SELECT sql_id, NVL(event, 'ON CPU') AS event, COUNT(*) AS seconds
FROM   v$active_session_history
WHERE  sample_time > SYSTIMESTAMP - INTERVAL '15' MINUTE
GROUP  BY sql_id, event ORDER BY seconds DESC FETCH FIRST 15 ROWS ONLY;
-- --8<-- [end:waits]
