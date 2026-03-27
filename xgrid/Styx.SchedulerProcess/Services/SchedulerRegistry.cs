using Dapper;
using Npgsql;

namespace Styx.SchedulerProcess.Services;

public class SchedulerRegistry
{
    private readonly string _connectionString;

    public SchedulerRegistry(string connectionString)
    {
        _connectionString = connectionString;
    }

    /// <summary>
    /// Reads the scheduler_id set by the API, updates the row with the real PID,
    /// and returns the schedulerId so the process can use it for heartbeats.
    /// </summary>
    public async Task<long> RegisterAsync(string jobPath, long modelJobId, int pid)
    {
        await using var conn = new NpgsqlConnection(_connectionString);

        var schedulerId = await conn.ExecuteScalarAsync<long?>(
            "SELECT scheduler_id FROM model_job WHERE id = @modelJobId",
            new { modelJobId });

        if (!schedulerId.HasValue)
            throw new InvalidOperationException($"No scheduler_id found on model_job {modelJobId}. Was it dispatched by the API?");

        await conn.ExecuteAsync(
            "UPDATE schedulers SET pid = @pid WHERE id = @schedulerId",
            new { pid, schedulerId = schedulerId.Value });

        return schedulerId.Value;
    }

    public async Task UnregisterAsync(long schedulerId, long modelJobId)
    {
        await using var conn = new NpgsqlConnection(_connectionString);
        await conn.ExecuteAsync(
            "UPDATE schedulers SET status = 'dead' WHERE id = @schedulerId",
            new { schedulerId });
        await conn.ExecuteAsync(
            "UPDATE model_job SET scheduler_id = NULL WHERE id = @modelJobId",
            new { modelJobId });
    }
}
