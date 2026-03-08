namespace Runner.Core.Interfaces;

/// <summary>
/// Contrat pour les handlers .NET typés.
/// Le nom doit correspondre au champ exe_name de la tâche.
/// </summary>
public interface ITaskHandler
{
    string Name { get; }
    Task ExecuteAsync(string? args, CancellationToken ct);
}
