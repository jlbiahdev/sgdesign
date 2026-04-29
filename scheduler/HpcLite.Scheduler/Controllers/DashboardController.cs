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

    [HttpPost("/schedulers")]
    public async Task<IActionResult> AddScheduler([FromBody] AddSchedulerRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.Name) ||
            string.IsNullOrWhiteSpace(request.Host))
            return BadRequest(new { error = "name et host sont obligatoires." });

        await _schedulerRepo.UpsertSchedulerAsync(
            request.Name.Trim(),
            request.Host.Trim());

        return Ok(new { name = request.Name.Trim(), host = request.Host.Trim() });
    }

    [HttpPost("/runners")]
    public async Task<IActionResult> AddRunner([FromBody] AddRunnerRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.Name)    ||
            string.IsNullOrWhiteSpace(request.Host)    ||
            string.IsNullOrWhiteSpace(request.ExePath))
            return BadRequest(new { error = "name, host et exe_path sont obligatoires." });

        await _runnerRepo.UpsertRunnerAsync(
            request.Name.Trim(),
            request.Host.Trim(),
            request.ExePath.Trim());

        return Ok(new { name = request.Name.Trim(), host = request.Host.Trim() });
    }
}

public class AddSchedulerRequest
{
    public string Name { get; set; } = "";
    public string Host { get; set; } = "";
}

public class AddRunnerRequest
{
    public string Name    { get; set; } = "";
    public string Host    { get; set; } = "";
    public string ExePath { get; set; } = "";
}
