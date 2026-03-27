using Styx.Domain.Models;
using Styx.SchedulerProcess.Models;

namespace Styx.SchedulerProcess.Services;

public class DependencyEngine
{
    private readonly SubJobExecutor _executor;
    private readonly DataJobRepository _dataJobRepo;
    private readonly int _maxParallelSubJobs;

    public DependencyEngine(SubJobExecutor executor, DataJobRepository dataJobRepo, int maxParallelSubJobs)
    {
        _executor = executor;
        _dataJobRepo = dataJobRepo;
        _maxParallelSubJobs = maxParallelSubJobs;
    }

    public async Task RunAsync(JobsFile jobsFile, long schedulerId, long modelJobId, CancellationToken ct = default)
    {
        var nodes = jobsFile.DataJobs
            .Select(e => new DataJobNode { Id = e.Id, ParentIds = e.ParentIds })
            .ToList();
        var nodeMap = nodes.ToDictionary(n => n.Id);

        if (HasCycle(nodes))
        {
            Console.Error.WriteLine($"[DependencyEngine] Cycle detected in DataJob dependencies for ModelJob {modelJobId}. Failing all jobs.");
            await _dataJobRepo.FailAllAsync(modelJobId);
            return;
        }

        var semaphore = new SemaphoreSlim(_maxParallelSubJobs, _maxParallelSubJobs);
        var activeTasks = new Dictionary<long, Task>();

        while (!ct.IsCancellationRequested)
        {
            if (nodes.All(n => n.State is RunStates.Finished or RunStates.Failed or RunStates.Canceled))
                break;

            // Launch all ready nodes up to semaphore limit
            var ready = nodes.Where(n =>
                n.State == RunStates.Queued &&
                !activeTasks.ContainsKey(n.Id) &&
                n.ParentIds.All(pid => nodeMap.TryGetValue(pid, out var p) && p.State == RunStates.Finished)
            ).ToList();

            foreach (var node in ready)
            {
                if (!await semaphore.WaitAsync(0, ct))
                    break; // No slots — process completions first

                node.State = RunStates.Running;
                await _dataJobRepo.SetRunningAsync(node.Id);
                activeTasks[node.Id] = RunNodeAsync(node, nodeMap, semaphore, ct);
            }

            if (activeTasks.Count == 0)
            {
                var hasQueued = nodes.Any(n => n.State == RunStates.Queued);
                if (hasQueued)
                    Console.WriteLine($"[DependencyEngine] WARNING: no ready nodes but queued exist for ModelJob {modelJobId}. Possible deadlock.");

                await Task.Delay(1000, ct);
                continue;
            }

            await Task.WhenAny(activeTasks.Values);

            // Remove completed tasks
            foreach (var id in activeTasks.Keys.ToList())
                if (activeTasks[id].IsCompleted)
                    activeTasks.Remove(id);
        }
    }

    private async Task RunNodeAsync(
        DataJobNode node,
        Dictionary<long, DataJobNode> nodeMap,
        SemaphoreSlim semaphore,
        CancellationToken ct)
    {
        try
        {
            var (success, errorDetail) = await _executor.ExecuteAsync(node, ct);
            if (success)
            {
                node.State = RunStates.Finished;
                await _dataJobRepo.SetFinishedAsync(node.Id);
            }
            else
            {
                node.State = RunStates.Failed;
                await _dataJobRepo.SetFailedAsync(node.Id, errorDetail);
                PropagateFailure(node, nodeMap);
            }
        }
        catch (Exception ex)
        {
            node.State = RunStates.Failed;
            await _dataJobRepo.SetFailedAsync(node.Id, ex.Message);
            PropagateFailure(node, nodeMap);
        }
        finally
        {
            semaphore.Release();
        }
    }

    private static void PropagateFailure(DataJobNode failed, Dictionary<long, DataJobNode> nodeMap)
    {
        var stack = new Stack<long>();
        foreach (var n in nodeMap.Values.Where(n => n.ParentIds.Contains(failed.Id)))
            stack.Push(n.Id);

        while (stack.Count > 0)
        {
            var id = stack.Pop();
            if (!nodeMap.TryGetValue(id, out var node)) continue;
            if (node.State is RunStates.Finished or RunStates.Failed or RunStates.Canceled) continue;

            node.State = RunStates.Failed;
            foreach (var child in nodeMap.Values.Where(n => n.ParentIds.Contains(id)))
                stack.Push(child.Id);
        }
    }

    private static bool HasCycle(List<DataJobNode> nodes)
    {
        var nodeIds = nodes.Select(n => n.Id).ToHashSet();
        var inDegree = nodes.ToDictionary(n => n.Id, _ => 0);
        var children = nodes.ToDictionary(n => n.Id, _ => new List<long>());

        foreach (var node in nodes)
        {
            foreach (var parentId in node.ParentIds)
            {
                if (!nodeIds.Contains(parentId)) continue;
                inDegree[node.Id]++;
                children[parentId].Add(node.Id);
            }
        }

        var queue = new Queue<long>(inDegree.Where(kv => kv.Value == 0).Select(kv => kv.Key));
        int processed = 0;

        while (queue.Count > 0)
        {
            var id = queue.Dequeue();
            processed++;
            foreach (var childId in children[id])
            {
                inDegree[childId]--;
                if (inDegree[childId] == 0)
                    queue.Enqueue(childId);
            }
        }

        return processed != nodes.Count;
    }
}
