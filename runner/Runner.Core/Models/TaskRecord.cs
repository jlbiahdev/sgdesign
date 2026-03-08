namespace Runner.Core.Models;

public class TaskRecord
{
    public long Id { get; set; }
    public long ExternalId { get; set; }
    public string State { get; set; } = "Submitted";
    public string CommandType { get; set; } = "Shell";
    public string ExeName { get; set; } = string.Empty;
    public string? Args { get; set; }
    public DateTime CreatedAt { get; set; }
}
