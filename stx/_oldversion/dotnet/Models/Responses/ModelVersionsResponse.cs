namespace Styx.Models.Responses;

public sealed class ModelVersionsResponse
{
    public string Model { get; init; } = string.Empty;
    public List<string> Versions { get; init; } = [];
}
