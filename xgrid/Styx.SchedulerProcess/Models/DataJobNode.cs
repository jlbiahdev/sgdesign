using System.Text.Json.Serialization;
using Styx.Domain.Models;

namespace Styx.SchedulerProcess.Models;

public class DataJobNode
{
    public long Id { get; set; }
    public List<long> ParentIds { get; set; } = [];

    [JsonIgnore]
    public string State { get; set; } = RunStates.Queued;
}
