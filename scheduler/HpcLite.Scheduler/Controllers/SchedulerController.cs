using HpcLite.Scheduler.Repositories;
using HpcLite.Scheduler.Services;
using Microsoft.AspNetCore.Mvc;

namespace HpcLite.Scheduler.Controllers;

[ApiController]
public class SchedulerController : ControllerBase
{
    private readonly RunnerRepository      _runnerRepo;
    private readonly RunnerDispatchService _dispatch;
    private readonly IConfiguration        _configuration;
    private readonly ILogger<SchedulerController> _logger;

    public SchedulerController(
        RunnerRepository runnerRepo,
        RunnerDispatchService dispatch,
        IConfiguration configuration,
        ILogger<SchedulerController> logger)
    {
        _runnerRepo    = runnerRepo;
        _dispatch      = dispatch;
        _configuration = configuration;
        _logger        = logger;
    }

    // Manual trigger — useful for tests or for Styx.JobApi if it ever wants to nudge the Scheduler.
    // The Scheduler now finds jobs itself via DB polling; this endpoint is no longer required
    // for normal operation.
    [HttpPost("/schedule")]
    public async Task<IActionResult> Schedule()
    {
        _logger.LogInformation("Manual /schedule trigger received");
        _ = Task.Run(() => _dispatch.TryDispatchAllPendingAsync());
        return Accepted(new { detail = "dispatch cycle triggered" });
    }

    [HttpGet("/runners/ping")]
    public async Task<IActionResult> Ping()
    {
        var timeoutSeconds = _configuration.GetValue<int>("Orchestrator:HeartbeatTimeoutSeconds", 60);
        var runners        = await _runnerRepo.GetAllForPingAsync(timeoutSeconds);
        return Ok(new { runners });
    }
}
