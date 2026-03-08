using System.Runtime.Serialization;
using System.Text.Json.Serialization;

namespace Styx.Models.Enums;

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum ScenarioTransfoModelType
{
    [EnumMember(Value = "2017")]   Model2017,
    [EnumMember(Value = "2018")]   Model2018,
    [EnumMember(Value = "2020")]   Model2020,
    [EnumMember(Value = "2020v2")] Model2020v2
}
