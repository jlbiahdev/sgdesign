using Runner.Core.Enums;

namespace Runner.Core.Models;

public class TaskSubmitRequest
{
    public long ExternalId { get; set; }
    public CommandType CommandType { get; set; } = CommandType.Shell;

    /// <summary>
    /// Shell : chemin vers l'exécutable (ex: "cmd.exe" ou "python")
    /// DotNet : nom du handler (ex: "EchoHandler")
    /// </summary>
    public string ExeName { get; set; } = string.Empty;

    /// <summary>
    /// Shell : arguments passés au process
    /// DotNet : JSON sérialisé passé au handler
    /// </summary>
    public string? Args { get; set; }
}
