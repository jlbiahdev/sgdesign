using Styx.Models.Entities;
using Styx.Models.Enums;

namespace Styx.Models.Responses;

public sealed class SavingsInitResponse
{
    public string Status { get; init; } = string.Empty;
    public string? Message { get; init; }

    public string DefaultName { get; init; } = string.Empty;

    public bool DetChecked { get; init; }
    public bool StoChecked { get; init; }

    /// <summary>Default deterministic simulation period in months.</summary>
    public int DefaultDetPeriodSim { get; init; }
    /// <summary>Default deterministic iteration range, e.g. "1-2000".</summary>
    public string DefaultDetIterations { get; init; } = string.Empty;

    public int DefaultStoPeriodSim { get; init; }
    public string DefaultStoIterations { get; init; } = string.Empty;

    public int DefaultPricerPeriodSim { get; init; }
    public string DefaultPricerIterations { get; init; } = string.Empty;

    public List<ModelEntry> Models { get; init; } = [];
    public List<TaskType> TaskTypes { get; init; } = [];
    public TaskType DefaultTaskType { get; init; }
    public List<JobPriority> Priorities { get; init; } = [];
    public List<OmenType> JobOmenTypes { get; init; } = [];
    public JobPriority DefaultJobPriority { get; init; }
    public OmenType DefaultJobType { get; init; }

    public bool DefaultIsGuaranteedFloorChecked { get; init; }
    public bool DefaultIsTrdPricerEnabled { get; init; }
}
