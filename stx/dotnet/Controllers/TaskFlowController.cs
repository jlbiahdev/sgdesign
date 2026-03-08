using Microsoft.AspNetCore.Mvc;

namespace Styx.Controllers;

[ApiController]
[Route("api/[controller]")]
[Produces("application/json")]
public class TaskFlowController : ControllerBase
{
    /// <summary>Notifies a task-state change. Body is job-type-specific.</summary>
    [HttpPost("taskState")]
    [ProducesResponseType(typeof(object), StatusCodes.Status200OK)]
    public IActionResult NotifyTaskState([FromBody] object? payload) => throw new NotImplementedException();
}
