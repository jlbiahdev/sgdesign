using Styx.JobApi.Repositories;

namespace Styx.JobApi.Services;

public class WatchdogService : BackgroundService
{
    private readonly SchedulerRepository _schedulerRepo;
    private readonly ModelJobRepository _modelJobRepo;
    private readonly DataJobRepository _dataJobRepo;
    private readonly JobDispatchService _dispatchService;
    private readonly IAlertService _alertService;
    private readonly int _watchdogIntervalSeconds;
    private readonly int _heartbeatTimeoutSeconds;
    private readonly ILogger<WatchdogService> _logger;

    public WatchdogService(
        SchedulerRepository schedulerRepo,
        ModelJobRepository modelJobRepo,
        DataJobRepository dataJobRepo,
        JobDispatchService dispatchService,
        IAlertService alertService,
        IConfiguration config,
        ILogger<WatchdogService> logger)
    {
        _schedulerRepo = schedulerRepo;
        _modelJobRepo = modelJobRepo;
        _dataJobRepo = dataJobRepo;
        _dispatchService = dispatchService;
        _alertService = alertService;
        _watchdogIntervalSeconds = config.GetValue<int>("Orchestrator:WatchdogIntervalSeconds");
        _heartbeatTimeoutSeconds = config.GetValue<int>("Orchestrator:HeartbeatTimeoutSeconds");
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            await Task.Delay(TimeSpan.FromSeconds(_watchdogIntervalSeconds), stoppingToken);
            await RunCycleAsync();
        }
    }

    private async Task RunCycleAsync()
    {
        // 1. Detect expired schedulers
        var expired = await _schedulerRepo.GetExpiredAsync(_heartbeatTimeoutSeconds);

        foreach (var scheduler in expired)
        {
            _logger.LogError(
                "[Watchdog] Scheduler {Id} (PID {Pid} on {Host}) timed out. ModelJob {ModelJobId} marked Failed.",
                scheduler.Id, scheduler.Pid, scheduler.Host, scheduler.ModelJobId);

            await _schedulerRepo.MarkDeadAsync(scheduler.Id);

            if (scheduler.ModelJobId.HasValue)
            {
                await _dataJobRepo.FailAllActiveAsync(scheduler.ModelJobId.Value);
                await _modelJobRepo.ClearSchedulerIdAsync(scheduler.ModelJobId.Value);
                await _alertService.NotifyAsync(scheduler.Id, scheduler.ModelJobId.Value);
            }
        }

        // 2. Re-dispatch queued jobs that now have an available slot
        var queued = await _modelJobRepo.GetQueuedWithoutSchedulerAsync();
        foreach (var job in queued)
        {
            if (job.JobPath is null) continue;
            await _dispatchService.TryDispatchAsync(job.Id, job.JobPath);
        }
    }
}
