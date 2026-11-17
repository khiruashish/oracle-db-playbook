-- Session, blocking and long-running SQL investigation. Read-only queries.
-- Needs SELECT on V$ views (SELECT_CATALOG_ROLE or specific grants). Not executed in this repository.

-- --8<-- [start:sessions]
SELECT s.sid, s.serial#, s.username, s.status, s.sql_id, s.event, s.wait_class,
       s.seconds_in_wait, s.blocking_session, s.machine, s.program, s.module, s.logon_time
FROM   v$session s
WHERE  s.type = 'USER'
ORDER  BY s.status, s.seconds_in_wait DESC;

-- Sessions per user and status
SELECT username, status, COUNT(*) AS sessions
FROM   v$session WHERE type = 'USER'
GROUP  BY username, status ORDER BY sessions DESC;
-- --8<-- [end:sessions]

-- --8<-- [start:blockers]
-- Blocking tree: root blockers first
SELECT LPAD(' ', 2 * (LEVEL - 1)) || s.sid || ',' || s.serial# AS session_tree,
       s.username, s.status, s.sql_id, s.event, s.seconds_in_wait, s.machine, s.program
FROM   v$session s
WHERE  s.sid IN (SELECT blocking_session FROM v$session WHERE blocking_session IS NOT NULL)
OR     s.blocking_session IS NOT NULL
START  WITH s.blocking_session IS NULL
CONNECT BY PRIOR s.sid = s.blocking_session
ORDER  SIBLINGS BY s.sid;

-- What the root blocker has locked, and for how long its transaction has been open
SELECT s.sid, s.serial#, s.username, t.start_time, t.used_urec AS undo_records,
       o.owner, o.object_name, l.locked_mode
FROM   v$session s
JOIN   v$transaction t   ON t.addr = s.taddr
JOIN   v$locked_object l ON l.session_id = s.sid
JOIN   dba_objects o     ON o.object_id = l.object_id
WHERE  s.sid = :blocker_sid;
-- --8<-- [end:blockers]

-- --8<-- [start:longsql]
-- Statements running longer than 60 seconds right now
SELECT s.sid, s.serial#, s.username, s.sql_id, s.sql_child_number,
       ROUND((SYSDATE - s.sql_exec_start) * 86400) AS running_seconds,
       s.event, q.executions, q.buffer_gets, q.disk_reads, SUBSTR(q.sql_text, 1, 100) AS sql_text
FROM   v$session s
JOIN   v$sql q ON q.sql_id = s.sql_id AND q.child_number = s.sql_child_number
WHERE  s.status = 'ACTIVE' AND s.type = 'USER'
AND    s.sql_exec_start < SYSDATE - 60 / 86400
ORDER  BY running_seconds DESC;

-- Progress of long operations (scans, sorts, RMAN)
SELECT sid, serial#, opname, target, sofar, totalwork,
       ROUND(100 * sofar / NULLIF(totalwork, 0), 1) AS pct_done, time_remaining
FROM   v$session_longops
WHERE  sofar < totalwork;

-- The plan actually in use
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR(sql_id => :sql_id, format => 'TYPICAL'));
-- --8<-- [end:longsql]
