using System.Diagnostics;
using System.Text.Json.Serialization;
using Microsoft.AspNetCore.Mvc;

namespace HpcLite.Agent.Controllers;

[ApiController]
public class AgentController : ControllerBase
{
    private readonly ILogger<AgentController> _logger;

    public AgentController(ILogger<AgentController> logger)
    {
        _logger = logger;
    }

    [HttpPost("/run")]
    public IActionResult Run([FromBody] RunRequest request)
    {
        _logger.LogInformation(
            "Spawning runner id={RunnerId} via '{ExePath}'",
            request.RunnerId, request.ExePath);

        var process = new Process
        {
            StartInfo = new ProcessStartInfo
            {
                FileName        = request.ExePath,
                Arguments       = $"--runner-id {request.RunnerId} --path \"{request.SettingsPath}\"",
                UseShellExecute = false,
                CreateNoWindow  = true
            }
        };

        process.Start();
        return Accepted();
    }
}

public class RunRequest
{
    [JsonPropertyName("runner_id")]
    public long   RunnerId     { get; set; }

    [JsonPropertyName("exe_path")]
    public string ExePath      { get; set; } = "";

    [JsonPropertyName("settings_path")]
    public string SettingsPath { get; set; } = "";
}
