using System.Text.Json.Serialization;
using Styx.Models.Entities;

namespace Styx.Models.Responses;

public sealed class ExploreResponse
{
    /// <summary>UNC root of the server, e.g. \\srvrbxassufp01.</summary>
    [JsonPropertyName("_root")]
    public string Root { get; init; } = string.Empty;

    /// <summary>
    /// Flat dictionary keyed by relative path from root (empty string = root).
    /// </summary>
    [JsonPropertyName("_tree")]
    public Dictionary<string, TreeNode> Tree { get; init; } = [];
}
