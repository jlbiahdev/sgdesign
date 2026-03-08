using Styx.Models.Entities;
using Styx.Models.Enums;

namespace Styx.Models.Responses;

/// <summary>Shared init response for RiskLife and RiskLifeKP.</summary>
public sealed class RiskLifeInitResponse
{
    public string Status { get; init; } = string.Empty;
    public string DefaultName { get; init; } = string.Empty;

    /// <summary>Default iteration range, e.g. "1-1".</summary>
    public string DefaultIterations { get; init; } = string.Empty;
    public bool DefaultAutoIterations { get; init; }

    /// <summary>Default projection period in months.</summary>
    public int DefaultPeriod { get; init; }

    public List<ModelEntry> Models { get; init; } = [];
    public List<OmenType> JobOmenTypes { get; init; } = [];
    public OmenType DefaultJobType { get; init; }
    public List<RLScenarioEntry> Scenarios { get; init; } = [];
}
