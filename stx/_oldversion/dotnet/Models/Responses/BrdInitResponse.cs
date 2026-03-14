using Styx.Models.Entities;

namespace Styx.Models.Responses;

public sealed class BrdInitResponse
{
    public string Status { get; init; } = string.Empty;
    public string DefaultName { get; init; } = string.Empty;
    /// <summary>Default projection duration in years.</summary>
    public int DefaultProjectionDuration { get; init; }
    public List<ModelEntry> Models { get; init; } = [];
}
