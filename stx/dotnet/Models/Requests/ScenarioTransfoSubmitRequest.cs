using System.ComponentModel.DataAnnotations;
using Styx.Models.Enums;

namespace Styx.Models.Requests;

public sealed class ScenarioTransfoSubmitRequest
{
    [Required]
    public string Environment { get; init; } = string.Empty;

    [Required]
    public ScenarioTransfoModelType ModelType { get; init; }

    [Required]
    public Periode Periode { get; init; }

    [Required]
    public int Iterations { get; init; }

    [Required]
    public Coupon Coupons { get; init; }

    /// <summary>Split output into per-scenario files.</summary>
    public bool Split { get; init; }
}
