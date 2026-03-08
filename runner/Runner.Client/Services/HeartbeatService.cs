using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Runner.Client.Configuration;
using Runner.Core.Interfaces;
using Runner.Core.Models;

namespace Runner.Client.Services;

public class HeartbeatService : BackgroundService
{
    private readonly ITaskRepository _repository;
    private readonly ClientOptions _options;
    private readonly ILogger<HeartbeatService> _logger;

    public HeartbeatService(
        ITaskRepository repository,
        ClientOptions options,
        ILogger<HeartbeatService> logger)
    {
        _repository = repository;
        _options    = options;
        _logger     = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("Heartbeat démarré pour le runner '{Id}'.", _options.ServerId);

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await _repository.UpsertServerAsync(new ServerRecord
                {
                    Id              = _options.ServerId,
                    FriendlyName    = _options.FriendlyName,
                    LastHeartbeatAt = DateTime.UtcNow
                }, stoppingToken);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Échec du heartbeat.");
            }

            await Task.Delay(
                TimeSpan.FromSeconds(_options.HeartbeatIntervalSeconds),
                stoppingToken);
        }
    }
}
