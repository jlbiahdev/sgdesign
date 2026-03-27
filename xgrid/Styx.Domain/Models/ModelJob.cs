namespace Styx.Domain.Models;

public class ModelJob
{
    public long Id { get; set; }
    public string Name { get; set; } = string.Empty;
    public bool IsPurged { get; set; }
    public long? SchedulerId { get; set; }
    public string? JobPath { get; set; }
}
