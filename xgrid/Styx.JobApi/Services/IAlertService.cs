namespace Styx.JobApi.Services;

public interface IAlertService
{
    Task NotifyAsync(long schedulerId, long modelJobId);
}

public class NoOpAlertService : IAlertService
{
    public Task NotifyAsync(long schedulerId, long modelJobId) => Task.CompletedTask;
}
