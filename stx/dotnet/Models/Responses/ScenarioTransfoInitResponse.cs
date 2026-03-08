using Styx.Models.Entities;

namespace Styx.Models.Responses;

public sealed class ScenarioTransfoInitResponse
{
    public List<LabelValueEntry> ModelTypes { get; init; } = [];
    public string DefaultModelType { get; init; } = string.Empty;

    public List<LabelValueEntry> Periodes { get; init; } = [];
    public string DefaultPeriode { get; init; } = string.Empty;

    public List<int> Iterations { get; init; } = [];
    public int DefaultIterations { get; init; }

    public List<string> Coupons { get; init; } = [];
    public string DefaultCoupon { get; init; } = string.Empty;
}
