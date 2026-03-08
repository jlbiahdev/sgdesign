namespace Runner.Core.Models;

/// <summary>Payload du NOTIFY PostgreSQL et de l'événement SignalR.</summary>
public class TaskEvent
{
    public long TaskId { get; set; }
    public string State { get; set; } = string.Empty;
    public string? ServerId { get; set; }
    public string? Reason { get; set; }
    public DateTime At { get; set; } = DateTime.UtcNow;
}
