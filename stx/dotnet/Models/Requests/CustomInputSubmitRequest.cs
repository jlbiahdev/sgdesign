using System.ComponentModel.DataAnnotations;

namespace Styx.Models.Requests;

public sealed class CustomInputSubmitRequest
{
    [Required]
    public string InputsFolder { get; init; } = string.Empty;

    [Required]
    public string ActionsFolder { get; init; } = string.Empty;
}
