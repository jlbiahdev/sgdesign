using Dapper;
using Npgsql;

namespace HpcLite.Scheduler.Repositories;

public class RunnerRepository
{
    private readonly string _connectionString;

    public RunnerRepository(IConfiguration configuration)
    {
        _connectionString = configuration.GetConnectionString("Postgres")!;
    }

    private NpgsqlConnection Open() => new(_connectionString);

    public async Task<RunnerRecord?> ClaimIdleRunnerAsync(long modelJobId)
    {
        using var conn = Open();
        await conn.OpenAsync();
        using var tx = await conn.BeginTransactionAsync();

        var runner = await conn.QuerySingleOrDefaultAsync<RunnerRecord>(
            @"SELECT id, name, host, exe_path
              FROM runners
              WHERE status = 'idle'
              ORDER BY id ASC
              LIMIT 1
              FOR UPDATE SKIP LOCKED",
            transaction: tx);

        if (runner is null)
        {
            await tx.RollbackAsync();
            return null;
        }

        await conn.ExecuteAsync(
            "UPDATE runners SET status='active', model_job_id=@modelJobId, started_at=NOW() WHERE id=@id",
            new { modelJobId, id = runner.Id }, tx);

        await tx.CommitAsync();
        return runner;
    }

    public async Task ReleaseRunnerAsync(long runnerId)
    {
        using var conn = Open();
        await conn.ExecuteAsync(
            "UPDATE runners SET status='idle', model_job_id=NULL, pid=NULL WHERE id=@id",
            new { id = runnerId });
    }

    public async Task<IEnumerable<RunnerRecord>> GetExpiredRunnersAsync(int heartbeatTimeoutSeconds)
    {
        using var conn = Open();
        return await conn.QueryAsync<RunnerRecord>(
            $@"SELECT id, name, pid, host, model_job_id, exe_path
               FROM runners
               WHERE status = 'active'
               AND heartbeat < NOW() - INTERVAL '{heartbeatTimeoutSeconds} seconds'");
    }

    public async Task<IEnumerable<RunnerPingRecord>> GetAllForPingAsync(int heartbeatTimeoutSeconds)
    {
        using var conn = Open();
        return await conn.QueryAsync<RunnerPingRecord>(
            $@"SELECT id, name, host, status, model_job_id, heartbeat,
                      CASE WHEN status = 'idle' THEN NULL
                           ELSE (heartbeat > NOW() - INTERVAL '{heartbeatTimeoutSeconds} seconds')
                      END AS is_alive
               FROM runners");
    }

    public async Task UpsertRunnerAsync(string name, string host, string exePath)
    {
        using var conn = Open();
        await conn.ExecuteAsync(
            @"INSERT INTO runners (name, host, exe_path)
              VALUES (@name, @host, @exePath)
              ON CONFLICT (name) DO UPDATE
                SET host     = EXCLUDED.host,
                    exe_path = EXCLUDED.exe_path",
            new { name, host, exePath });
    }
}

public class RunnerRecord
{
    public long    Id          { get; set; }
    public string  Name        { get; set; } = "";
    public int?    Pid         { get; set; }
    public string  Host        { get; set; } = "";
    public string  ExePath     { get; set; } = "";
    public long?   ModelJobId  { get; set; }
}

public class RunnerPingRecord
{
    public long    Id          { get; set; }
    public string  Name        { get; set; } = "";
    public string  Host        { get; set; } = "";
    public string  Status      { get; set; } = "";
    public long?   ModelJobId  { get; set; }
    public DateTime? Heartbeat { get; set; }
    public bool?   IsAlive     { get; set; }
}
