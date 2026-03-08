namespace Runner.Core.Models;

public class ServerRecord
{
    public string Id { get; set; } = string.Empty;
    public string? FriendlyName { get; set; }
    public DateTime LastHeartbeatAt { get; set; }
}
