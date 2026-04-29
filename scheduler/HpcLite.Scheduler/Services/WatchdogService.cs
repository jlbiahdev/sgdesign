using HpcLite.Scheduler.Repositories;

namespace HpcLite.Scheduler.Services;

public class WatchdogService : BackgroundService
{
    private readonly RunnerRepository      _runnerRepo;
    private readonly ModelJobRepository    _modelJobRepo;
    private readonly RunnerDispatchService _dispatch;
    private readonly IAlertService         _alerts;
    private readonly IConfiguration        _configuration;
    private readonly ILogger<WatchdogService> _logger;

    public WatchdogService(
        RunnerRepository runnerRepo,
        ModelJobRepository modelJobRepo,
        RunnerDispatchService dispatch,
        IAlertService alerts,
        IConfiguration configuration,
        ILogger<WatchdogService> logger)
    {
        _runnerRepo    = runnerRepo;
        _modelJobRepo  = modelJobRepo;
        _dispatch      = dispatch;
        _alerts        = alerts;
        _configuration = configuration;
        _logger        = logger;
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

        var anyReleased = false;
        foreach (var runner in expired)
        {
            _logger.LogError(
                "[Watchdog] Runner '{Name}' (PID {Pid} on {Host}) timed out — model_job {ModelJobId} marked Failed.",
                runner.Name, runner.Pid, runner.Host, runner.ModelJobId);

            await _runnerRepo.ReleaseRunnerAsync(runner.Id);
            anyReleased = true;

            if (runner.ModelJobId.HasValue)
            {
                await _modelJobRepo.FailDataJobsAsync(runner.ModelJobId.Value);
                await _modelJobRepo.ClearRunnerAsync(runner.ModelJobId.Value);
                await _alerts.NotifyAsync(runner.Id, runner.ModelJobId.Value);
            }
        }

        // A runner just became free — immediately try to assign pending jobs to it.
        if (anyReleased)
            await _dispatch.TryDispatchAllPendingAsync();
    }
}
