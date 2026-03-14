using System.Text.Json.Serialization;

namespace Styx.Models.Enums;

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum JobPriority
{
    Normal,
    High,
    BelowNormal,
    AboveNormal,
    Automatic
}
