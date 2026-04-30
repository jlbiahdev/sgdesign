using Npgsql;

namespace HpcLite.Scheduler.Services;

/// Maintains a persistent PostgreSQL LISTEN connection on channel 'hpclite_job_ready'.
/// The channel is fed by a DB trigger that fires whenever a data_job transitions to 'Queued'.
/// A poll fallback runs every PollIntervalSeconds in case a notification is missed
/// (connection drop, trigger missed, etc.).
public class JobListenerService : BackgroundService
{
    private const string Channel = "hpclite_job_ready";

    private readonly string _connectionString;
    private readonly RunnerDispatchService _dispatcher;
    private readonly LightJobDispatchService _lightDispatcher;
    private readonly int _pollIntervalSeconds;
    private readonly ILogger<JobListenerService> _logger;

    public JobListenerService(
        IConfiguration configuration,
        RunnerDispatchService dispatcher,
        LightJobDispatchService lightDispatcher,
        ILogger<JobListenerService> logger)
    {
        _connectionString    = configuration.GetConnectionString("Postgres")!;
        _pollIntervalSeconds = configuration.GetValue<int>("Orchestrator:PollIntervalSeconds", 10);
        _dispatcher          = dispatcher;
        _lightDispatcher     = lightDispatcher;
        _logger              = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        // Initial dispatch on startup: pick up any jobs submitted while the Scheduler was down
        await _dispatcher.TryDispatchAllPendingAsync();
        await _lightDispatcher.TryDispatchAllPendingAsync();

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await ListenLoopAsync(stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break;
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "[JobListener] LISTEN connection lost — reconnecting in 5s");
                await Task.Delay(TimeSpan.FromSeconds(5), stoppingToken);
            }
        }
    }

    private async Task ListenLoopAsync(CancellationToken ct)
    {
        await using var conn = new NpgsqlConnection(_connectionString);
        await conn.OpenAsync(ct);

        conn.Notification += (_, args) =>
            _logger.LogDebug("[JobListener] NOTIFY received: model_job_id={Id}", args.Payload);

        await using (var cmd = conn.CreateCommand())
        {
            cmd.CommandText = $"LISTEN {Channel}";
            await cmd.ExecuteNonQueryAsync(ct);
        }

        _logger.LogInformation("[JobListener] Listening on '{Channel}' (poll fallback every {N}s)",
            Channel, _pollIntervalSeconds);

        while (!ct.IsCancellationRequested)
        {
            // Blocks until a notification arrives OR the timeout elapses.
            // Either way we attempt a dispatch — the SKIP LOCKED query is a no-op if nothing is pending.
            await conn.WaitAsync(TimeSpan.FromSeconds(_pollIntervalSeconds), ct);
            await _dispatcher.TryDispatchAllPendingAsync();
            await _lightDispatcher.TryDispatchAllPendingAsync();
        }
    }
}
