using HpcLite.Scheduler.Repositories;

namespace HpcLite.Scheduler.Services;

public class WatchdogService : BackgroundService
{
    private readonly RunnerRepository    _runnerRepo;
    private readonly ModelJobRepository  _modelJobRepo;
    private readonly RunnerDispatchService _dispatch;
    private readonly IAlertService       _alerts;
    private readonly IConfiguration      _configuration;
    private readonly ILogger<WatchdogService> _logger;

    public WatchdogService(
        RunnerRepository runnerRepo,
        ModelJobRepository modelJobRepo,
        RunnerDispatchService dispatch,
        IAlertService alerts,
        IConfiguration configuration,
        ILogger<WatchdogService> logger)
    {
        _runnerRepo   = runnerRepo;
        _modelJobRepo = modelJobRepo;
        _dispatch     = dispatch;
        _alerts       = alerts;
        _configuration = configuration;
        _logger       = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var intervalSeconds = _configuration.GetValue<int>("Orchestrator:WatchdogIntervalSeconds", 15);

        while (!stoppingToken.IsCancellationRequested)
        {
            try { await TickAsync(); }
            catch (Exception ex) { _logger.LogError(ex, "[Watchdog] Unexpected error"); }

            await Task.Delay(TimeSpan.FromSeconds(intervalSeconds), stoppingToken);
        }
    }

    private async Task TickAsync()
    {
        var timeoutSeconds = _configuration.GetValue<int>("Orchestrator:HeartbeatTimeoutSeconds", 60);
        var expired        = await _runnerRepo.GetExpiredRunnersAsync(timeoutSeconds);

        foreach (var runner in expired)
        {
            _logger.LogError(
                "[Watchdog] Runner {Name} (PID {Pid} on {Host}) timed out. ModelJob {ModelJobId} marked Failed.",
                runner.Name, runner.Pid, runner.Host, runner.ModelJobId);

            await _runnerRepo.ReleaseRunnerAsync(runner.Id);

            if (runner.ModelJobId.HasValue)
            {
                await _modelJobRepo.FailDataJobsAsync(runner.ModelJobId.Value);
                await _modelJobRepo.ClearRunnerAsync(runner.ModelJobId.Value);
                await _alerts.NotifyAsync(runner.Id, runner.ModelJobId.Value);
            }
        }

        // Retry queued jobs
        var pendingIds = await _modelJobRepo.GetPendingModelJobIdsAsync();
        foreach (var modelJobId in pendingIds)
        {
            var job = await _modelJobRepo.GetByIdAsync(modelJobId);
            if (job is null) continue;

            // settings_path not stored on the Scheduler side — retry only possible if Styx re-calls /schedule
            // Log for observability; the caller is responsible for re-submitting
            _logger.LogInformation("[Watchdog] model_job {Id} is queued but has no active runner.", modelJobId);
        }
    }
}
