using HpcLite.Scheduler.Repositories;
using System.Text;
using System.Text.Json;

namespace HpcLite.Scheduler.Services;

public enum DispatchResult { Dispatched, Queued }

public class RunnerDispatchService
{
    private readonly RunnerRepository    _runnerRepo;
    private readonly ModelJobRepository  _modelJobRepo;
    private readonly IHttpClientFactory  _httpFactory;
    private readonly IConfiguration      _configuration;
    private readonly ILogger<RunnerDispatchService> _logger;

    public RunnerDispatchService(
        RunnerRepository runnerRepo,
        ModelJobRepository modelJobRepo,
        IHttpClientFactory httpFactory,
        IConfiguration configuration,
        ILogger<RunnerDispatchService> logger)
    {
        _runnerRepo    = runnerRepo;
        _modelJobRepo  = modelJobRepo;
        _httpFactory   = httpFactory;
        _configuration = configuration;
        _logger        = logger;
    }

    public async Task<DispatchResult> TryDispatchAsync(long modelJobId, string settingsPath)
    {
        var runner = await _runnerRepo.ClaimIdleRunnerAsync(modelJobId);
        if (runner is null)
        {
            _logger.LogInformation("No runner available — model_job {Id} pending", modelJobId);
            return DispatchResult.Queued;
        }

        var assigned = await _modelJobRepo.TryAssignRunnerAsync(modelJobId, runner.Id);
        if (!assigned)
        {
            // Race: another Scheduler already took this job — release runner
            await _runnerRepo.ReleaseRunnerAsync(runner.Id);
            _logger.LogWarning("model_job {Id} already dispatched by another Scheduler", modelJobId);
            return DispatchResult.Queued;
        }

        var agentPort = _configuration.GetValue<int>("Orchestrator:AgentPort", 5200);
        var agentUrl  = $"http://{runner.Host}:{agentPort}/run";

        var body = JsonSerializer.Serialize(new
        {
            runner_id    = runner.Id,
            exe_path     = runner.ExePath,
            settings_path = settingsPath
        });

        try
        {
            var client   = _httpFactory.CreateClient();
            var response = await client.PostAsync(
                agentUrl,
                new StringContent(body, Encoding.UTF8, "application/json"));

            response.EnsureSuccessStatusCode();
            _logger.LogInformation(
                "Dispatched runner '{Name}' (id={Id}) to Agent {Url} for model_job {JobId}",
                runner.Name, runner.Id, agentUrl, modelJobId);
            return DispatchResult.Dispatched;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Agent call failed for runner '{Name}' at {Url} — rolling back", runner.Name, agentUrl);
            await _runnerRepo.ReleaseRunnerAsync(runner.Id);
            await _modelJobRepo.ClearRunnerAsync(modelJobId);
            throw;
        }
    }
}
