using HpcLite.Runner.Models;
using HpcLite.Runner.Repositories;

namespace HpcLite.Runner.Services;

public class RunnerRegistrationService
{
    private readonly RunnerRepository    _runnerRepo;
    private readonly ModelJobRepository  _modelJobRepo;

    public RunnerRegistrationService(RunnerRepository runnerRepo, ModelJobRepository modelJobRepo)
    {
        _runnerRepo   = runnerRepo;
        _modelJobRepo = modelJobRepo;
    }

    public async Task<RunnerContext> RegisterAsync(long runnerId, long modelJobId, string settingsPath)
    {
        await _runnerRepo.ActivateAsync(runnerId, modelJobId);
        return new RunnerContext
        {
            RunnerId    = runnerId,
            ModelJobId  = modelJobId,
            SettingsPath = settingsPath
        };
    }

    public async Task UnregisterAsync(long runnerId, long modelJobId)
    {
        await _runnerRepo.DeactivateAsync(runnerId);
        await _modelJobRepo.ClearRunnerAsync(modelJobId);
    }
}
