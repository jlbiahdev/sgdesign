using System.Runtime.Serialization;
using System.Text.Json.Serialization;

namespace Styx.Models.Enums;

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum Periode
{
    [EnumMember(Value = "mois")]  Mois,
    [EnumMember(Value = "annee")] Annee
}
