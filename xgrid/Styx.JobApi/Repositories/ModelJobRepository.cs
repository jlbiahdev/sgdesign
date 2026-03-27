using Dapper;
using Npgsql;
using Styx.Domain.Models;

namespace Styx.JobApi.Repositories;

public class ModelJobRepository
{
    private readonly string _connectionString;

    public ModelJobRepository(string connectionString)
    {
        _connectionString = connectionString;
    }

    public async Task<ModelJob?> GetByIdAsync(long id)
    {
        await using var conn = new NpgsqlConnection(_connectionString);
        return await conn.QuerySingleOrDefaultAsync<ModelJob>(
            "SELECT * FROM model_job WHERE id = @id",
            new { id });
    }

    public async Task<bool> TryLockForDispatchAsync(NpgsqlConnection conn, NpgsqlTransaction tx, long modelJobId)
    {
        var result = await conn.QuerySingleOrDefaultAsync<long?>(
            "SELECT id FROM model_job WHERE id = @modelJobId AND scheduler_id IS NULL FOR UPDATE SKIP LOCKED",
            new { modelJobId }, tx);
        return result.HasValue;
    }

    public async Task SetSchedulerIdAsync(NpgsqlConnection conn, NpgsqlTransaction tx, long modelJobId, long schedulerId)
    {
        await conn.ExecuteAsync(
            "UPDATE model_job SET scheduler_id = @schedulerId WHERE id = @modelJobId",
            new { schedulerId, modelJobId }, tx);
    }

    public async Task SetJobPathAsync(NpgsqlConnection conn, NpgsqlTransaction tx, long modelJobId, string jobPath)
    {
        await conn.ExecuteAsync(
            "UPDATE model_job SET job_path = @jobPath WHERE id = @modelJobId",
            new { jobPath, modelJobId }, tx);
    }

    public async Task ClearSchedulerIdAsync(long modelJobId)
    {
        await using var conn = new NpgsqlConnection(_connectionString);
        await conn.ExecuteAsync(
            "UPDATE model_job SET scheduler_id = NULL WHERE id = @modelJobId",
            new { modelJobId });
    }

    public async Task<IEnumerable<ModelJob>> GetQueuedWithoutSchedulerAsync()
    {
        await using var conn = new NpgsqlConnection(_connectionString);
        return await conn.QueryAsync<ModelJob>(
            @"SELECT DISTINCT mj.* FROM model_job mj
              WHERE mj.scheduler_id IS NULL
              AND mj.job_path IS NOT NULL
              AND EXISTS (
                  SELECT 1 FROM data_job dj
                  WHERE dj.parent_model_id = mj.id
                  AND dj.state NOT IN ('Finished', 'Failed', 'Canceled')
              )");
    }
}
