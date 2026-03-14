namespace Styx.Models.Entities;

/// <summary>A model name paired with its list of available versions.</summary>
public sealed class ModelEntry
{
    public string Model { get; init; } = string.Empty;
    public List<string> Versions { get; init; } = [];
}
