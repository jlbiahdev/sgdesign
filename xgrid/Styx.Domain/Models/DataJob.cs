namespace Styx.Domain.Models;

public class DataJob
{
    public long Id { get; set; }
    public long ParentModelId { get; set; }
    public string Name { get; set; } = string.Empty;
    public string State { get; set; } = RunStates.Created;
    public int Progress { get; set; }
    public int RetryLimit { get; set; }
    public DateTime? StartDateTime { get; set; }
    public DateTime ChangeDateTime { get; set; }
}
