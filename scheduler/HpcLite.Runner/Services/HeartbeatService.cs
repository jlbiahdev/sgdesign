using HpcLite.Runner.Repositories;
using NLog;

namespace HpcLite.Runner.Services;

public class HeartbeatService
{
    private static readonly Logger Log = LogManager.GetCurrentClassLogger();

    private readonly RunnerRepository _runnerRepo;
    private readonly int _intervalSeconds;

    public HeartbeatService(RunnerRepository runnerRepo, int intervalSeconds)
    {
        _runnerRepo      = runnerRepo;
        _intervalSeconds = intervalSeconds;
    }

    public async Task RunAsync(long runnerId, CancellationToken cancellationToken)
    {
        while (!cancellationToken.IsCancellationRequested)
        {
            try
            {
                await _runnerRepo.UpdateHeartbeatAsync(runnerId);
                Log.Debug("Heartbeat envoyé pour runner id={RunnerId}", runnerId);
            }
            catch (Exception ex)
            {
                Log.Warn(ex, "Échec heartbeat pour runner id={RunnerId}", runnerId);
            }

            try
            {
                await Task.Delay(TimeSpan.FromSeconds(_intervalSeconds), cancellationToken);
            }
            catch (OperationCanceledException)
            {
                break;
            }
        }
    }
}
