using System.ComponentModel.DataAnnotations;

namespace Styx.Models.Requests;

public sealed class UfxSubmitRequest
{
    public string? JobName { get; init; }

    [Required]
    public string Path { get; init; } = string.Empty;

    /// <summary>true if <see cref="Path"/> points to a folder (batch UFX).</summary>
    public bool IsFolder { get; init; }
}
