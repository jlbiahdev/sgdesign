namespace Styx.Models.Responses;

public sealed class StatusMessageResponse
{
    public string Status { get; init; } = string.Empty;
    public string? Message { get; init; }
}
