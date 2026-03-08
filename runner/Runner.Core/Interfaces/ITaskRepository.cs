using Runner.Core.Enums;
using Runner.Core.Models;

namespace Runner.Core.Interfaces;

public interface ITaskRepository
{
    Task<long> InsertAsync(TaskRecord task, CancellationToken ct = default);
    Task<TaskRecord?> GetByIdAsync(long id, CancellationToken ct = default);
    Task<IEnumerable<TaskRecord>> GetAllAsync(CancellationToken ct = default);

    /// <summary>
    /// Prend atomiquement la prochaine tâche Submitted (SELECT FOR UPDATE SKIP LOCKED).
    /// Met à jour son état à Running et insère dans task_state.
    /// </summary>
    Task<TaskRecord?> TryAcquireNextAsync(string serverId, CancellationToken ct = default);

    Task UpdateStateAsync(long id, WorkStatus status, string serverId, string? reason = null, CancellationToken ct = default);
    Task<IEnumerable<TaskStateRecord>> GetHistoryAsync(long id, CancellationToken ct = default);
    Task<IEnumerable<ServerRecord>> GetServersAsync(CancellationToken ct = default);
    Task UpsertServerAsync(ServerRecord server, CancellationToken ct = default);
}
