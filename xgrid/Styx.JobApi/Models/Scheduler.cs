namespace Styx.JobApi.Models;

public class Scheduler
{
    public long Id { get; set; }
    public int Pid { get; set; }
    public string Host { get; set; } = string.Empty;
    public long? ModelJobId { get; set; }
    public string JobPath { get; set; } = string.Empty;
    public string Status { get; set; } = "active";
    public DateTime StartedAt { get; set; }
    public DateTime Heartbeat { get; set; }
}
