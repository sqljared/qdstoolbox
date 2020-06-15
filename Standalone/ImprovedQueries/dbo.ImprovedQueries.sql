SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [dbo].[ImprovedQueries]
(
	@ImprovedQueriesTable NVARCHAR(800) = NULL,
	@measurement	VARCHAR(32),
	@metric			VARCHAR(16),
	@results_row_count INT = 25,
	@recent_start_time DATETIME2 = NULL,
	@recent_end_time DATETIME2 = NULL,
	@history_start_time DATETIME2 = NULL,
	@history_end_time DATETIME2 = NULL,
	@min_exec_count TINYINT = 1,
	@min_plan_count TINYINT = 1,
	@max_plan_count INT = 99999
)
AS
SET NOCOUNT ON
DECLARE @Error BIT = 0

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


DECLARE @ValidMeasurement TABLE
(
	[MeasurementName] VARCHAR(32)
)
INSERT INTO @ValidMeasurement VALUES('CLR')
INSERT INTO @ValidMeasurement VALUES('CPU')
INSERT INTO @ValidMeasurement VALUES('DOP')
INSERT INTO @ValidMeasurement VALUES('Duration')
INSERT INTO @ValidMeasurement VALUES('Log')
INSERT INTO @ValidMeasurement VALUES('LogicalIOReads')
INSERT INTO @ValidMeasurement VALUES('LogicalIOWrites')
INSERT INTO @ValidMeasurement VALUES('MaxMemory')
INSERT INTO @ValidMeasurement VALUES('PhysicalIOReads')
INSERT INTO @ValidMeasurement VALUES('Rowcount')
INSERT INTO @ValidMeasurement VALUES('TempDB')

IF @measurement NOT IN (SELECT [MeasurementName] FROM @ValidMeasurement)
BEGIN
	SELECT [MeasurementName] AS [List of accepted values for @measurement]
	FROM @ValidMeasurement
	RAISERROR('No valid value for @measurement has been provided, check the provided table for reference',0,1)
	SET @Error = 1
END

DECLARE @ValidMetric TABLE
(
	[MetricName] VARCHAR(16)
)
INSERT INTO @ValidMetric VALUES('Avg')
INSERT INTO @ValidMetric VALUES('Max')
INSERT INTO @ValidMetric VALUES('Min')
INSERT INTO @ValidMetric VALUES('StdDev')
INSERT INTO @ValidMetric VALUES('Total')

IF @metric NOT IN (SELECT [MetricName] FROM @ValidMetric)
BEGIN
	SELECT [MetricName] AS [List of accepted values for @metric]
	FROM @ValidMetric
	RAISERROR('No valid value for @metric has been provided, check the provided table for reference',0,1)
	SET @Error = 1
END

IF (@Error = 1)
BEGIN
 RAISERROR('Errors found in the input parameters, see messages above', 16, 0)
 RETURN
END


IF (@Error = 0)
BEGIN
	DECLARE @SqlCmd VARCHAR(MAX)
	SET @SqlCmd = 'EXECUTE [dbo].[ImprovedQueries_'+@measurement+'_'+@metric+']
	 @ImprovedQueriesTable = '''+ISNULL(@ImprovedQueriesTable,'')+''',
	 @measurement = ''' +@measurement+''',
	 @metric = '''+@metric+''',
	 @results_row_count = '+convert(varchar(3), @results_row_count)+',
	 @recent_start_time = '''+convert(varchar(25), @recent_start_time, 120)+''',
	 @recent_end_time = '''+convert(varchar(25), @recent_end_time, 120)+''',
	 @history_start_time = '''+convert(varchar(25), @history_start_time, 120)+''',
	 @history_end_time = '''+CONVERT(VARCHAR(25),@history_end_time,120)+''',
	 @min_exec_count = '+CAST(@min_exec_count AS VARCHAR(10))+',
	 @min_plan_count = '+CAST(@min_plan_count AS VARCHAR(10))+',
	 @max_plan_count = '+CAST(@max_plan_count AS VARCHAR(10))+';'
	EXECUTE (@SqlCmd)
END

GO


