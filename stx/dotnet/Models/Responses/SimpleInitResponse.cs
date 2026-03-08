using Styx.Models.Entities;

namespace Styx.Models.Responses;

/// <summary>
/// Shared init response for NonLife and TdR.
/// </summary>
public sealed class SimpleInitResponse
{
    public string Status { get; init; } = string.Empty;
    public string DefaultName { get; init; } = string.Empty;
    /// <summary>Default simulation period in months.</summary>
    public int DefaultPeriod { get; init; }
    public List<ModelEntry> Models { get; init; } = [];
}
