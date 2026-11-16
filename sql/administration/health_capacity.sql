-- Daily health check and capacity report. Read-only. Not executed in this repository.

-- --8<-- [start:health]
SELECT name, open_mode, database_role, log_mode, flashback_on, force_logging FROM v$database;
SELECT instance_name, status, startup_time, version_full FROM v$instance;
SELECT con_id, name, open_mode, restricted FROM v$pdbs;
SELECT COUNT(*) AS invalid_objects FROM dba_objects WHERE status = 'INVALID';
SELECT COUNT(*) AS failed_jobs_24h FROM dba_scheduler_job_run_details
WHERE  status = 'FAILED' AND log_date > SYSTIMESTAMP - INTERVAL '1' DAY;
SELECT input_type, status, start_time, end_time,
       ROUND(output_bytes / 1073741824, 1) AS output_gb
FROM   v$rman_backup_job_details WHERE start_time > SYSDATE - 7 ORDER BY start_time DESC;
SELECT name, guarantee_flashback_database, time FROM v$restore_point;
-- --8<-- [end:health]

-- --8<-- [start:alert]
-- Errors in the alert log during the last 24 hours
SELECT originating_timestamp, message_text
FROM   v$diag_alert_ext
WHERE  originating_timestamp > SYSTIMESTAMP - INTERVAL '1' DAY
AND    (message_text LIKE '%ORA-%' OR message_text LIKE '%Checkpoint not complete%'
        OR message_text LIKE '%Deadlock%' OR message_text LIKE '%corrupt%')
ORDER  BY originating_timestamp DESC;
-- --8<-- [end:alert]

-- --8<-- [start:capacity]
-- Largest segments
SELECT owner, segment_name, segment_type, ROUND(SUM(bytes) / 1073741824, 2) AS gb
FROM   dba_segments WHERE owner = 'FRESHMART'
GROUP  BY owner, segment_name, segment_type ORDER BY gb DESC FETCH FIRST 20 ROWS ONLY;

-- Database size
SELECT ROUND(SUM(bytes) / 1073741824, 1) AS allocated_gb FROM dba_data_files;
SELECT ROUND(SUM(bytes) / 1073741824, 1) AS used_gb FROM dba_segments;

-- Diagnostics Pack: tablespace growth trend from AWR
SELECT ts.tsname, TRUNC(sn.end_interval_time) AS day,
       ROUND(MAX(u.tablespace_usedsize * 8192) / 1073741824, 1) AS used_gb
FROM   dba_hist_tbspc_space_usage u
JOIN   dba_hist_snapshot sn ON sn.snap_id = u.snap_id AND sn.dbid = u.dbid
JOIN   dba_hist_tablespace_stat ts ON ts.ts# = u.tablespace_id AND ts.snap_id = u.snap_id AND ts.dbid = u.dbid
GROUP  BY ts.tsname, TRUNC(sn.end_interval_time)
ORDER  BY ts.tsname, day;

-- Peak sessions and processes against limits
SELECT resource_name, current_utilization, max_utilization, limit_value
FROM   v$resource_limit WHERE resource_name IN ('processes', 'sessions');
-- --8<-- [end:capacity]
