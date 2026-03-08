using System.Text.Json;
using Runner.Core.Interfaces;

namespace Runner.Handlers.Examples;

/// <summary>
/// Handler DotNet qui attend N secondes.
/// Args attendus (JSON) : { "seconds": 10 }
/// exe_name = "DelayHandler"
/// </summary>
public class DelayHandler : ITaskHandler
{
    public string Name => "DelayHandler";

    public async Task ExecuteAsync(string? args, CancellationToken ct)
    {
        int seconds = 5;

        if (!string.IsNullOrWhiteSpace(args))
        {
            // Accepte un entier simple ("10") ou du JSON ({"seconds":10})
            if (int.TryParse(args.Trim(), out var plain) && plain > 0)
                seconds = plain;
            else
            {
                var opts   = new JsonSerializerOptions { PropertyNameCaseInsensitive = true };
                var parsed = JsonSerializer.Deserialize<DelayArgs>(args, opts);
                if (parsed?.Seconds > 0) seconds = parsed.Seconds;
            }
        }

        Console.WriteLine($"[DelayHandler] Attente de {seconds}s…");
        await Task.Delay(TimeSpan.FromSeconds(seconds), ct);
        Console.WriteLine("[DelayHandler] Terminé.");
    }

    private record DelayArgs(int Seconds);
}
