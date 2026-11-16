-- Space, undo, redo and archive monitoring. Read-only queries. Not executed in this repository.

-- --8<-- [start:tablespace]
SELECT m.tablespace_name,
       ROUND(m.used_space      * t.block_size / 1073741824, 1) AS used_gb,
       ROUND(m.tablespace_size * t.block_size / 1073741824, 1) AS max_gb,
       ROUND(m.used_percent, 1)                                AS pct_of_max
FROM   dba_tablespace_usage_metrics m
JOIN   dba_tablespaces t ON t.tablespace_name = m.tablespace_name
ORDER  BY m.used_percent DESC;

SELECT file_id, tablespace_name, file_name,
       ROUND(bytes / 1073741824, 1) AS size_gb, autoextensible,
       ROUND(maxbytes / 1073741824, 1) AS max_gb
FROM   dba_data_files ORDER BY tablespace_name, file_id;

-- Temporary tablespace use by session
SELECT s.sid, s.username, s.sql_id, u.tablespace, u.segtype,
       ROUND(u.blocks * 8192 / 1048576) AS mb
FROM   v$tempseg_usage u JOIN v$session s ON s.saddr = u.session_addr
ORDER  BY u.blocks DESC;
-- --8<-- [end:tablespace]

-- --8<-- [start:undo]
SELECT tablespace_name, status, ROUND(SUM(bytes) / 1048576) AS mb
FROM   dba_undo_extents GROUP BY tablespace_name, status ORDER BY 1, 2;

-- Undo generation, longest query and ORA-01555 count per 10-minute interval
SELECT begin_time, undoblks, maxquerylen AS longest_query_s,
       ssolderrcnt AS ora_1555, nospaceerrcnt AS no_space, tuned_undoretention
FROM   v$undostat ORDER BY begin_time DESC FETCH FIRST 24 ROWS ONLY;

-- Transactions holding the most undo
SELECT s.sid, s.serial#, s.username, t.start_time, t.used_ublk, t.used_urec, s.sql_id
FROM   v$transaction t JOIN v$session s ON s.taddr = t.addr
ORDER  BY t.used_ublk DESC;
-- --8<-- [end:undo]

-- --8<-- [start:redo]
SELECT group#, thread#, sequence#, ROUND(bytes / 1048576) AS mb, members, status, archived
FROM   v$log ORDER BY thread#, group#;

-- Log switches per hour (target: single digits at peak)
SELECT TRUNC(first_time, 'HH24') AS hour, COUNT(*) AS switches
FROM   v$log_history
WHERE  first_time > SYSDATE - 2
GROUP  BY TRUNC(first_time, 'HH24') ORDER BY 1 DESC;

-- Sessions generating the most redo since logon
SELECT s.sid, s.username, s.program, ROUND(st.value / 1048576) AS redo_mb
FROM   v$sesstat st
JOIN   v$statname n ON n.statistic# = st.statistic#
JOIN   v$session s  ON s.sid = st.sid
WHERE  n.name = 'redo size' AND st.value > 0
ORDER  BY st.value DESC FETCH FIRST 10 ROWS ONLY;
-- --8<-- [end:redo]

-- --8<-- [start:archive]
SELECT name, ROUND(space_limit / 1073741824, 1) AS limit_gb,
       ROUND(space_used / 1073741824, 1)        AS used_gb,
       ROUND(space_reclaimable / 1073741824, 1) AS reclaimable_gb,
       ROUND(100 * (space_used - space_reclaimable) / space_limit, 1) AS pct_unreclaimable
FROM   v$recovery_file_dest;

SELECT file_type, percent_space_used, percent_space_reclaimable, number_of_files
FROM   v$recovery_area_usage;

-- Archived redo generated per day
SELECT TRUNC(completion_time) AS day, ROUND(SUM(blocks * block_size) / 1073741824, 1) AS gb
FROM   v$archived_log
WHERE  completion_time > SYSDATE - 14 AND dest_id = 1
GROUP  BY TRUNC(completion_time) ORDER BY 1 DESC;
-- --8<-- [end:archive]
