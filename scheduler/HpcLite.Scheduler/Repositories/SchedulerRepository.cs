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
            "UPDATE schedulers SET status='active', started_at=NOW(), heartbeat=NOW() WHERE host=@host",
            new { host });
    }

    public async Task UpdateHeartbeatAsync(string host)
    {
        using var conn = Open();
        await conn.ExecuteAsync(
            "UPDATE schedulers SET heartbeat=NOW() WHERE host=@host",
            new { host });
    }

    public async Task DeactivateAsync(string host)
    {
        using var conn = Open();
        await conn.ExecuteAsync(
            "UPDATE schedulers SET status='inactive' WHERE host=@host",
            new { host });
    }

    public async Task<IEnumerable<SchedulerRecord>> GetAllAsync()
    {
        using var conn = Open();
        return await conn.QueryAsync<SchedulerRecord>(
            "SELECT id, name, host, status, started_at, heartbeat FROM schedulers ORDER BY id");
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
