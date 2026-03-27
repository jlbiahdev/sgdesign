using Dapper;
using Npgsql;

namespace Styx.SchedulerProcess.Services;

public class HeartbeatService
{
    private readonly string _connectionString;
    private readonly int _intervalSeconds;

    public HeartbeatService(string connectionString, int intervalSeconds)
    {
        _connectionString = connectionString;
        _intervalSeconds = intervalSeconds;
    }

    public async Task RunAsync(long schedulerId, CancellationToken cancellationToken)
    {
        while (!cancellationToken.IsCancellationRequested)
        {
            try
            {
                await UpdateHeartbeatAsync(schedulerId);
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine($"[Heartbeat] Failed to update heartbeat: {ex.Message}");
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

    private async Task UpdateHeartbeatAsync(long schedulerId)
    {
        await using var conn = new NpgsqlConnection(_connectionString);
        await conn.ExecuteAsync(
            "UPDATE schedulers SET heartbeat = NOW() WHERE id = @schedulerId",
            new { schedulerId });
    }
}
