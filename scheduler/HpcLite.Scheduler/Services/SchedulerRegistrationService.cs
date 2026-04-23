using System.Net;
using HpcLite.Scheduler.Repositories;

namespace HpcLite.Scheduler.Services;

public class SchedulerRegistrationService : BackgroundService
{
    private readonly SchedulerRepository _repo;
    private readonly IConfiguration _configuration;
    private readonly ILogger<SchedulerRegistrationService> _logger;
    private readonly string _host;

    public SchedulerRegistrationService(
        SchedulerRepository repo,
        IConfiguration configuration,
        ILogger<SchedulerRegistrationService> logger)
    {
        _repo          = repo;
        _configuration = configuration;
        _logger        = logger;
        _host          = Dns.GetHostName();
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var rows = await _repo.ActivateAsync(_host);
        if (rows == 0)
        {
            _logger.LogError(
                "Ce Scheduler n'est pas enregistré en DB (host='{Host}'). Contacter l'admin.",
                _host);
        }
        else
        {
            _logger.LogInformation("Scheduler '{Host}' activé en DB.", _host);
        }

        var intervalSeconds = _configuration.GetValue<int>("Orchestrator:HeartbeatIntervalSeconds", 10);

        while (!stoppingToken.IsCancellationRequested)
        {
            await Task.Delay(TimeSpan.FromSeconds(intervalSeconds), stoppingToken);
            try
            {
                await _repo.UpdateHeartbeatAsync(_host);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Échec du heartbeat Scheduler.");
            }
        }
    }

    public override async Task StopAsync(CancellationToken cancellationToken)
    {
        await _repo.DeactivateAsync(_host);
        _logger.LogInformation("Scheduler '{Host}' marqué inactive.", _host);
        await base.StopAsync(cancellationToken);
    }
}
