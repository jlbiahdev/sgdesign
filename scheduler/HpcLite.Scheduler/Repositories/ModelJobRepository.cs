using Dapper;
using Npgsql;

namespace HpcLite.Scheduler.Repositories;

public class ModelJobRepository
{
    private readonly string _connectionString;

    public ModelJobRepository(IConfiguration configuration)
    {
        _connectionString = configuration.GetConnectionString("Postgres")!;
    }

    private NpgsqlConnection Open() => new(_connectionString);

    public async Task<ModelJobRecord?> GetByIdAsync(long modelJobId)
    {
        using var conn = Open();
        return await conn.QuerySingleOrDefaultAsync<ModelJobRecord>(
            "SELECT id, name, runner_id FROM model_job WHERE id = @id",
            new { id = modelJobId });
    }

    public async Task<bool> TryAssignRunnerAsync(long modelJobId, long runnerId)
    {
        using var conn = Open();
        var rows = await conn.ExecuteAsync(
            "UPDATE model_job SET runner_id=@runnerId WHERE id=@id AND runner_id IS NULL",
            new { runnerId, id = modelJobId });
        return rows > 0;
    }

    public async Task ClearRunnerAsync(long modelJobId)
    {
        using var conn = Open();
        await conn.ExecuteAsync(
            "UPDATE model_job SET runner_id=NULL WHERE id=@id",
            new { id = modelJobId });
    }

    public async Task FailDataJobsAsync(long modelJobId)
    {
        using var conn = Open();
        await conn.ExecuteAsync(
            @"UPDATE data_job SET state='Failed', change_date_time=NOW()
              WHERE parent_model_id=@modelJobId
              AND state NOT IN ('Finished','Failed','Canceled')",
            new { modelJobId });
    }

    public async Task<IEnumerable<long>> GetPendingModelJobIdsAsync()
    {
        using var conn = Open();
        return await conn.QueryAsync<long>(
            @"SELECT DISTINCT dj.parent_model_id
              FROM data_job dj
              JOIN model_job mj ON mj.id = dj.parent_model_id
              WHERE mj.runner_id IS NULL
              AND dj.state = 'Queued'");
    }
}

public class ModelJobRecord
{
    public long   Id       { get; set; }
    public string Name     { get; set; } = "";
    public long?  RunnerId { get; set; }
}
