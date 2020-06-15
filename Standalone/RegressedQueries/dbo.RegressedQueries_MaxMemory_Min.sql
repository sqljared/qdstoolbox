SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE dbo.RegressedQueries_MaxMemory_Min
(
	@RegressedQueriesTable NVARCHAR(800) = NULL,
	@measurement	VARCHAR(32) = 'MaxMemory',
	@metric			VARCHAR(16) = 'Min',
	@results_row_count INT = 25,
	@recent_start_time DATETIME2 = NULL,
	@recent_end_time DATETIME2 = NULL,
	@history_start_time DATETIME2 = NULL,
	@history_end_time DATETIME2 = NULL,
	@min_exec_count INT = 1,
	@min_plan_count INT = 1,
	@max_plan_count INT = 99999
)
AS
IF (@results_row_count IS NULL) OR (@results_row_count <= 1)
	SET @results_row_count = 25

IF (@recent_start_time IS NULL) OR (@recent_end_time IS NULL) OR (@history_start_time IS NULL) OR (@history_end_time IS NULL)
BEGIN
	SET @recent_end_time	= SYSUTCDATETIME()
	SET @recent_start_time	= DATEADD(HOUR, -1, @recent_end_time)
	SET @history_end_time	= @recent_start_time
	SET @history_start_time	= DATEADD(DAY, -30, @recent_end_time)
END

IF (@min_plan_count IS NULL) OR (@min_plan_count < 1)
	SET @min_plan_count = 1

IF (@max_plan_count IS NOT NULL) AND (@max_plan_count < @min_plan_count)
	SET @max_plan_count = @min_plan_count

IF (@max_plan_count IS NULL) OR (@max_plan_count < @min_plan_count)
	SET @max_plan_count = 99999

