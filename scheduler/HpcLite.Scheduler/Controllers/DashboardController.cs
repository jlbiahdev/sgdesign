using HpcLite.Scheduler.Repositories;
using Microsoft.AspNetCore.Mvc;

namespace HpcLite.Scheduler.Controllers;

[ApiController]
public class DashboardController : ControllerBase
{
    private readonly SchedulerRepository _schedulerRepo;
    private readonly RunnerRepository    _runnerRepo;
    private readonly ModelJobRepository  _modelJobRepo;
    private readonly IConfiguration      _configuration;

    public DashboardController(
        SchedulerRepository schedulerRepo,
        RunnerRepository    runnerRepo,
        ModelJobRepository  modelJobRepo,
        IConfiguration      configuration)
    {
        _schedulerRepo = schedulerRepo;
        _runnerRepo    = runnerRepo;
        _modelJobRepo  = modelJobRepo;
        _configuration = configuration;
    }

    [HttpGet("/dashboard/status")]
    public async Task<IActionResult> Status()
    {
        var heartbeatTimeout = _configuration.GetValue<int>("Orchestrator:HeartbeatTimeoutSeconds", 60);

        var schedulers    = await _schedulerRepo.GetAllAsync();
        var runners       = await _runnerRepo.GetAllForPingAsync(heartbeatTimeout);
        var queuedJobIds  = await _modelJobRepo.GetPendingModelJobIdsAsync();

        return Ok(new
        {
            schedulers,
            runners,
            queued_model_job_ids = queuedJobIds
        });
    }
}
