using Runner.Core.Enums;
using Runner.Core.Interfaces;
using Runner.Core.Models;

namespace Runner.Server.Services;

public class TaskService : ITaskService
{
    private readonly ITaskRepository _repository;

    public TaskService(ITaskRepository repository)
    {
        _repository = repository;
    }

    public async Task<long> SubmitAsync(TaskSubmitRequest request, CancellationToken ct = default)
    {
        var task = new TaskRecord
        {
            ExternalId  = request.ExternalId,
            State       = WorkStatus.Submitted.ToString(),
            CommandType = request.CommandType.ToString(),
            ExeName     = request.ExeName,
            Args        = request.Args,
            CreatedAt   = DateTime.UtcNow
        };

        return await _repository.InsertAsync(task, ct);
    }

    public Task<TaskRecord?> GetAsync(long id, CancellationToken ct = default)
        => _repository.GetByIdAsync(id, ct);

    public Task<IEnumerable<TaskRecord>> GetAllAsync(CancellationToken ct = default)
        => _repository.GetAllAsync(ct);

    public async Task<bool> CancelAsync(long id, CancellationToken ct = default)
    {
        var task = await _repository.GetByIdAsync(id, ct);
        if (task is null) return false;

        var cancellable = new[] { WorkStatus.Submitted.ToString(), WorkStatus.Running.ToString() };
        if (!cancellable.Contains(task.State)) return false;

        await _repository.UpdateStateAsync(id, WorkStatus.Canceled, "server", "Canceled via API", ct);
        return true;
    }

    public Task<IEnumerable<TaskStateRecord>> GetHistoryAsync(long id, CancellationToken ct = default)
        => _repository.GetHistoryAsync(id, ct);

    public Task<IEnumerable<ServerRecord>> GetRunnersAsync(CancellationToken ct = default)
        => _repository.GetServersAsync(ct);
}
