namespace Styx.Models.Responses;

public sealed class SubmitResponse
{
    public int ParentId { get; init; }
    public int LaunchedJobCount { get; init; }
    public ApiResults ApiResults { get; init; } = new();
}

public sealed class ApiResults
{
    public List<LightGridResult> LightGridSubmissionResult { get; init; } = [];
    public ExternalApiResult ExternalApiSubmissionResult { get; init; } = new();
}

public sealed class LightGridResult
{
    public int JobId { get; init; }
    public List<TaskIdEntry> TasksIds { get; init; } = [];
}

public sealed class TaskIdEntry
{
    public int Id { get; init; }
    public int GridId { get; init; }
}

public sealed class ExternalApiResult
{
    public List<ExternalIdEntry> Ids { get; init; } = [];
    public string Status { get; init; } = string.Empty;
    public string? Message { get; init; }
}

public sealed class ExternalIdEntry
{
    public int Id { get; init; }
    public int BpcId { get; init; }
    public int XGridId { get; init; }
}
