namespace Styx.Models.Entities;

/// <summary>Generic value/label pair used in Scenario Transformator init.</summary>
public sealed class LabelValueEntry
{
    public string Value { get; init; } = string.Empty;
    public string Label { get; init; } = string.Empty;
}
