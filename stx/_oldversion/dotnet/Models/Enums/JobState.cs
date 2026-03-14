using System.Text.Json.Serialization;

namespace Styx.Models.Enums;

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum JobState
{
    Running,
    Queued,
    Finished,
    Failed,
    Canceled
}
