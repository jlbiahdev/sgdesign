namespace Styx.Models.Entities;

/// <summary>
/// A single node in the remote UNC filesystem tree returned by
/// <c>GET /api/JobEnvironment/explore</c>.
/// The <see cref="Scenarios"/> list is only populated for <c>scenario/</c> nodes.
/// </summary>
public sealed class TreeNode
{
    public List<string> Folders { get; init; } = [];
    public List<string> Files { get; init; } = [];
    public List<ScenarioDescriptor>? Scenarios { get; init; }
}
