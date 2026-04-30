using Dapper;
using Npgsql;

namespace HpcLite.Scheduler.Repositories;

public class SchedulerRepository
{
    private readonly string _connectionString;

    public SchedulerRepository(IConfiguration configuration)
    {
        _connectionString = configuration.GetConnectionString("Postgres")!;
    }

    private NpgsqlConnection Open() => new(_connectionString);

    public async Task<int> ActivateAsync(string host)
    {
        using var conn = Open();
        return await conn.ExecuteAsync(
            "UPDATE scheduler.schedulers SET status='active', started_at=NOW(), heartbeat=NOW() WHERE host=@host",
            new { host });
    }

    public async Task UpdateHeartbeatAsync(string host)
    {
        using var conn = Open();
        await conn.ExecuteAsync(
            "UPDATE scheduler.schedulers SET heartbeat=NOW() WHERE host=@host",
            new { host });
    }

    public async Task DeactivateAsync(string host)
    {
        using var conn = Open();
        await conn.ExecuteAsync(
            "UPDATE scheduler.schedulers SET status='inactive' WHERE host=@host",
            new { host });
    }

    public async Task<IEnumerable<SchedulerRecord>> GetAllAsync()
    {
        using var conn = Open();
        return await conn.QueryAsync<SchedulerRecord>(
            "SELECT id, name, host, status, started_at, heartbeat FROM scheduler.schedulers ORDER BY id");
    }

    public async Task UpsertSchedulerAsync(string name, string host)
    {
        using var conn = Open();
        await conn.ExecuteAsync(
            @"INSERT INTO scheduler.schedulers (name, host)
              VALUES (@name, @host)
              ON CONFLICT (host) DO UPDATE
                SET name = EXCLUDED.name",
            new { name, host });
    }
}

public class SchedulerRecord
{
    public long      Id        { get; set; }
    public string    Name      { get; set; } = "";
    public string    Host      { get; set; } = "";
    public string    Status    { get; set; } = "";
    public DateTime? StartedAt { get; set; }
    public DateTime? Heartbeat { get; set; }
}
