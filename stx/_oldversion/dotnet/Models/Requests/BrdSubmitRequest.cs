namespace Styx.Models.Requests;

public sealed class BrdSubmitRequest : OmenSubmitBase
{
    /// <summary>Projection duration in years.</summary>
    public int ProjectionDuration { get; init; }

    /// <summary>Selected scenario numbers (as strings).</summary>
    public List<string> Scenarios { get; init; } = [];
}
