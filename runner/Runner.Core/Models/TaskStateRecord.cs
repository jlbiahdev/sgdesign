namespace Runner.Core.Models;

public class TaskStateRecord
{
    public long Id { get; set; }
    public long TaskId { get; set; }
    public string Name { get; set; } = string.Empty;
    public string? Reason { get; set; }
    public string? ServerId { get; set; }
    public DateTime CreatedAt { get; set; }
}
