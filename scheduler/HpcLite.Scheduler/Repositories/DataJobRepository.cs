using Dapper;
using Npgsql;

namespace HpcLite.Scheduler.Repositories;

public class DataJobDispatchRecord
{
    public long   Id             { get; set; }
    public int    JobCommandType { get; set; }
    public long   ParentModelId  { get; set; }
    public string TemplateFolder { get; set; } = "";
}

public class DataTaskRecord
{
    public long    Id          { get; set; }
    public int     TaskIndex   { get; set; }
    public long    ExternalId  { get; set; }
    public string  TaskName    { get; set; } = "";
    public string  CommandExe  { get; set; } = "";
    public string? CommandArgs { get; set; }
}

public class DataJobRepository
{
    private readonly string _connectionString;

    public DataJobRepository(IConfiguration configuration)
    {
        _connectionString = configuration.GetConnectionString("Postgres")!;
    }

    private NpgsqlConnection Open() => new(_connectionString);

    /// Atomically claims all dispatchable Light (job_command_type = 0) data_jobs and marks them Running.
    /// A data_job is dispatchable when it is Queued and has no unfinished parents in data_job_parent.
    public async Task<IReadOnlyList<DataJobDispatchRecord>> ClaimDispatchableLightJobsAsync()
    {
        await using var conn = Open();
        await conn.OpenAsync();
        await using var tx = await conn.BeginTransactionAsync();

        var jobs = (await conn.QueryAsync<DataJobDispatchRecord>(
            @"SELECT dj.id, dj.job_command_type, dj.parent_model_id, mj.template_folder
              FROM data_job dj
              JOIN model_job mj ON mj.id = dj.parent_model_id
              WHERE dj.state = 'Queued'
                AND dj.job_command_type = 0
                AND NOT EXISTS (
                    SELECT 1 FROM data_job_parent djp
                    JOIN data_job p ON p.id = djp.parent_job_id
                    WHERE djp.job_id = dj.id
                      AND p.state != 'Finished'
                )
              ORDER BY dj.id ASC
              FOR UPDATE OF dj SKIP LOCKED",
            transaction: tx)).AsList();

        if (jobs.Count == 0)
        {
            await tx.RollbackAsync();
            return [];
        }

        var ids = jobs.Select(j => j.Id).ToArray();
        await conn.ExecuteAsync(
            @"UPDATE data_job
              SET state = 'Running', start_date_time = NOW(), change_date_time = NOW()
              WHERE id = ANY(@ids)",
            new { ids }, tx);

        await tx.CommitAsync();
        return jobs;
    }

    public async Task<IReadOnlyList<DataTaskRecord>> GetTasksAsync(long dataJobId)
    {
        await using var conn = Open();
        return (await conn.QueryAsync<DataTaskRecord>(
            @"SELECT id, task_index, external_id, task_name, command_exe, command_args
              FROM data_task
              WHERE data_job_id = @dataJobId
                AND task_state NOT IN ('Finished', 'Failed', 'Canceled')
              ORDER BY task_index ASC",
            new { dataJobId })).AsList();
    }

    public async Task RevertToQueuedAsync(long dataJobId)
    {
        await using var conn = Open();
        await conn.ExecuteAsync(
            "UPDATE data_job SET state = 'Queued', change_date_time = NOW() WHERE id = @id",
            new { id = dataJobId });
    }
}
