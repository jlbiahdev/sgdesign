using Microsoft.AspNetCore.Mvc;
using Styx.Models.Responses;

namespace Styx.Controllers;

[ApiController]
[Route("api/[controller]")]
[Produces("application/json")]
public class TaskFlowController : ControllerBase
{
    /// <summary>Notifies a task-state change. Body is job-type-specific.</summary>
    [HttpPost("taskState")]
    [ProducesResponseType(typeof(StatusMessageResponse), StatusCodes.Status200OK)]
    public IActionResult NotifyTaskState([FromBody] object? payload)
        => Ok(new StatusMessageResponse { Status = "ok", Message = "Task state notification received." });
}
