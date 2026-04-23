using Dapper;
using Npgsql;

namespace HpcLite.Runner.Repositories;

public class RunnerRepository
{
    private readonly string _connectionString;

    public RunnerRepository(string connectionString)
    {
        _connectionString = connectionString;
    }

    private NpgsqlConnection Open() => new(_connectionString);

    public async Task ActivateAsync(long runnerId, long modelJobId)
    {
        using var conn = Open();
        await conn.ExecuteAsync(
            @"UPDATE runners
              SET status='active', pid=@pid, model_job_id=@modelJobId,
                  started_at=NOW(), heartbeat=NOW()
              WHERE id=@runnerId",
            new { pid = Environment.ProcessId, modelJobId, runnerId });
    }

    public async Task UpdateHeartbeatAsync(long runnerId)
    {
        using var conn = Open();
        await conn.ExecuteAsync(
            "UPDATE runners SET heartbeat=NOW() WHERE id=@runnerId",
            new { runnerId });
    }

    public async Task DeactivateAsync(long runnerId)
    {
        using var conn = Open();
        await conn.ExecuteAsync(
            "UPDATE runners SET status='idle', pid=NULL, model_job_id=NULL WHERE id=@runnerId",
            new { runnerId });
    }
}
