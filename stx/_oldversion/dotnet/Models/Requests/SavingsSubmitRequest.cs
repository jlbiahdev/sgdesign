using Styx.Models.Enums;

namespace Styx.Models.Requests;

public sealed class SavingsSubmitRequest : OmenSubmitBase
{
    public bool DetEnabled { get; init; }
    /// <summary>Iteration range, e.g. "1-2000".</summary>
    public string DetRange { get; init; } = string.Empty;
    /// <summary>Period label, e.g. "1y".</summary>
    public string DetPeriod { get; init; } = string.Empty;
    public int DetMonths { get; init; }

    public bool StoEnabled { get; init; }
    public string StoRange { get; init; } = string.Empty;
    public string StoPeriod { get; init; } = string.Empty;
    public int StoMonths { get; init; }

    public bool PricerEnabled { get; init; }
    public string PricerRange { get; init; } = string.Empty;
    public string PricerPeriod { get; init; } = string.Empty;
    public int PricerMonths { get; init; }

    public bool GuaranteedFloor { get; init; }
    public OmenType OmenType { get; init; }

    /// <summary>Selected scenario numbers (as strings, e.g. ["1","2"]).</summary>
    public List<string> Scenarios { get; init; } = [];
}
