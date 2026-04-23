using HpcLite.Scheduler.Repositories;
using HpcLite.Scheduler.Services;
using Microsoft.AspNetCore.Mvc;

namespace HpcLite.Scheduler.Controllers;

[ApiController]
public class SchedulerController : ControllerBase
{
    private readonly ModelJobRepository  _modelJobRepo;
    private readonly RunnerRepository    _runnerRepo;
    private readonly RunnerDispatchService _dispatch;
    private readonly IConfiguration      _configuration;
    private readonly ILogger<SchedulerController> _logger;

    public SchedulerController(
        ModelJobRepository modelJobRepo,
        RunnerRepository runnerRepo,
        RunnerDispatchService dispatch,
        IConfiguration configuration,
        ILogger<SchedulerController> logger)
    {
        _modelJobRepo  = modelJobRepo;
        _runnerRepo    = runnerRepo;
        _dispatch      = dispatch;
        _configuration = configuration;
        _logger        = logger;
    }

    [HttpPost("/schedule")]
    public async Task<IActionResult> Schedule([FromBody] ScheduleRequest request)
    {
        var modelJob = await _modelJobRepo.GetByIdAsync(request.ModelJobId);
        if (modelJob is null)
            return NotFound($"model_job {request.ModelJobId} not found");
        if (modelJob.RunnerId.HasValue)
            return Conflict(new { model_job_id = request.ModelJobId, detail = "Already running" });

        DispatchResult result;
        try
        {
            result = await _dispatch.TryDispatchAsync(request.ModelJobId, request.SettingsPath);
        }
        catch
        {
            return StatusCode(502, new { detail = "Agent unreachable" });
        }

        return Accepted(new
        {
            model_job_id = request.ModelJobId,
            status       = result == DispatchResult.Dispatched ? "dispatched" : "queued"
        });
    }

    [HttpGet("/runners/ping")]
    public async Task<IActionResult> Ping()
    {
        var timeoutSeconds = _configuration.GetValue<int>("Orchestrator:HeartbeatTimeoutSeconds", 60);
        var runners        = await _runnerRepo.GetAllForPingAsync(timeoutSeconds);
        return Ok(new { runners });
    }
}

public class ScheduleRequest
{
    public long   ModelJobId   { get; set; }
    public string SettingsPath { get; set; } = "";
}
