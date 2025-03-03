SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

----------------------------------------------------------------------------------
-- Procedure Name: [dbo].[QueryVariation]
--
-- Desc: This script queries the QDS data and generates a report based on those queries whose performance has changed when comparing two periods of time
--
--
-- Parameters:
--	INPUT
--		@ServerIdentifier			SYSNAME			--	Identifier assigned to the server.
--														[Default: @@SERVERNAME]
--
--		@DatabaseName				SYSNAME			--	Name of the database to generate this report on.
--														[Default: DB_NAME()]
--
--		@ReportIndex				NVARCHAR(800)	--	Table to store the details of the report, such as parameters used, if no results returned to the user are required
--														[Default: NULL, results returned to user]
--
--		@ReportTable				NVARCHAR(800)	--	Table to store the results of the report, if no results returned to the user are required. 
--														[Default: NULL, results returned to user]
--
--		@Measurement				NVARCHAR(32)	--	Measurement to analyze, to select from
--															CLR
--															CPU
--															DOP
--															Duration
--															Log
--															LogicalIOReads
--															LogicalIOWrites
--															MaxMemory
--															PhysicalIOReads
--															Rowcount
--															TempDB
--														[Default: CPU]
--
--		@Metric						NVARCHAR(8)		--	Metric on which to analyze the @Measurement values on, to select from
--															Avg
--															Max
--															Min
--															StdDev
--															Total
--														[Default: Avg]
--
--		@VariationType				NVARCHAR(1)		--	Defines whether queries whose metric indicates an improvement (I) or a regression (R).
--														[Default: R]
--
--		@ResultsRowCount			INT				--	Number of rows to return.
--														[Default: 25]
--
--		@RecentStartTime			DATETIME2		--	Start of the time period considered as "recent" to be compared with the "history" time period. Must be expressed in UTC.
--														[Default: DATEADD(HOUR, -1, SYSUTCDATETIME()]
--
--		@RecentEndTime				DATETIME2		--	End of the time period considered as "recent" to be compared with the "history" time period. Must be expressed in UTC.
--														[Default: SYSUTCDATETIME()]
--
--		@HistoryStartTime			DATETIME2		--	Start of the time period considered as "history" to be compared with the "recent" time period. Must be expressed in UTC.
--														[Default: DATEADD(DAY, -30, SYSUTCDATETIME())]
--
--		@HistoryEndTime				DATETIME2		--	End of the time period considered as "history" to be compared with the "recent" time period. Must be expressed in UTC.
--														[Default: DATEADD(HOUR, -1, SYSUTCDATETIME()]
--
--		@MinExecCount				INT				--	Minimum number of executions in the "recent" time period to analyze the query.
--														[Default: 1]
--
--		@MinPlanCount				INT				--	Minimum number of different execution plans used by the query to analyze it.
--														[Default: 1]
--
--		@MaxPlanCount				INT				--	Maximum number of different execution plans used by the query to analyze it.
--														[Default: 99999]
--
--		@IncludeQueryText			BIT				--	Flag to define whether the text of the query will be returned.
--														[Default: 0]
--
--		@ExcludeAdhoc				BIT				--	Flag to define whether to ignore adhoc queries (not part of a DB object) from the analysis
--														[Default: 0]
--
--		@ExcludeInternal			BIT				--	Flag to define whether to ignore internal queries (backup, index rebuild, statistics update...) from the analysis
--														[Default: 0]
--
--		@VerboseMode				BIT				--	Flag to determine whether the T-SQL commands that compose this report will be returned to the user.
--														[Default: 0]
--
--		@TestMode					BIT				--	Flag to determine whether the actual T-SQL commands that generate the report will be executed.
--														[Default:0]
--
--	OUTPUT
--		@ReportID					BIGINT			--	Returns the ReportID (when the report is being logged into a table)
--
-- Sample execution:
--
--	Sample 1: Return a list of the 25 queries whose average duration increased the most in the last hour compared to the previous month
--		EXECUTE [dbo].[QueryVariation]
--			@Measurement	= 'Duration',
--			@Metric			= 'Avg'
--
--
--	Sample 2: Save a list of the top 10 queries whose average CPU was reduced the most in the last hour compared to the previous month despite not changing on its execution plan,
--			into the table [dbo].[QueryVariationStore], not including the queries' text
--		EXECUTE [dbo].[QueryVariation]
--			@ReportIndex		= '[dbo].[QueryVariationIndex]',
--			@ReportTable		= '[dbo].[QueryVariationStore]',
--			@Measurement		= 'CPU',
--			@Metric				= 'Total',
--			@VariationType		= 'I',
--			@ResultsRowCount	= 10
--			@MaxPlanCount		= 1,
--			@IncludeQueryText	= 0
--
--	Sample 3: Save a list of the top 5 queries whose max TempDB has increased in the last week compared to the previous one on the database [DBxxx], and store the results
--			into a table in a linked server [LinkedSrv].[LinkedDB].[dbo].[CentralizedQueryVariationStore], including the queries' text
--		DECLARE @RecentEnd		DATETIME2 = SYSUTCDATETIME()
--		DECLARE @RecentStart	DATETIME2 = DATEADD(DAY, -7, @RecentEnd)
--		DECLARE @HistoryStart	DATETIME2 = DATEADD(DAY, -14, @RecentEnd)
--		DECLARE @HistoryEnd		DATETIME2 = @RecentEnd
--		EXECUTE [dbo].[QueryVariation]
--			@ReportIndex		= '[LinkedSrv].[LinkedDB].[dbo].[CentralizedQueryVariationIndex]',
--			@ReportTable		= '[LinkedSrv].[LinkedDB].[dbo].[CentralizedQueryVariationStore]',
--			@Measurement		= 'TempDB',
--			@Metric				= 'Max',
--			@VariationType		= 'R',
--			@ResultsRowCount	= 5,
--			@RecentStartTime	= @RecentStart,
--			@RecentEndTime		= @RecentEnd,
--			@HistoryStartTime	= @HistoryStart,
--			@HistoryEndTime		= @HistoryEnd,
--			@IncludeQueryText	= 1
--			
--
--
-- Date: 2020.10.22
-- Auth: Pablo Lozano (@sqlozano)
--
-- Date: 2021.02.28
-- Auth: Pablo Lozano (@sqlozano)
-- Changes:	Execution in SQL 2016 will thrown an error when the @Measurement selected does not exist
----------------------------------------------------------------------------------

CREATE OR ALTER PROCEDURE [dbo].[QueryVariation]
(
	 @ServerIdentifier		SYSNAME			=	NULL	
	,@DatabaseName			SYSNAME			=	NULL
	,@ReportIndex			NVARCHAR(800)	=	NULL
	,@ReportTable			NVARCHAR(800)	=	NULL
	,@Measurement			NVARCHAR(32)	=	'CPU'
	,@Metric				NVARCHAR(16)	=	'Avg'
	,@VariationType			NVARCHAR(1)		=	'R'
	,@ResultsRowCount		INT				=	25
	,@RecentStartTime		DATETIME2		=	NULL
	,@RecentEndTime			DATETIME2		=	NULL
	,@HistoryStartTime		DATETIME2		=	NULL
	,@HistoryEndTime		DATETIME2		=	NULL
	,@MinExecCount			INT				=	1
	,@MinPlanCount			INT				=	1
	,@MaxPlanCount			INT				=	99999
	,@IncludeQueryText		BIT				=	0
	,@ExcludeAdhoc			BIT				=	0
	,@ExcludeInternal		BIT				=	1
	,@VerboseMode			BIT				=	0
	,@TestMode				BIT				=	0
	,@ReportID				BIGINT			=	NULL	OUTPUT
)
AS
SET NOCOUNT ON

-- Get the Version # to ensure it runs SQL2016 or higher
DECLARE @Version INT =  CAST(SUBSTRING(CONVERT(VARCHAR(128), SERVERPROPERTY ('productversion')),0,CHARINDEX('.',CONVERT(VARCHAR(128), SERVERPROPERTY ('productversion')),0)) AS INT)
IF (@Version < 13)
BEGIN
	RAISERROR(N'[dbo].[QueryVariation] requires SQL 2016 or higher',16,1)
	RETURN -1
END
-- Raise an error if the @Measurement selected is not available in SQL 2016
IF (@Version = 13 AND @Measurement IN ('Log', 'TempDB'))
BEGIN
	RAISERROR(N'The selected @Measurement [%s] is not available in the current SQL version (2016)',16,1, @Measurement)
	RETURN -1
END

-- Check variables and set defaults - START
IF (@ServerIdentifier IS NULL)
	SET @ServerIdentifier = @@SERVERNAME

IF (@DatabaseName IS NULL) OR (@DatabaseName = '')
	SET @DatabaseName = DB_NAME()

IF (@VariationType NOT IN ('R','I'))
	SET @VariationType = 'R'

IF (@ResultsRowCount IS NULL) OR (@ResultsRowCount < 1)
	SET @ResultsRowCount = 25

IF (@RecentStartTime IS NULL) OR (@RecentEndTime IS NULL) OR (@HistoryStartTime IS NULL) OR (@HistoryEndTime IS NULL)
BEGIN
	SET @RecentEndTime	= SYSUTCDATETIME()
	SET @RecentStartTime	= DATEADD(HOUR, -1, @RecentEndTime)
	SET @HistoryEndTime	= @RecentStartTime
	SET @HistoryStartTime	= DATEADD(DAY, -30, @RecentEndTime)
END

IF (@MinExecCount IS NULL) OR (@MinExecCount < 1)
	SET @MinExecCount = 1

IF (@MinPlanCount IS NULL) OR (@MinPlanCount < 1)
	SET @MinPlanCount = 1

IF (@MaxPlanCount IS NOT NULL) AND (@MaxPlanCount < @MinPlanCount)
	SET @MaxPlanCount = @MinPlanCount

IF (@MaxPlanCount IS NULL) OR (@MaxPlanCount < @MinPlanCount)
	SET @MaxPlanCount = 99999

IF (@IncludeQueryText IS NULL)
	SET @IncludeQueryText = 1
-- Check variables and set defaults - END

-- Verify variables that cannot be defaulted - START
DECLARE @Error BIT = 0

	-- Check whether @DatabaseName actually exists - START
	IF NOT EXISTS (SELECT 1 FROM [sys].[databases] WHERE [name] = @DatabaseName)
	BEGIN
		RAISERROR('The database [%s] does not exist', 16, 0, @DatabaseName)
		RETURN
	END
	-- Check whether @DatabaseName actually exists - END
	
	-- Check whether @DatabaseName is ONLINE - START
	IF EXISTS (SELECT 1 FROM [sys].[databases] WHERE [name] = @DatabaseName AND [state_desc] <> 'ONLINE')
	BEGIN
		RAISERROR('The database [%s] is not online', 16, 0, @DatabaseName)
		RETURN
	END
	-- Check whether @DatabaseName is ONLINE - END
	
	-- Check the @Measurement and @Metric parameters are valid - START
	IF NOT EXISTS(SELECT 1 FROM [dbo].[QDSMetricArchive] WHERE [Measurement] = @Measurement AND [Metric] = @Metric)
	BEGIN
		RAISERROR('The @Measurement [%s] and @Metric [%s] provided are not valid. Check the table [dbo].[QDSMetricArchive] for reference.',0,1, @Measurement, @Metric)
		SET @Error = 1
	END
	-- Check the @Measurement and @Metric parameters are valid - END

IF (@Error = 1)
BEGIN
 RAISERROR('Errors found in the input parameters, see messages above.', 16, 0)
 RETURN
END
-- Verify variables that cannot be defaulted - END


-- Verify all the SubQueries exist - START
DECLARE @SubQuery01 NVARCHAR(MAX)
DECLARE @SubQuery02 NVARCHAR(MAX)
DECLARE @SubQuery03 NVARCHAR(MAX)
DECLARE @SubQuery04 NVARCHAR(MAX)

SELECT 
	 @SubQuery01 = [SubQuery01]
	,@SubQuery02 = [SubQuery02]
	,@SubQuery03 = [SubQuery03]
	,@SubQuery04 = [SubQuery04]
FROM [dbo].[QDSMetricArchive] 
WHERE 
	[Measurement] = @Measurement
AND [Metric] = @Metric

IF (@SubQuery01 IS NULL) OR (@SubQuery02 IS NULL) OR (@SubQuery03 IS NULL) OR (@SubQuery04 IS NULL)
BEGIN
	RAISERROR('There are no valid SubQueries for the parameters @Measurement [%s] and @Metric [%s] provided. Check the table [dbo].[QDSMetricArchive] for reference.',16,0, @Measurement, @Metric)
	RETURN
END
-- Verify all the SubQueries exist - END

IF (@Error = 0)
BEGIN
-- Output to user - START
IF (@ReportTable IS NULL) OR (@ReportTable = '') OR (@ReportIndex IS NULL) OR (@ReportIndex = '')
BEGIN
	DECLARE @SqlCmd2User NVARCHAR(MAX) =
	'WITH 
	[hist] AS
	(
	SELECT
		[qsp].[query_id] [query_id],
		{@SubQuery01}
		SUM([qsrs].[count_executions]) [count_executions],
		COUNT(DISTINCT [qsp].[plan_id]) [num_plans]
    FROM [{@DatabaseName}].[sys].[query_store_runtime_stats] AS [qsrs]
        INNER JOIN [{@DatabaseName}].[sys].[query_store_plan]  AS [qsp] ON [qsp].[plan_id]  = [qsrs].[plan_id]
		INNER JOIN [{@DatabaseName}].[sys].[query_store_query] AS [qsq] ON [qsq].[query_id] = [qsp].[query_id]
    WHERE 
		(
			([qsrs].[first_execution_time] >= ''{@HistoryStartTime}'' AND [qsrs].[last_execution_time] < ''{@HistoryEndTime}'')
        OR	([qsrs].[first_execution_time] <= ''{@HistoryStartTime}'' AND [qsrs].[last_execution_time] > ''{@HistoryStartTime}'')
        OR	([qsrs].[first_execution_time] <= ''{@HistoryEndTime}''   AND [qsrs].[last_execution_time] > ''{@HistoryEndTime}'')
		)
		{@ExcludeAdhoc}
		{@ExcludeInternal}
    GROUP BY [qsp].[query_id]
	),
	[recent] AS
	(
	SELECT
		[qsp].[query_id] [query_id],
		{@SubQuery01}
		SUM([qsrs].[count_executions]) [count_executions],
		COUNT(DISTINCT [qsp].[plan_id]) [num_plans]
    FROM [{@DatabaseName}].[sys].[query_store_runtime_stats] AS [qsrs]
        INNER JOIN [{@DatabaseName}].[sys].[query_store_plan]  AS [qsp] ON [qsp].[plan_id]  = [qsrs].[plan_id]
		INNER JOIN [{@DatabaseName}].[sys].[query_store_query] AS [qsq] ON [qsq].[query_id] = [qsp].[query_id]
    WHERE
		(
			([qsrs].[first_execution_time] >= ''{@RecentStartTime}'' AND [qsrs].[last_execution_time] < ''{@RecentEndTime}'')
        OR ([qsrs].[first_execution_time]  <= ''{@RecentStartTime}'' AND [qsrs].[last_execution_time] > ''{@RecentStartTime}'')
        OR ([qsrs].[first_execution_time]  <= ''{@RecentEndTime}''   AND [qsrs].[last_execution_time] > ''{@RecentEndTime}'')
		)
		{@ExcludeAdhoc}
		{@ExcludeInternal}
    GROUP BY [qsp].[query_id]
	)
	SELECT TOP ({@ResultsRowCount})
		[results].[query_id] AS [QueryID],
		[results].[object_id] AS [ObjectID],
		[objs].[SchemaName] AS [SchemaName],
		[objs].[ObjectName] AS [ObjectName],
		{@SubQuery02}
		ISNULL([results].[count_executions_recent], 0) AS [ExecutionCountRecent],
		ISNULL([results].[count_executions_hist], 0) AS [ExecutionCountHist],
		[queries].[num_plans] AS [NumPlans],
		[results].[query_sql_text] AS [QuerySqlText]
	FROM
	(
	SELECT
		[hist].[query_id] [query_id],
		[qsq].[object_id] [object_id],
		CASE
			WHEN {@IncludeQueryText} = 1 THEN [qsqt].[query_sql_text]
			ELSE NULL
		END AS [query_sql_text],
		{@SubQuery03}
		[recent].[count_executions] [count_executions_recent],
		[hist].[count_executions] [count_executions_hist]
    FROM [hist]
        INNER JOIN [recent]
            ON [hist].[query_id] = [recent].[query_id]
        INNER JOIN [{@DatabaseName}].[sys].[query_store_query] AS [qsq]
            ON [qsq].[query_id] = [hist].[query_id]
        INNER JOIN [{@DatabaseName}].[sys].[query_store_query_text] AS [qsqt]
            ON [qsq].[query_text_id] = [qsqt].[query_text_id]
	WHERE
		[recent].[count_executions] >= {@MinExecCount}
	) AS results
	JOIN
	(
	SELECT
		[qsp].[query_id] [query_id],
		COUNT(DISTINCT [qsp].[plan_id]) [num_plans]
	FROM [{@DatabaseName}].[sys].[query_store_plan] [qsp]
	GROUP BY [qsp].[query_id]
	HAVING COUNT(DISTINCT [qsp].[plan_id]) BETWEEN {@MinPlanCount} AND {@MaxPlanCount}
	) AS [queries] ON [queries].[query_id] = [results].[query_id]
	LEFT JOIN 
	(
	SELECT 
		[sc].[name] AS [SchemaName],
		[obs].[name] AS [ObjectName],
		[obs].[object_id]
	 FROM [{@DatabaseName}].[sys].[objects] [obs]
	 INNER JOIN [{@DatabaseName}].[sys].[schemas] [sc]
	 ON [obs].[schema_id] = [sc].[schema_id]
	) AS [objs] ON [results].[object_id] = [objs].[object_id]
	WHERE {@SubQuery04} {@Zero} 0
	ORDER BY {@SubQuery04} {@ASCDESC}
	OPTION (MERGE JOIN)'

	SET @SqlCmd2User = REPLACE(@SqlCmd2User, '{@DatabaseName}',			@DatabaseName) 
	SET @SqlCmd2User = REPLACE(@SqlCmd2User, '{@SubQuery01}',			@SubQuery01) 
	SET @SqlCmd2User = REPLACE(@SqlCmd2User, '{@SubQuery02}',			@SubQuery02) 
	SET @SqlCmd2User = REPLACE(@SqlCmd2User, '{@SubQuery03}',			@SubQuery03) 
	SET @SqlCmd2User = REPLACE(@SqlCmd2User, '{@SubQuery04}',			@SubQuery04) 
	SET @SqlCmd2User = REPLACE(@SqlCmd2User, '{@HistoryStartTime}',		CAST(@HistoryStartTime AS NVARCHAR(34)))
	SET @SqlCmd2User = REPLACE(@SqlCmd2User, '{@HistoryEndTime}',		CAST(@HistoryEndTime AS NVARCHAR(34)))
	SET @SqlCmd2User = REPLACE(@SqlCmd2User, '{@RecentStartTime}',		CAST(@RecentStartTime AS NVARCHAR(34)))
	SET @SqlCmd2User = REPLACE(@SqlCmd2User, '{@RecentEndTime}',		CAST(@RecentEndTime AS NVARCHAR(34)))
	SET @SqlCmd2User = REPLACE(@SqlCmd2User, '{@ResultsRowCount}',		CAST(@ResultsRowCount AS NVARCHAR(20)))
	SET @SqlCmd2User = REPLACE(@SqlCmd2User, '{@MinExecCount}',			CAST(@MinExecCount AS NVARCHAR(20)))
	SET @SqlCmd2User = REPLACE(@SqlCmd2User, '{@MinPlanCount}',			CAST(@MinPlanCount AS NVARCHAR(20)))
	SET @SqlCmd2User = REPLACE(@SqlCmd2User, '{@MaxPlanCount}',			CAST(@MaxPlanCount AS NVARCHAR(20)))
	SET @SqlCmd2User = REPLACE(@SqlCmd2User, '{@IncludeQueryText} ',	CAST(@IncludeQueryText AS NVARCHAR(1)))

	-- Based on @ExcludeAdhoc, exclude Adhoc queries from the analysis - START
	IF (@ExcludeAdhoc = 0)
	BEGIN
		SET @SqlCmd2User = REPLACE(@SqlCmd2User, '{@ExcludeAdhoc}',		'')	
	END
	IF (@ExcludeAdhoc = 1)
	BEGIN
		SET @SqlCmd2User = REPLACE(@SqlCmd2User, '{@ExcludeAdhoc}',		'AND ([qsq].[object_id] <> 0)')
	END
	-- Based on @ExcludeAdhoc, exclude Adhoc queries from the analysis - END
	
	-- Based on @ExcludeInternal, exclude internal queries from the analysis - START
	IF (@ExcludeInternal = 0)
	BEGIN
		SET @SqlCmd2User = REPLACE(@SqlCmd2User, '{@ExcludeInternal}',	'')	
	END
	IF (@ExcludeInternal = 1)
	BEGIN
		SET @SqlCmd2User = REPLACE(@SqlCmd2User, '{@ExcludeInternal}',	'AND ([qsq].[is_internal_query] = 0)')	
	END
	-- Based on @ExcludeInternal, exclude internal queries from the analysis - END
	
	-- Based on @VariationType, adapt results' ordering - START
	IF (@VariationType = 'R')
	BEGIN
		SET @SqlCmd2User = REPLACE(@SqlCmd2User, '{@Zero}',				'>')
		SET @SqlCmd2User = REPLACE(@SqlCmd2User, '{@ASCDESC}',			'DESC')
	END
	IF (@VariationType = 'I')
	BEGIN
		SET @SqlCmd2User = REPLACE(@SqlCmd2User, '{@Zero}',				'<')
		SET @SqlCmd2User = REPLACE(@SqlCmd2User, '{@ASCDESC}',			'ASC')
	END
	-- Based on @VariationType, adapt results' ordering - END

	IF (@VerboseMode = 1) PRINT (@SqlCmd2User)
	IF (@TestMode = 0)	EXEC (@SqlCmd2User)
END
-- Output to user - END

-- Output to table - START
IF (@ReportTable IS NOT NULL) AND (@ReportTable <> '') AND (@ReportIndex IS NOT NULL) AND (@ReportIndex <> '')
BEGIN
	-- Log report entry in [dbo].[QueryVariationIndex] - START
	DECLARE @SqlCmdIndex NVARCHAR(MAX) =
	'INSERT INTO {@ReportIndex}
	(
		[CaptureDate],
		[ServerIdentifier],
		[DatabaseName],
		[Parameters]
	)
	SELECT
		SYSUTCDATETIME(),
		''{@ServerIdentifier}'',
		''{@DatabaseName}'',
		(
		SELECT
			''{@Measurement}''		AS [Measurement],
			''{@Metric}''			AS [Metric],
			''{@VariationType}''	AS [VariationType],
			{@ResultsRowCount}		AS [ResultsRowCount],
			''{@RecentStartTime}''	AS [RecentStartTime],
			''{@RecentEndTime}''	AS [RecentEndTime],
			''{@HistoryStartTime}''	AS [HistoryStartTime],
			''{@HistoryEndTime}''	AS [HistoryEndTime],
			{@MinExecCount}			AS [MinExecCount],
			{@MinPlanCount}			AS [MinPlanCount],
			{@MaxPlanCount}			AS [MaxPlanCount],
			{@IncludeQueryText}		AS [IncludeQueryText],
			{@ExcludeAdhoc}			AS [ExcludeAdhoc],
			{@ExcludeInternal}		AS [ExcludeInternal]
		FOR XML PATH(''QueryVariationParameters''), ROOT(''Root'')
		)	AS [Parameters]'

	SET @SqlCmdIndex = REPLACE(@SqlCmdIndex, '{@ReportIndex}',		@ReportIndex)
	SET @SqlCmdIndex = REPLACE(@SqlCmdIndex, '{@ServerIdentifier}',	@ServerIdentifier)
	SET @SqlCmdIndex = REPLACE(@SqlCmdIndex, '{@DatabaseName}',		@DatabaseName)
	SET @SqlCmdIndex = REPLACE(@SqlCmdIndex, '{@Measurement}',		@Measurement)
	SET @SqlCmdIndex = REPLACE(@SqlCmdIndex, '{@Metric}',			@Metric)
	SET @SqlCmdIndex = REPLACE(@SqlCmdIndex, '{@VariationType}',	@VariationType)
	SET @SqlCmdIndex = REPLACE(@SqlCmdIndex, '{@ResultsRowCount}',	CAST(@ResultsRowCount AS NVARCHAR(20)))
	SET @SqlCmdIndex = REPLACE(@SqlCmdIndex, '{@RecentStartTime}',	CAST(@RecentStartTime AS NVARCHAR(34)))
	SET @SqlCmdIndex = REPLACE(@SqlCmdIndex, '{@RecentEndTime}',	CAST(@RecentEndTime AS NVARCHAR(34)))
	SET @SqlCmdIndex = REPLACE(@SqlCmdIndex, '{@HistoryStartTime}',	CAST(@HistoryStartTime AS NVARCHAR(34)))
	SET @SqlCmdIndex = REPLACE(@SqlCmdIndex, '{@HistoryEndTime}',	CAST(@HistoryEndTime AS NVARCHAR(34)))
	SET @SqlCmdIndex = REPLACE(@SqlCmdIndex, '{@MinExecCount}',		CAST(@MinExecCount AS NVARCHAR(20)))
	SET @SqlCmdIndex = REPLACE(@SqlCmdIndex, '{@MinPlanCount}',		CAST(@MinPlanCount AS NVARCHAR(20)))
	SET @SqlCmdIndex = REPLACE(@SqlCmdIndex, '{@MaxPlanCount}',		CAST(@MaxPlanCount AS NVARCHAR(20)))
	SET @SqlCmdIndex = REPLACE(@SqlCmdIndex, '{@IncludeQueryText}',	CAST(@IncludeQueryText AS NVARCHAR(1)))
	SET @SqlCmdIndex = REPLACE(@SqlCmdIndex, '{@ExcludeAdhoc}',		CAST(@ExcludeAdhoc AS NVARCHAR(1)))
	SET @SqlCmdIndex = REPLACE(@SqlCmdIndex, '{@ExcludeInternal}',	CAST(@ExcludeInternal AS NVARCHAR(1)))

	IF (@VerboseMode = 1) PRINT (@SqlCmdIndex)
	IF (@TestMode = 0) EXEC (@SqlCmdIndex)


	SET @ReportID = IDENT_CURRENT(@ReportIndex)
	-- Log report entry in [dbo].[QueryVariationIndex] - END

	DECLARE @SqlCmd2Table NVARCHAR(MAX) =
	'WITH 
	[hist] AS
	(
	SELECT
		[qsp].[query_id] [query_id],
		{@SubQuery01}
		SUM([qsrs].[count_executions]) [count_executions],
		COUNT(DISTINCT [qsp].[plan_id]) [num_plans]
    FROM [{@DatabaseName}].[sys].[query_store_runtime_stats] AS [qsrs]
        INNER JOIN [{@DatabaseName}].[sys].[query_store_plan]  AS [qsp] ON [qsp].[plan_id]  = [qsrs].[plan_id]
		INNER JOIN [{@DatabaseName}].[sys].[query_store_query] AS [qsq] ON [qsq].[query_id] = [qsp].[query_id]
    WHERE 
		(
			([qsrs].[first_execution_time] >= ''{@HistoryStartTime}'' AND [qsrs].[last_execution_time] < ''{@HistoryEndTime}'')
		OR  ([qsrs].[first_execution_time] <= ''{@HistoryStartTime}'' AND [qsrs].[last_execution_time] > ''{@HistoryStartTime}'')
        OR  ([qsrs].[first_execution_time] <= ''{@HistoryEndTime}''   AND [qsrs].[last_execution_time] > ''{@HistoryEndTime}'')
		)
		{@ExcludeAdhoc}
		{@ExcludeInternal}
    GROUP BY [qsp].[query_id]
	),
	[recent] AS
	(
	SELECT
		[qsp].[query_id] [query_id],
		{@SubQuery01}
		SUM([qsrs].[count_executions]) [count_executions],
		COUNT(DISTINCT [qsp].[plan_id]) [num_plans]
    FROM [{@DatabaseName}].[sys].[query_store_runtime_stats] AS [qsrs]
        INNER JOIN [{@DatabaseName}].[sys].[query_store_plan]  AS [qsp] ON [qsp].[plan_id]  = [qsrs].[plan_id]
		INNER JOIN [{@DatabaseName}].[sys].[query_store_query] AS [qsq] ON [qsq].[query_id] = [qsp].[query_id]
    WHERE
		(
			([qsrs].[first_execution_time] >= ''{@RecentStartTime}'' AND [qsrs].[last_execution_time] < ''{@RecentEndTime}'')
        OR	([qsrs].[first_execution_time] <= ''{@RecentStartTime}'' AND [qsrs].[last_execution_time] > ''{@RecentStartTime}'')
        OR	([qsrs].[first_execution_time] <= ''{@RecentEndTime}''   AND [qsrs].[last_execution_time] > ''{@RecentEndTime}'')
		)
		{@ExcludeAdhoc}
		{@ExcludeInternal}
    GROUP BY [qsp].[query_id]
	)
	INSERT INTO {@ReportTable}
	SELECT TOP ({@ResultsRowCount})
		{@ReportID},
		[results].[query_id],
		[results].[object_id],
		[objs].[SchemaName],
		[objs].[ObjectName],
		{@SubQuery02}
		ISNULL([results].[count_executions_recent], 0),
		ISNULL([results].[count_executions_hist], 0),
		[queries].[num_plans],
		COMPRESS([results].[query_sql_text])
	FROM
	(
	SELECT
		[hist].[query_id] [query_id],
		[qsq].[object_id] [object_id],
		CASE
			WHEN {@IncludeQueryText} = 1 THEN [qsqt].[query_sql_text]
			ELSE NULL
		END as query_sql_text,
		{@SubQuery03}
		[recent].[count_executions] [count_executions_recent],
		[hist].[count_executions] [count_executions_hist]
    FROM hist
        INNER JOIN recent
            ON [hist].[query_id] = [recent].[query_id]
        INNER JOIN [{@DatabaseName}].[sys].[query_store_query] AS [qsq]
            ON [qsq].[query_id] = [hist].[query_id]
        INNER JOIN [{@DatabaseName}].[sys].[query_store_query_text] AS [qsqt]
            ON [qsq].[query_text_id] = [qsqt].[query_text_id]
	WHERE
		[recent].[count_executions] >= {@MinExecCount}
	) AS [results]
	INNER JOIN
	(
	SELECT
		[qsp].[query_id] [query_id],
		COUNT(DISTINCT [qsp].[plan_id]) [num_plans]
	FROM [{@DatabaseName}].[sys].[query_store_plan] [qsp]
	GROUP BY [qsp].[query_id]
	HAVING COUNT(DISTINCT [qsp].[plan_id]) BETWEEN {@MinPlanCount} AND {@MaxPlanCount}
	) AS [queries] ON [queries].[query_id] = [results].[query_id]
	LEFT JOIN 
	(
	SELECT 
		[sc].[name]  AS [SchemaName],
		[obs].[name] AS [ObjectName],
		[obs].[object_id]
	 FROM [{@DatabaseName}].[sys].[objects] [obs]
	 INNER JOIN [{@DatabaseName}].[sys].[schemas] [sc]
	 ON [obs].[schema_id] = [sc].[schema_id]
	) AS [objs] ON [results].[object_id] = [objs].[object_id]
	WHERE {@SubQuery04} {@Zero} 0
	ORDER BY {@SubQuery04} {@ASCDESC}
	OPTION (MERGE JOIN)'

	SET @SqlCmd2Table = REPLACE(@SqlCmd2Table, '{@ReportTable}',		@ReportTable) 
	SET @SqlCmd2Table = REPLACE(@SqlCmd2Table, '{@DatabaseName}',		@DatabaseName) 
	SET @SqlCmd2Table = REPLACE(@SqlCmd2Table, '{@ReportID}',			@ReportID) 
	SET @SqlCmd2Table = REPLACE(@SqlCmd2Table, '{@SubQuery01}',			@SubQuery01) 
	SET @SqlCmd2Table = REPLACE(@SqlCmd2Table, '{@SubQuery02}',			@SubQuery02) 
	SET @SqlCmd2Table = REPLACE(@SqlCmd2Table, '{@SubQuery03}',			@SubQuery03) 
	SET @SqlCmd2Table = REPLACE(@SqlCmd2Table, '{@SubQuery04}',			@SubQuery04) 
	SET @SqlCmd2Table = REPLACE(@SqlCmd2Table, '{@HistoryStartTime}',	CAST(@HistoryStartTime AS NVARCHAR(34)))
	SET @SqlCmd2Table = REPLACE(@SqlCmd2Table, '{@HistoryEndTime}',		CAST(@HistoryEndTime AS NVARCHAR(34)))
	SET @SqlCmd2Table = REPLACE(@SqlCmd2Table, '{@RecentStartTime}',	CAST(@RecentStartTime AS NVARCHAR(34)))
	SET @SqlCmd2Table = REPLACE(@SqlCmd2Table, '{@RecentEndTime}',		CAST(@RecentEndTime AS NVARCHAR(34)))
	SET @SqlCmd2Table = REPLACE(@SqlCmd2Table, '{@ResultsRowCount}',	CAST(@ResultsRowCount AS NVARCHAR(8)))
	SET @SqlCmd2Table = REPLACE(@SqlCmd2Table, '{@MinExecCount}',		CAST(@MinExecCount AS NVARCHAR(8)))
	SET @SqlCmd2Table = REPLACE(@SqlCmd2Table, '{@MinPlanCount}',		CAST(@MinPlanCount AS NVARCHAR(8)))
	SET @SqlCmd2Table = REPLACE(@SqlCmd2Table, '{@MaxPlanCount}',		CAST(@MaxPlanCount AS NVARCHAR(8)))
	SET @SqlCmd2Table = REPLACE(@SqlCmd2Table, '{@IncludeQueryText} ',	CAST(@IncludeQueryText AS NVARCHAR(1)))

	-- Based on @ExcludeAdhoc, exclude Adhoc queries from the analysis - START
	IF (@ExcludeAdhoc = 0)
	BEGIN
		SET @SqlCmd2Table = REPLACE(@SqlCmd2Table, '{@ExcludeAdhoc}',		'')	
	END
	IF (@ExcludeAdhoc = 1)
	BEGIN
		SET @SqlCmd2Table = REPLACE(@SqlCmd2Table, '{@ExcludeAdhoc}',		'AND ([qsq].[object_id] <> 0)')
	END
	-- Based on @ExcludeAdhoc, exclude Adhoc queries from the analysis - END
	
	-- Based on @ExcludeInternal, exclude internal queries from the analysis - START
	IF (@ExcludeInternal = 0)
	BEGIN
		SET @SqlCmd2Table = REPLACE(@SqlCmd2Table, '{@ExcludeInternal}',	'')	
	END
	IF (@ExcludeInternal = 1)
	BEGIN
		SET @SqlCmd2Table = REPLACE(@SqlCmd2Table, '{@ExcludeInternal}',	'AND ([qsq].[is_internal_query] = 0)')	
	END
	-- Based on @ExcludeInternal, exclude internal queries from the analysis - END
	
	-- Based on @VariationType, adapt results' ordering - START
	IF (@VariationType = 'R')
	BEGIN
		SET @SqlCmd2Table = REPLACE(@SqlCmd2Table, '{@Zero}',				'>')
		SET @SqlCmd2Table = REPLACE(@SqlCmd2Table, '{@ASCDESC}',			'DESC')
	END
	IF (@VariationType = 'I')
	BEGIN
		SET @SqlCmd2Table = REPLACE(@SqlCmd2Table, '{@Zero}',				'<')
		SET @SqlCmd2Table = REPLACE(@SqlCmd2Table, '{@ASCDESC}',			'ASC')
	END
	-- Based on @VariationType, adapt results' ordering - END

	IF (@VerboseMode = 1) PRINT (@SqlCmd2Table)
	IF (@TestMode = 0)	EXEC (@SqlCmd2Table)
END
-- Output to table - END

RETURN
END

GO