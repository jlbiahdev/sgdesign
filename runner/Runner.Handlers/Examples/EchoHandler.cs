using Runner.Core.Interfaces;

namespace Runner.Handlers.Examples;

/// <summary>
/// Handler DotNet minimal : affiche les args et attend 1s.
/// Enregistrement dans Runner.Client/Program.cs :
///   services.AddSingleton&lt;ITaskHandler, EchoHandler&gt;();
/// Utilisation (exe_name = "EchoHandler", args = "hello world")
/// </summary>
public class EchoHandler : ITaskHandler
{
    public string Name => "EchoHandler";

    public async Task ExecuteAsync(string? args, CancellationToken ct)
    {
        Console.WriteLine($"[EchoHandler] Args reçus : {args ?? "(vide)"}");
        await Task.Delay(1_000, ct);
        Console.WriteLine("[EchoHandler] Terminé.");
    }
}
