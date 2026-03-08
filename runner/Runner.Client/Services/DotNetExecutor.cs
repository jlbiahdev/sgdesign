using Microsoft.Extensions.Logging;
using Runner.Core.Interfaces;

namespace Runner.Client.Services;

public class DotNetExecutor
{
    private readonly IEnumerable<ITaskHandler> _handlers;
    private readonly ILogger<DotNetExecutor> _logger;

    public DotNetExecutor(IEnumerable<ITaskHandler> handlers, ILogger<DotNetExecutor> logger)
    {
        _handlers = handlers;
        _logger   = logger;
    }

    /// <summary>
    /// Résout le handler dont le Name correspond à exeName et l'exécute.
    /// </summary>
    public async Task RunAsync(string exeName, string? args, CancellationToken ct)
    {
        var handler = _handlers.FirstOrDefault(h =>
            string.Equals(h.Name, exeName, StringComparison.OrdinalIgnoreCase));

        if (handler is null)
            throw new InvalidOperationException(
                $"Aucun ITaskHandler enregistré avec le nom '{exeName}'.");

        _logger.LogInformation("Exécution du handler '{Name}' avec args : {Args}", handler.Name, args);
        await handler.ExecuteAsync(args, ct);
    }
}