-- Output to user - START
IF (@RegressedQueriesTable IS NULL) OR (@RegressedQueriesTable = '')
BEGIN
	WITH 
	hist AS
	(
	SELECT
		p.query_id query_id,
		ROUND(CONVERT(FLOAT, MIN(rs.min_query_max_used_memory))*8,2) min_query_max_used_memory,
		SUM(rs.count_executions) count_executions,
		COUNT(distinct p.plan_id) num_plans
     FROM sys.query_store_runtime_stats AS rs
        JOIN sys.query_store_plan AS p ON p.plan_id = rs.plan_id
    WHERE (rs.first_execution_time >= @history_start_time
               AND rs.last_execution_time < @history_end_time)
        OR (rs.first_execution_time <= @history_start_time
               AND rs.last_execution_time > @history_start_time)
        OR (rs.first_execution_time <= @history_end_time
               AND rs.last_execution_time > @history_end_time)
    GROUP BY p.query_id
	),
	recent AS
	(
	SELECT
		p.query_id query_id,
		ROUND(CONVERT(FLOAT, MIN(rs.min_query_max_used_memory))*8,2) min_query_max_used_memory,
		SUM(rs.count_executions) count_executions,
		COUNT(distinct p.plan_id) num_plans
    FROM sys.query_store_runtime_stats AS rs
        JOIN sys.query_store_plan AS p ON p.plan_id = rs.plan_id
    WHERE  (rs.first_execution_time >= @recent_start_time
               AND rs.last_execution_time < @recent_end_time)
        OR (rs.first_execution_time <= @recent_start_time
               AND rs.last_execution_time > @recent_start_time)
        OR (rs.first_execution_time <= @recent_end_time
               AND rs.last_execution_time > @recent_end_time)
    GROUP BY p.query_id
	)
	SELECT TOP (@results_row_count)
		results.query_id AS [QueryID],
		results.object_id AS [ObjectID],
		ISNULL(objs.SchemaName,'') AS [SchemaName],
		ISNULL(objs.ObjectName,'') AS [ObjectName],
		results.query_max_used_memory_regr_perc_recent query_max_used_memory_regr_perc_recent,
		results.min_query_max_used_memory_recent min_query_max_used_memory_recent,
		results.min_query_max_used_memory_hist min_query_max_used_memory_hist,
		ISNULL(results.count_executions_recent, 0) AS [ExecutionCountRecent],
		ISNULL(results.count_executions_hist, 0) AS [ExecutionCountHist],
		queries.num_plans AS [NumPlans],
		results.query_sql_text AS [QuerySqlText]
	FROM
	(
	SELECT
		hist.query_id query_id,
		q.object_id object_id,
		qt.query_sql_text query_sql_text,
		ROUND(CONVERT(FLOAT, recent.min_query_max_used_memory-hist.min_query_max_used_memory)/NULLIF(hist.min_query_max_used_memory,0)*100.0, 2) query_max_used_memory_regr_perc_recent,
		ROUND(recent.min_query_max_used_memory, 2) min_query_max_used_memory_recent,
		ROUND(hist.min_query_max_used_memory, 2) min_query_max_used_memory_hist,
		recent.count_executions count_executions_recent,
		hist.count_executions count_executions_hist
    FROM hist
        JOIN recent
            ON hist.query_id = recent.query_id
        JOIN sys.query_store_query AS q
            ON q.query_id = hist.query_id
        JOIN sys.query_store_query_text AS qt
            ON q.query_text_id = qt.query_text_id
	WHERE
		recent.count_executions >= @min_exec_count
	) AS results
	JOIN
	(
	SELECT
		p.query_id query_id,
		COUNT(distinct p.plan_id) num_plans
	FROM sys.query_store_plan p
	GROUP BY p.query_id
	HAVING COUNT(distinct p.plan_id) BETWEEN @min_plan_count AND @max_plan_count
	) AS queries ON queries.query_id = results.query_id
	LEFT JOIN 
	(
	SELECT 
		sc.name AS SchemaName,
		obs.name AS ObjectName,
		obs.object_id
	 FROM sys.objects obs
	 INNER JOIN sys.schemas sc
	 ON obs.schema_id = sc.schema_id
	) AS objs ON results.object_id = objs.object_id
	WHERE query_max_used_memory_regr_perc_recent > 0
	ORDER BY query_max_used_memory_regr_perc_recent DESC
	OPTION (MERGE JOIN)
END
-- Output to user - END

----------------------------------------------------------

