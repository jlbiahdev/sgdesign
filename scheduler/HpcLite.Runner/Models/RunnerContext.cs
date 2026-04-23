namespace HpcLite.Runner.Models;

public class RunnerContext
{
    public long   RunnerId    { get; init; }
    public long   ModelJobId  { get; init; }
    public string SettingsPath { get; init; } = "";
}
