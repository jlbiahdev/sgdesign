using System.Text.Json.Serialization;

namespace Styx.Models.Enums;

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum OmenType
{
    S2,
    S1,
    FR_GAAP,
    Solvency_II
}
