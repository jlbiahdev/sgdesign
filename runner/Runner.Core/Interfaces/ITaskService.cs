using Runner.Core.Models;

namespace Runner.Core.Interfaces;

public interface ITaskService
{
    Task<long> SubmitAsync(TaskSubmitRequest request, CancellationToken ct = default);
    Task<TaskRecord?> GetAsync(long id, CancellationToken ct = default);
    Task<IEnumerable<TaskRecord>> GetAllAsync(CancellationToken ct = default);
    Task<bool> CancelAsync(long id, CancellationToken ct = default);
    Task<IEnumerable<TaskStateRecord>> GetHistoryAsync(long id, CancellationToken ct = default);
    Task<IEnumerable<ServerRecord>> GetRunnersAsync(CancellationToken ct = default);
}
