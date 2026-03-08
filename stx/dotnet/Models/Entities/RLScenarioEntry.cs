namespace Styx.Models.Entities;

/// <summary>A scenario entry used in RiskLife / RiskLifeKP init responses.</summary>
public sealed class RLScenarioEntry
{
    public int Num { get; init; }
    public string Name { get; init; } = string.Empty;
    public bool Selected { get; init; }
}
