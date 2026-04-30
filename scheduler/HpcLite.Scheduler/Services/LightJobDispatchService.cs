using System.Net.Http.Json;
using HpcLite.Scheduler.Repositories;

namespace HpcLite.Scheduler.Services;

/// Dispatches Light (job_command_type = 0) data_jobs to the TaskFlow runner.
/// For each dispatchable Queued data_job, marks it Running then POSTs each data_task
/// to the TaskFlow API as an individual task submission.
public class LightJobDispatchService
{
    private readonly DataJobRepository _dataJobRepo;
    private readonly IHttpClientFactory _httpFactory;
    private readonly string _taskFlowBaseUrl;
    private readonly ILogger<LightJobDispatchService> _logger;

    // Prevents concurrent dispatch loops from processing the same jobs.
    private readonly SemaphoreSlim _gate = new(1, 1);

    public LightJobDispatchService(
        DataJobRepository dataJobRepo,
        IHttpClientFactory httpFactory,
        IConfiguration configuration,
        ILogger<LightJobDispatchService> logger)
    {
        _dataJobRepo     = dataJobRepo;
        _httpFactory     = httpFactory;
        _taskFlowBaseUrl = configuration["TaskFlow:BaseUrl"]!.TrimEnd('/');
        _logger          = logger;
    }

    /// Called by JobListenerService (on NOTIFY or poll fallback) and WatchdogService.
    public async Task TryDispatchAllPendingAsync()
    {
        if (!await _gate.WaitAsync(0))
            return;

        try
        {
            var jobs = await _dataJobRepo.ClaimDispatchableLightJobsAsync();
            foreach (var job in jobs)
                await DispatchJobAsync(job);
        }
        finally
        {
            _gate.Release();
        }
    }

    private async Task DispatchJobAsync(DataJobDispatchRecord job)
    {
        var tasks = await _dataJobRepo.GetTasksAsync(job.Id);

        if (tasks.Count == 0)
        {
            _logger.LogWarning("[LightDispatch] data_job {Id} has no dispatchable tasks — skipping", job.Id);
            return;
        }

        _logger.LogInformation(
            "[LightDispatch] Submitting {Count} tasks for data_job {JobId} (model_job {ModelJobId})",
            tasks.Count, job.Id, job.ParentModelId);

        var client = _httpFactory.CreateClient();
        var url    = $"{_taskFlowBaseUrl}/taskflow/tasks";

        foreach (var task in tasks)
        {
            try
            {
                var response = await client.PostAsJsonAsync(url, new
                {
                    externalId  = task.ExternalId,
                    commandType = 0,  // Shell
                    exeName     = task.CommandExe,
                    args        = task.CommandArgs
                });

                response.EnsureSuccessStatusCode();
            }
            catch (Exception ex)
            {
                _logger.LogError(ex,
                    "[LightDispatch] Failed to submit task {TaskId} (externalId={ExtId}) for data_job {JobId} — reverting to Queued",
                    task.Id, task.ExternalId, job.Id);

                await _dataJobRepo.RevertToQueuedAsync(job.Id);
                return;
            }
        }

        _logger.LogInformation(
            "[LightDispatch] data_job {JobId} dispatched to TaskFlow ({Count} tasks submitted)",
            job.Id, tasks.Count);
    }
}
