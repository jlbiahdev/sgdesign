using Microsoft.AspNetCore.Mvc;
using Styx.Models.Responses;

namespace Styx.Controllers;

[ApiController]
[Route("api/[controller]")]
[Produces("application/json")]
public class JobEnvironmentController : ControllerBase
{
    /// <summary>
    /// Returns the complete UNC filesystem tree in a single response.
    /// <c>_root</c> is the server UNC root; <c>_tree</c> is a flat dictionary keyed
    /// by relative path. Nodes under <c>scenario/</c> folders include a scenarios array.
    /// </summary>
    [HttpGet("explore")]
    [ProducesResponseType(typeof(ExploreResponse), StatusCodes.Status200OK)]
    public IActionResult Explore() => throw new NotImplementedException();
}
