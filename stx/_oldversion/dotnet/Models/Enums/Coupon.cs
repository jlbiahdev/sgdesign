using System.Text.Json.Serialization;

namespace Styx.Models.Enums;

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum Coupon
{
    ZC,
    TC
}
