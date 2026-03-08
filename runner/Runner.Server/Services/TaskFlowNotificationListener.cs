using System.Text.Json;
using Microsoft.AspNetCore.SignalR;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Npgsql;
using Runner.Core.Models;
using Runner.Server.Configuration;
using Runner.Server.Hubs;

namespace Runner.Server.Services;

/// <summary>
/// BackgroundService qui maintient une connexion LISTEN sur PostgreSQL.
/// À chaque NOTIFY 'taskflow_events', il rebroadcast via SignalR.
/// </summary>
public class TaskFlowNotificationListener : BackgroundService
{
    private readonly string _connectionString;
    private readonly IHubContext<TaskFlowHub> _hub;
    private readonly ILogger<TaskFlowNotificationListener> _logger;

    public TaskFlowNotificationListener(
        TaskFlowOptions options,
        IHubContext<TaskFlowHub> hub,
        ILogger<TaskFlowNotificationListener> logger)
    {
        _connectionString = options.ConnectionString;
        _hub              = hub;
        _logger           = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await ListenAsync(stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Erreur LISTEN/NOTIFY, reconnexion dans 5s…");
                await Task.Delay(5_000, stoppingToken);
            }
        }
    }

    private async Task ListenAsync(CancellationToken ct)
    {
        await using var conn = new NpgsqlConnection(_connectionString);
        await conn.OpenAsync(ct);

        conn.Notification += OnNotification;

        await using var batch = new NpgsqlBatch(conn)
        {
            BatchCommands =
            {
                new NpgsqlBatchCommand("LISTEN taskflow_events"),
                new NpgsqlBatchCommand("LISTEN taskflow_runner_events"),
            }
        };
        await batch.ExecuteNonQueryAsync(ct);
        _logger.LogInformation("LISTEN taskflow_events + taskflow_runner_events actif.");

        // Boucle keepalive — WaitAsync retourne à chaque notification ou annulation
        while (!ct.IsCancellationRequested)
            await conn.WaitAsync(ct);
    }

    private void OnNotification(object sender, NpgsqlNotificationEventArgs e)
    {
        _logger.LogInformation("NOTIFY reçu sur {Channel}: {Payload}", e.Channel, e.Payload);

        try
        {
            if (e.Channel == "taskflow_runner_events")
            {
                _logger.LogInformation("→ SignalR broadcast RunnerChanged");
                _ = _hub.Clients.All.SendAsync("RunnerChanged");
                return;
            }

            var opts = new JsonSerializerOptions { PropertyNameCaseInsensitive = true };
            var evt = JsonSerializer.Deserialize<TaskEvent>(e.Payload, opts);

            if (evt is null)
            {
                _logger.LogWarning("Payload NOTIFY non désérialisable: {Payload}", e.Payload);
                return;
            }

            _logger.LogInformation("→ SignalR broadcast TaskStateChanged: taskId={TaskId} state={State}", evt.TaskId, evt.State);

            // Broadcast à tous les clients connectés au hub
            _ = _hub.Clients.All.SendAsync("TaskStateChanged", evt);

            // Broadcast au groupe spécifique à cette tâche
            _ = _hub.Clients.Group($"task-{evt.TaskId}").SendAsync("TaskStateChanged", evt);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Erreur de désérialisation du payload NOTIFY.");
        }
    }
}
