namespace Styx.Models.Entities;

/// <summary>
/// Describes a single scenario in the Savings scenario library or the
/// filesystem explore tree (scenario/ nodes).
/// </summary>
public sealed class ScenarioDescriptor
{
    public int ScenarioNum { get; init; }
    public string CalVif { get; init; } = string.Empty;

    public string? Filename { get; init; }
    public string? FilenameDot { get; init; }
    public string? FilenameSp { get; init; }

    public List<string> FilenameL { get; init; } = [];
    public List<string> FilenameDotL { get; init; } = [];
    public List<string> FilenameSpL { get; init; } = [];

    public List<string> DollFilenameL { get; init; } = [];
    public List<string> DollFilenameDotD { get; init; } = [];
    public List<string> DollFilenameSpL { get; init; } = [];
    public List<string> ListDollarFiles { get; init; } = [];

    public string? Description { get; init; }
    public bool IsScenarioSelected { get; init; }
    public bool IsEnabled { get; init; }
    public int Depth { get; init; }
}