-- Output to table - START
IF (@RegressedQueriesTable IS NOT NULL) AND (@RegressedQueriesTable <> '')
BEGIN
	DECLARE @SqlCmd NVARCHAR(MAX) =
	'WITH 
	hist AS
	(
	SELECT
		p.query_id query_id,
		ROUND(CONVERT(FLOAT, MIN(rs.min_query_max_used_memory))*8,2) min_query_max_used_memory,
		SUM(rs.count_executions) count_executions,
		COUNT(distinct p.plan_id) num_plans
     FROM sys.query_store_runtime_stats AS rs
        JOIN sys.query_store_plan AS p ON p.plan_id = rs.plan_id
    WHERE (rs.first_execution_time >= '''+CAST(@history_start_time AS VARCHAR(34))+'''
               AND rs.last_execution_time < '''+CAST(@history_end_time AS VARCHAR(34))+''')
        OR (rs.first_execution_time <= '''+CAST(@history_start_time AS VARCHAR(34))+'''
               AND rs.last_execution_time > '''+CAST(@history_start_time AS VARCHAR(34))+''')
        OR (rs.first_execution_time <= '''+CAST(@history_end_time AS VARCHAR(34))+'''
               AND rs.last_execution_time > '''+CAST(@history_end_time AS VARCHAR(34))+''')
    GROUP BY p.query_id
	),
	recent AS
	(
	SELECT
		p.query_id query_id,
		ROUND(CONVERT(FLOAT, MIN(rs.min_query_max_used_memory))*8,2) min_query_max_used_memory,
		SUM(rs.count_executions) count_executions,
		COUNT(distinct p.plan_id) num_plans
    FROM sys.query_store_runtime_stats AS rs
        JOIN sys.query_store_plan AS p ON p.plan_id = rs.plan_id
    WHERE  (rs.first_execution_time >= '''+CAST(@recent_start_time AS VARCHAR(34))+'''
               AND rs.last_execution_time < '''+CAST(@recent_end_time AS VARCHAR(34))+''')
        OR (rs.first_execution_time <= '''+CAST(@recent_start_time AS VARCHAR(34))+'''
               AND rs.last_execution_time > '''+CAST(@recent_start_time AS VARCHAR(34))+''')
        OR (rs.first_execution_time <= '''+CAST(@recent_end_time AS VARCHAR(34))+'''
               AND rs.last_execution_time > '''+CAST(@recent_end_time AS VARCHAR(34))+''')
    GROUP BY p.query_id
	)
	INSERT INTO ' + @RegressedQueriesTable +'
	SELECT TOP ('+CAST(@results_row_count AS VARCHAR(8))+')
		GETUTCDATE(),
		@@SERVERNAME,
		DB_NAME(),
		'''+@measurement+''',
		'''+@metric+''',
		results.query_id,
		results.object_id,
		ISNULL(objs.SchemaName,''''),
		ISNULL(objs.ObjectName,''''),
		results.query_max_used_memory_regr_perc_recent query_max_used_memory_regr_perc_recent,
		results.min_query_max_used_memory_recent min_query_max_used_memory_recent,
		results.min_query_max_used_memory_hist min_query_max_used_memory_hist,
		ISNULL(results.count_executions_recent, 0),
		ISNULL(results.count_executions_hist, 0),
		queries.num_plans,
		COMPRESS(results.query_sql_text)
	FROM
	(
	SELECT
		hist.query_id query_id,
		q.object_id object_id,
		qt.query_sql_text query_sql_text,
		ROUND(CONVERT(FLOAT, recent.min_query_max_used_memory-hist.min_query_max_used_memory)/NULLIF(hist.min_query_max_used_memory,0)*100.0, 2) query_max_used_memory_regr_perc_recent,
		ROUND(recent.min_query_max_used_memory, 2) min_query_max_used_memory_recent,
		ROUND(hist.min_query_max_used_memory, 2) min_query_max_used_memory_hist,
		recent.count_executions count_executions_recent,
		hist.count_executions count_executions_hist
    FROM hist
        JOIN recent
            ON hist.query_id = recent.query_id
        JOIN sys.query_store_query AS q
            ON q.query_id = hist.query_id
        JOIN sys.query_store_query_text AS qt
            ON q.query_text_id = qt.query_text_id
	WHERE
		recent.count_executions >= '+ CAST(@min_exec_count AS VARCHAR(8))+'
	) AS results
	JOIN
	(
	SELECT
		p.query_id query_id,
		COUNT(distinct p.plan_id) num_plans
	FROM sys.query_store_plan p
	GROUP BY p.query_id
	HAVING COUNT(distinct p.plan_id) BETWEEN '+CAST(@min_plan_count AS VARCHAR(8))+' AND ' +CAST(@max_plan_count AS VARCHAR(8))+'
	) AS queries ON queries.query_id = results.query_id
	LEFT JOIN 
	(
	SELECT 
		sc.name AS SchemaName,
		obs.name AS ObjectName,
		obs.object_id
	 FROM sys.objects obs
	 INNER JOIN sys.schemas sc
	 ON obs.schema_id = sc.schema_id
	) AS objs ON results.object_id = objs.object_id
	WHERE query_max_used_memory_regr_perc_recent > 0
	ORDER BY query_max_used_memory_regr_perc_recent DESC
	OPTION (MERGE JOIN)'

	EXEC  (@SqlCmd)
END
-- Output to table - END


GO
