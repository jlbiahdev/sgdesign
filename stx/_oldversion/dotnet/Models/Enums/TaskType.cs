using System.Text.Json.Serialization;

namespace Styx.Models.Enums;

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum TaskType
{
    Full,
    Deterministic,
    Stochastic,
    InputOnly
}
