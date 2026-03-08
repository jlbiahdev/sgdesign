namespace Styx.Models.Enums;

/// <summary>
/// Numeric state used in child jobs and job groups.
/// </summary>
public enum ChildJobState
{
    Queued   = 0,
    Running  = 1,
    Finished = 2,
    Failed   = 3,
    Canceled = 4
}
