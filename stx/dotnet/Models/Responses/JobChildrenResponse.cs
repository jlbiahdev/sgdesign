using Styx.Models.Enums;

namespace Styx.Models.Responses;

public sealed class JobChildrenResponse
{
    public string Status { get; init; } = string.Empty;
    public string? Message { get; init; }
    public string? Warnings { get; init; }
    public int JobId { get; init; }
    public List<JobGroup> JobGroups { get; init; } = [];
}

public sealed class JobGroup
{
    public int Id { get; init; }
    public ChildJobState Status { get; init; }
    public string Name { get; init; } = string.Empty;
    public int Progress { get; init; }
    public DateTime? Updated { get; init; }
    public int ParentId { get; init; }
    public int LaunchedJobCount { get; init; }
    public List<ChildJob> Children { get; init; } = [];
}

public sealed class ChildJob
{
    public int Id { get; init; }
    public ChildJobState State { get; init; }
    public string Name { get; init; } = string.Empty;
    public int Progress { get; init; }
    public JobPriority Priority { get; init; }
    public DateTime? Created { get; init; }
    public DateTime? Submitted { get; init; }
    public DateTime? Updated { get; init; }
    public string? Environment { get; init; }
}
