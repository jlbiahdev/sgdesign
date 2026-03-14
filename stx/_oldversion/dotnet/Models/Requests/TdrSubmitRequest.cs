namespace Styx.Models.Requests;

public sealed class TdrSubmitRequest : OmenSubmitBase
{
    /// <summary>Period in months.</summary>
    public int Period { get; init; }
}
