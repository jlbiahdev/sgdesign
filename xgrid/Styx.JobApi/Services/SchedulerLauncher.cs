using System.Diagnostics;
using Styx.JobApi.Repositories;

namespace Styx.JobApi.Services;

public class SchedulerLauncher
{
    private readonly SchedulerRepository _schedulerRepo;
    private readonly string _schedulerExePath;
    private readonly ILogger<SchedulerLauncher> _logger;

    public SchedulerLauncher(SchedulerRepository schedulerRepo, IConfiguration config, ILogger<SchedulerLauncher> logger)
    {
        _schedulerRepo = schedulerRepo;
        _schedulerExePath = config["Orchestrator:SchedulerExePath"]!;
        _logger = logger;
    }

    public async Task SpawnAsync(long modelJobId, string jobPath, long schedulerId)
    {
        var process = new Process
        {
            StartInfo = new ProcessStartInfo
            {
                FileName        = _schedulerExePath,
                Arguments       = $"--path \"{jobPath}\" --model-job-id {modelJobId}",
                UseShellExecute = false,
                CreateNoWindow  = true
            }
        };

        process.Start();
        _logger.LogInformation("Spawned SchedulerProcess PID={Pid} SchedulerId={SchedulerId} ModelJobId={ModelJobId}",
            process.Id, schedulerId, modelJobId);

        await _schedulerRepo.UpdatePidAsync(schedulerId, process.Id);
    }
}
