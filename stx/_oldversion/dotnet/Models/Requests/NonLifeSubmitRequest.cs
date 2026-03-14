namespace Styx.Models.Requests;

public sealed class NonLifeSubmitRequest : OmenSubmitBase
{
    /// <summary>Projection period in months.</summary>
    public int Period { get; init; }
}
