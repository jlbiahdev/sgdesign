using Dapper;
using Npgsql;
using Styx.JobApi.Models;

namespace Styx.JobApi.Repositories;

public class SchedulerRepository
{
    private readonly string _connectionString;

    public SchedulerRepository(string connectionString)
    {
        _connectionString = connectionString;
    }

    public async Task<int> CountActiveAsync(int heartbeatTimeoutSeconds)
    {
        await using var conn = new NpgsqlConnection(_connectionString);
        return await conn.ExecuteScalarAsync<int>(
            $"SELECT COUNT(*) FROM schedulers WHERE status = 'active' AND heartbeat > NOW() - INTERVAL '{heartbeatTimeoutSeconds} seconds'");
    }

    public async Task<long> InsertAsync(NpgsqlConnection conn, NpgsqlTransaction tx, long modelJobId, string jobPath)
    {
        return await conn.ExecuteScalarAsync<long>(
            @"INSERT INTO schedulers (pid, host, model_job_id, job_path, status, started_at, heartbeat)
              VALUES (0, @host, @modelJobId, @jobPath, 'active', NOW(), NOW())
              RETURNING id",
            new { host = Environment.MachineName, modelJobId, jobPath }, tx);
    }

    public async Task UpdatePidAsync(long schedulerId, int pid)
    {
        await using var conn = new NpgsqlConnection(_connectionString);
        await conn.ExecuteAsync(
            "UPDATE schedulers SET pid = @pid WHERE id = @schedulerId",
            new { pid, schedulerId });
    }

    public async Task<IEnumerable<Scheduler>> GetExpiredAsync(int heartbeatTimeoutSeconds)
    {
        await using var conn = new NpgsqlConnection(_connectionString);
        return await conn.QueryAsync<Scheduler>(
            $@"SELECT id, pid, host, model_job_id AS ModelJobId, job_path AS JobPath,
                      status, started_at AS StartedAt, heartbeat
               FROM schedulers
               WHERE status = 'active'
               AND heartbeat < NOW() - INTERVAL '{heartbeatTimeoutSeconds} seconds'");
    }

    public async Task<IEnumerable<Scheduler>> GetAllActiveAsync()
    {
        await using var conn = new NpgsqlConnection(_connectionString);
        return await conn.QueryAsync<Scheduler>(
            @"SELECT id, pid, host, model_job_id AS ModelJobId, job_path AS JobPath,
                     status, started_at AS StartedAt, heartbeat
              FROM schedulers WHERE status = 'active'");
    }

    public async Task MarkDeadAsync(long schedulerId)
    {
        await using var conn = new NpgsqlConnection(_connectionString);
        await conn.ExecuteAsync(
            "UPDATE schedulers SET status = 'dead' WHERE id = @schedulerId",
            new { schedulerId });
    }
}
