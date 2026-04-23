using Dapper;
using Npgsql;

namespace HpcLite.Runner.Repositories;

public class ModelJobRepository
{
    private readonly string _connectionString;

    public ModelJobRepository(string connectionString)
    {
        _connectionString = connectionString;
    }

    private NpgsqlConnection Open() => new(_connectionString);

    public async Task ClearRunnerAsync(long modelJobId)
    {
        using var conn = Open();
        await conn.ExecuteAsync(
            "UPDATE model_job SET runner_id=NULL WHERE id=@modelJobId",
            new { modelJobId });
    }
}
