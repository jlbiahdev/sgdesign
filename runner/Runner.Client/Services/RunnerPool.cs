using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Runner.Client.Configuration;
using Runner.Core.Enums;
using Runner.Core.Interfaces;
using Runner.Core.Models;

namespace Runner.Client.Services;

/// <summary>
/// Gère un pool de N workers qui s'exécutent en parallèle.
/// Chaque worker poll la DB et prend une tâche dès qu'elle est disponible.
/// </summary>
public class RunnerPool : BackgroundService
{
    private readonly ITaskRepository _repository;
    private readonly ShellExecutor _shellExecutor;
    private readonly DotNetExecutor _dotNetExecutor;
    private readonly ClientOptions _options;
    private readonly ILogger<RunnerPool> _logger;

    public RunnerPool(
        ITaskRepository repository,
        ShellExecutor shellExecutor,
        DotNetExecutor dotNetExecutor,
        ClientOptions options,
        ILogger<RunnerPool> logger)
    {
        _repository     = repository;
        _shellExecutor  = shellExecutor;
        _dotNetExecutor = dotNetExecutor;
        _options        = options;
        _logger         = logger;
    }

    protected override Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation(
            "Runner pool démarré — {Count} worker(s) parallèle(s).",
            _options.MaxConcurrentRunners);

        var workers = Enumerable
            .Range(0, _options.MaxConcurrentRunners)
            .Select(i => RunWorkerAsync(i, stoppingToken));

        return Task.WhenAll(workers);
    }

    private async Task RunWorkerAsync(int workerId, CancellationToken ct)
    {
        while (!ct.IsCancellationRequested)
        {
            TaskRecord? task = null;

            try
            {
                task = await _repository.TryAcquireNextAsync(_options.ServerId, ct);

                if (task is null)
                {
                    await Task.Delay(_options.PollingIntervalMs, ct);
                    continue;
                }

                _logger.LogInformation(
                    "[Worker {Id}] Tâche {TaskId} acquise ({Type} → {Exe}).",
                    workerId, task.Id, task.CommandType, task.ExeName);

                await ExecuteTaskAsync(task, ct);

                await _repository.UpdateStateAsync(
                    task.Id, WorkStatus.Finished, _options.ServerId, null, ct);

                _logger.LogInformation("[Worker {Id}] Tâche {TaskId} terminée.", workerId, task.Id);
            }
            catch (OperationCanceledException) when (ct.IsCancellationRequested)
            {
                if (task is not null)
                    await TryMarkCanceledAsync(task.Id);
                break;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "[Worker {Id}] Tâche {TaskId} en échec.", workerId, task?.Id);

                if (task is not null)
                    await TryMarkFailedAsync(task.Id, ex.Message);
            }
        }
    }

    private async Task ExecuteTaskAsync(TaskRecord task, CancellationToken ct)
    {
        using var cts = _options.TaskTimeoutSeconds > 0
            ? CancellationTokenSource.CreateLinkedTokenSource(ct)
            : null;

        if (cts is not null)
            cts.CancelAfter(TimeSpan.FromSeconds(_options.TaskTimeoutSeconds));

        var token = cts?.Token ?? ct;

        if (task.CommandType == CommandType.Shell.ToString())
            await _shellExecutor.RunAsync(task.ExeName, task.Args, token);
        else
            await _dotNetExecutor.RunAsync(task.ExeName, task.Args, token);
    }

    private async Task TryMarkFailedAsync(long taskId, string reason)
    {
        try
        {
            await _repository.UpdateStateAsync(
                taskId, WorkStatus.Failed, _options.ServerId, reason);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Impossible de marquer la tâche {Id} comme Failed.", taskId);
        }
    }

    private async Task TryMarkCanceledAsync(long taskId)
    {
        try
        {
            await _repository.UpdateStateAsync(
                taskId, WorkStatus.Canceled, _options.ServerId, "Runner arrêté");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Impossible de marquer la tâche {Id} comme Canceled.", taskId);
        }
    }
}
