using System.Text.Json;
using Dapper;
using Npgsql;

namespace HpcLite.Scheduler.Services;

/// Listens on PostgreSQL channel 'taskflow_events'.
/// When a TaskFlow task reaches a terminal state, propagates the result to
/// data_task → data_job, then triggers Light dispatch for newly-unblocked jobs.
public class TaskFlowCompletionListener : BackgroundService
{
    private const string Channel = "taskflow_events";

    private readonly string _connectionString;
    private readonly LightJobDispatchService _lightDispatcher;
    private readonly ILogger<TaskFlowCompletionListener> _logger;

    public TaskFlowCompletionListener(
        IConfiguration configuration,
        LightJobDispatchService lightDispatcher,
        ILogger<TaskFlowCompletionListener> logger)
    {
        _connectionString = configuration.GetConnectionString("Postgres")!;
        _lightDispatcher  = lightDispatcher;
        _logger           = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await ListenLoopAsync(stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break;
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "[TaskFlowCompletion] LISTEN connection lost — reconnecting in 5s");
                await Task.Delay(TimeSpan.FromSeconds(5), stoppingToken);
            }
        }
    }

    private async Task ListenLoopAsync(CancellationToken ct)
    {
        await using var conn = new NpgsqlConnection(_connectionString);
        await conn.OpenAsync(ct);

        conn.Notification += (_, args) =>
        {
            _ = HandleNotificationAsync(args.Payload, ct);
        };

        await using (var cmd = conn.CreateCommand())
        {
            cmd.CommandText = $"LISTEN {Channel}";
            await cmd.ExecuteNonQueryAsync(ct);
        }

        _logger.LogInformation("[TaskFlowCompletion] Listening on '{Channel}'", Channel);

        while (!ct.IsCancellationRequested)
            await conn.WaitAsync(ct);
    }

    private async Task HandleNotificationAsync(string payload, CancellationToken ct)
    {
        TaskFlowEvent? evt;
        try
        {
            evt = JsonSerializer.Deserialize<TaskFlowEvent>(payload, JsonOptions);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "[TaskFlowCompletion] Failed to parse payload: {Payload}", payload);
            return;
        }

        if (evt is null || evt.State is not ("Finished" or "Failed"))
            return;

        _logger.LogDebug("[TaskFlowCompletion] taskflow task {TaskId} → {State}", evt.TaskId, evt.State);

        try
        {
            await ProcessCompletionAsync(evt, ct);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex,
                "[TaskFlowCompletion] Error processing completion for taskflow task {TaskId}", evt.TaskId);
        }
    }

    private async Task ProcessCompletionAsync(TaskFlowEvent evt, CancellationToken ct)
    {
        await using var conn = new NpgsqlConnection(_connectionString);
        await conn.OpenAsync(ct);

        // Resolve external_id from taskflow.task
        var externalId = await conn.QuerySingleOrDefaultAsync<long?>(
            "SELECT external_id FROM taskflow.task WHERE id = @id",
            new { id = evt.TaskId });

        if (externalId is null)
        {
            _logger.LogWarning("[TaskFlowCompletion] taskflow.task {Id} not found", evt.TaskId);
            return;
        }

        // Update data_task state
        var affected = await conn.ExecuteAsync(
            @"UPDATE data_task SET task_state = @state
              WHERE external_id = @externalId
                AND task_state NOT IN ('Finished', 'Failed', 'Canceled')",
            new { state = evt.State, externalId });

        if (affected == 0)
            return; // already terminal or unknown external_id

        // Find the parent data_job
        var dataJobId = await conn.QuerySingleOrDefaultAsync<long?>(
            "SELECT data_job_id FROM data_task WHERE external_id = @externalId LIMIT 1",
            new { externalId });

        if (dataJobId is null)
            return;

        // Check whether all tasks are now terminal
        var pendingCount = await conn.QuerySingleAsync<int>(
            @"SELECT COUNT(*) FROM data_task
              WHERE data_job_id = @dataJobId
                AND task_state NOT IN ('Finished', 'Failed', 'Canceled')",
            new { dataJobId });

        if (pendingCount > 0)
            return;

        // All tasks terminal — determine data_job outcome
        var failedCount = await conn.QuerySingleAsync<int>(
            "SELECT COUNT(*) FROM data_task WHERE data_job_id = @dataJobId AND task_state = 'Failed'",
            new { dataJobId });

        var newJobState = failedCount > 0 ? "Failed" : "Finished";

        await conn.ExecuteAsync(
            @"UPDATE data_job
              SET state            = @state,
                  progress         = CASE WHEN @state = 'Finished' THEN 100 ELSE progress END,
                  change_date_time = NOW()
              WHERE id = @dataJobId AND state = 'Running'",
            new { state = newJobState, dataJobId });

        _logger.LogInformation(
            "[TaskFlowCompletion] data_job {JobId} → {State}", dataJobId, newJobState);

        // A Finished data_job may unblock dependent jobs
        if (newJobState == "Finished")
            await _lightDispatcher.TryDispatchAllPendingAsync();
    }

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true
    };

    private sealed record TaskFlowEvent(long TaskId, string State);
}
