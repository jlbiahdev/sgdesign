using System.ComponentModel.DataAnnotations;

namespace Styx.Models.Requests;

/// <summary>Request body for cancel and requeue operations.</summary>
public sealed class JobActionRequest
{
    [Required]
    public int JobId { get; init; }
}
