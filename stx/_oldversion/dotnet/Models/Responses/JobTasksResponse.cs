using Styx.Models.Enums;

namespace Styx.Models.Responses;

public sealed class JobTasksResponse
{
    public string Status { get; init; } = string.Empty;
    public string? Message { get; init; }
    public string? Warnings { get; init; }
    public int JobId { get; init; }
    public List<JobTask> Tasks { get; init; } = [];
}

public sealed class JobTask
{
    public int Id { get; init; }
    public JobState State { get; init; }
    public string Command { get; init; } = string.Empty;
    public string? Output { get; init; }
    public DateTime? StartTime { get; init; }
    public DateTime? EndTime { get; init; }
}
