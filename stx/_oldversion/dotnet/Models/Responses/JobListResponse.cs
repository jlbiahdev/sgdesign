using Styx.Models.Entities;
using Styx.Models.Enums;

namespace Styx.Models.Responses;

public sealed class JobListResponse
{
    public string Status { get; init; } = string.Empty;
    public string? Message { get; init; }
    public string? Warnings { get; init; }
    public List<JobItem> Jobs { get; init; } = [];
}

public sealed class JobItem
{
    public int Id { get; init; }
    public string Name { get; init; } = string.Empty;
    public string UserAccountId { get; init; } = string.Empty;
    public string UserName { get; init; } = string.Empty;

    /// <summary>0–100.</summary>
    public int Progress { get; init; }

    public DateTime? SubmitTime { get; init; }
    public DateTime? CreateTime { get; init; }
    public DateTime? ChangeTime { get; init; }

    public JobState State { get; init; }
    public JobPriority Priority { get; init; }
    public bool HasChildrens { get; init; }
    public string? WorkFolder { get; init; }
    public int GridCost { get; init; }
    public bool IsFastPass { get; init; }
    public string Environment { get; init; } = string.Empty;

    /// <summary>
    /// Job-type-specific submitted settings. Shape varies by <c>type</c> field.
    /// null for UFX and other jobs that don't store settings.
    /// </summary>
    public JobSettings? Settings { get; init; }
}

/// <summary>
/// Free-form settings stored alongside a parent job.
/// The <see cref="Type"/> discriminator determines which additional fields are present.
/// </summary>
public sealed class JobSettings
{
    public string Type { get; init; } = string.Empty;
    public string? JobName { get; init; }
    public string? Environment { get; init; }
    public string? Inputs { get; init; }
    public bool RefModelSelected { get; init; }
    public string? Model { get; init; }
    public string? Version { get; init; }
    public bool AdvOptions { get; init; }

    // Savings-specific
    public bool? DetEnabled { get; init; }
    public string? DetRange { get; init; }
    public string? DetPeriod { get; init; }
    public int? DetMonths { get; init; }
    public bool? StoEnabled { get; init; }
    public string? StoRange { get; init; }
    public string? StoPeriod { get; init; }
    public int? StoMonths { get; init; }
    public bool? PricerEnabled { get; init; }
    public string? PricerRange { get; init; }
    public string? PricerPeriod { get; init; }
    public int? PricerMonths { get; init; }
    public bool? GuaranteedFloor { get; init; }
    public string? OmenType { get; init; }

    // NonLife / TdR / RiskLife / RiskLifeKP
    public int? Period { get; init; }

    // BRD
    public int? ProjectionDuration { get; init; }

    // Shared
    public List<string>? Scenarios { get; init; }
}
