using Dapper;
using Npgsql;
using Styx.Domain.Models;

namespace Styx.JobApi.Repositories;

public class DataJobRepository
{
    private readonly string _connectionString;

    public DataJobRepository(string connectionString)
    {
        _connectionString = connectionString;
    }

    public async Task<IEnumerable<DataJob>> GetByModelJobIdAsync(long modelJobId)
    {
        await using var conn = new NpgsqlConnection(_connectionString);
        return await conn.QueryAsync<DataJob>(
            "SELECT * FROM data_job WHERE parent_model_id = @modelJobId",
            new { modelJobId });
    }

    public async Task<IEnumerable<(long JobId, long ParentJobId)>> GetParentIdsAsync(long modelJobId)
    {
        await using var conn = new NpgsqlConnection(_connectionString);
        var rows = await conn.QueryAsync(
            @"SELECT djp.job_id, djp.parent_job_id
              FROM data_job_parent djp
              JOIN data_job dj ON dj.id = djp.job_id
              WHERE dj.parent_model_id = @modelJobId",
            new { modelJobId });
        return rows.Select(r => ((long)r.job_id, (long)r.parent_job_id));
    }

    public async Task FailAllActiveAsync(long modelJobId)
    {
        await using var conn = new NpgsqlConnection(_connectionString);
        await conn.ExecuteAsync(
            @"UPDATE data_job SET state = 'Failed', change_date_time = NOW()
              WHERE parent_model_id = @modelJobId
              AND state NOT IN ('Finished', 'Failed', 'Canceled')",
            new { modelJobId });
    }
}
