namespace HpcLite.Scheduler.Services;

public interface IAlertService
{
    Task NotifyAsync(long runnerId, long modelJobId);
}

public class NoOpAlertService : IAlertService
{
    public Task NotifyAsync(long runnerId, long modelJobId) => Task.CompletedTask;
}
