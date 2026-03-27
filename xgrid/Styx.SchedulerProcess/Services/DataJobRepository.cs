using Dapper;
using Npgsql;

namespace Styx.SchedulerProcess.Services;

public class DataJobRepository
{
    private readonly string _connectionString;

    public DataJobRepository(string connectionString)
    {
        _connectionString = connectionString;
    }

    public async Task SetRunningAsync(long id)
    {
        await using var conn = new NpgsqlConnection(_connectionString);
        await conn.ExecuteAsync(
            "UPDATE data_job SET state = 'Running', start_date_time = NOW(), change_date_time = NOW() WHERE id = @id",
            new { id });
    }

    public async Task SetFinishedAsync(long id)
    {
        await using var conn = new NpgsqlConnection(_connectionString);
        await conn.ExecuteAsync(
            "UPDATE data_job SET state = 'Finished', progress = 100, change_date_time = NOW() WHERE id = @id",
            new { id });
    }

    public async Task SetFailedAsync(long id, string? errorDetail = null)
    {
        await using var conn = new NpgsqlConnection(_connectionString);
        await conn.ExecuteAsync(
            "UPDATE data_job SET state = 'Failed', change_date_time = NOW() WHERE id = @id",
            new { id });
        // errorDetail can be logged or stored in a dedicated column if the schema supports it
        if (errorDetail is not null)
            Console.Error.WriteLine($"[DataJob {id}] Failed: {errorDetail}");
    }

    public async Task FailAllAsync(long modelJobId)
    {
        await using var conn = new NpgsqlConnection(_connectionString);
        await conn.ExecuteAsync(
            @"UPDATE data_job SET state = 'Failed', change_date_time = NOW()
              WHERE parent_model_id = @modelJobId
              AND state NOT IN ('Finished', 'Failed', 'Canceled')",
            new { modelJobId });
    }
}
