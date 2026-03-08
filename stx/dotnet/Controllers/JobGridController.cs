using Microsoft.AspNetCore.Mvc;
using Styx.Models.Requests;
using Styx.Models.Responses;

namespace Styx.Controllers;

[ApiController]
[Route("api/[controller]")]
[Produces("application/json")]
public class JobGridController : ControllerBase
{
    /// <summary>Returns all jobs for the monitoring grid.</summary>
    [HttpGet("jobs")]
    [ProducesResponseType(typeof(JobListResponse), StatusCodes.Status200OK)]
    public IActionResult GetJobs() => throw new NotImplementedException();

    /// <summary>Returns the child job groups (execution phases) for a parent job.</summary>
    [HttpGet("jobs/children")]
    [ProducesResponseType(typeof(JobChildrenResponse), StatusCodes.Status200OK)]
    public IActionResult GetJobChildren([FromQuery] int jobId) => throw new NotImplementedException();

    /// <summary>Returns the task-level log for a leaf job.</summary>
    [HttpGet("jobs/{jobId}/tasks")]
    [ProducesResponseType(typeof(JobTasksResponse), StatusCodes.Status200OK)]
    public IActionResult GetJobTasks(int jobId) => throw new NotImplementedException();

    /// <summary>Cancels a running or queued job.</summary>
    [HttpPost("cancel")]
    [ProducesResponseType(typeof(StatusMessageResponse), StatusCodes.Status200OK)]
    public IActionResult CancelJob([FromBody] JobActionRequest request) => throw new NotImplementedException();

    /// <summary>Requeues a failed or cancelled job.</summary>
    [HttpPost("requeue")]
    [ProducesResponseType(typeof(StatusMessageResponse), StatusCodes.Status200OK)]
    public IActionResult RequeueJob([FromBody] JobActionRequest request) => throw new NotImplementedException();
}
