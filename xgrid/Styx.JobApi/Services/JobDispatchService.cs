using Npgsql;
using Styx.JobApi.Repositories;

namespace Styx.JobApi.Services;

public class JobDispatchService
{
    private readonly SchedulerRepository _schedulerRepo;
    private readonly ModelJobRepository _modelJobRepo;
    private readonly SchedulerLauncher _launcher;
    private readonly string _connectionString;
    private readonly int _maxConcurrentSchedulers;
    private readonly int _heartbeatTimeoutSeconds;
    private readonly ILogger<JobDispatchService> _logger;

    public JobDispatchService(
        SchedulerRepository schedulerRepo,
        ModelJobRepository modelJobRepo,
        SchedulerLauncher launcher,
        IConfiguration config,
        ILogger<JobDispatchService> logger)
    {
        _schedulerRepo = schedulerRepo;
        _modelJobRepo = modelJobRepo;
        _launcher = launcher;
        _connectionString = config.GetConnectionString("Postgres")!;
        _maxConcurrentSchedulers = config.GetValue<int>("Orchestrator:MaxConcurrentSchedulers");
        _heartbeatTimeoutSeconds = config.GetValue<int>("Orchestrator:HeartbeatTimeoutSeconds");
        _logger = logger;
    }

    public async Task<string> TryDispatchAsync(long modelJobId, string jobPath)
    {
        var activeCount = await _schedulerRepo.CountActiveAsync(_heartbeatTimeoutSeconds);
        if (activeCount >= _maxConcurrentSchedulers)
        {
            _logger.LogInformation("No slot available — model_job {Id} remains Queued", modelJobId);
            return "queued";
        }

        await using var conn = new NpgsqlConnection(_connectionString);
        await conn.OpenAsync();
        await using var tx = await conn.BeginTransactionAsync();

        var locked = await _modelJobRepo.TryLockForDispatchAsync(conn, tx, modelJobId);
        if (!locked)
        {
            await tx.RollbackAsync();
            _logger.LogInformation("ModelJob {Id} already dispatched or locked", modelJobId);
            return "queued";
        }

        var schedulerId = await _schedulerRepo.InsertAsync(conn, tx, modelJobId, jobPath);
        await _modelJobRepo.SetSchedulerIdAsync(conn, tx, modelJobId, schedulerId);
        await tx.CommitAsync();

        await _launcher.SpawnAsync(modelJobId, jobPath, schedulerId);
        return "dispatched";
    }
}
