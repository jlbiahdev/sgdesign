namespace Styx.Models.Requests;

/// <summary>Shared request body for RiskLife and RiskLifeKP submissions.</summary>
public sealed class RiskLifeSubmitRequest : OmenSubmitBase
{
    /// <summary>Projection period in months.</summary>
    public int Period { get; init; }

    /// <summary>Selected scenario numbers (as strings).</summary>
    public List<string> Scenarios { get; init; } = [];
}
