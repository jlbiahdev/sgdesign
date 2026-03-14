using System.ComponentModel.DataAnnotations;

namespace Styx.Models.Requests;

/// <summary>Fields common to all Omen job submission requests.</summary>
public abstract class OmenSubmitBase
{
    public string? JobName { get; init; }

    [Required]
    public string Environment { get; init; } = string.Empty;

    [Required]
    public string Inputs { get; init; } = string.Empty;

    [Required]
    public bool RefModelSelected { get; init; }

    [Required]
    public string Model { get; init; } = string.Empty;

    [Required]
    public string Version { get; init; } = string.Empty;

    public bool AdvOptions { get; init; }
}
