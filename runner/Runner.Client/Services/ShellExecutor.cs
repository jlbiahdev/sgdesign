using System.Diagnostics;
using Microsoft.Extensions.Logging;

namespace Runner.Client.Services;

public class ShellExecutor
{
    private readonly ILogger<ShellExecutor> _logger;

    public ShellExecutor(ILogger<ShellExecutor> logger)
    {
        _logger = logger;
    }

    /// <summary>
    /// Lance un processus shell et attend sa fin.
    /// Lève une exception si le code de retour est non nul.
    /// </summary>
    public async Task RunAsync(string exeName, string? args, CancellationToken ct)
    {
        var psi = new ProcessStartInfo
        {
            FileName               = exeName,
            Arguments              = args ?? string.Empty,
            RedirectStandardOutput = true,
            RedirectStandardError  = true,
            UseShellExecute        = false,
            CreateNoWindow         = true
        };

        using var process = new Process { StartInfo = psi, EnableRaisingEvents = true };

        process.OutputDataReceived += (_, e) =>
        {
            if (e.Data is not null) _logger.LogInformation("[stdout] {Line}", e.Data);
        };
        process.ErrorDataReceived += (_, e) =>
        {
            if (e.Data is not null) _logger.LogWarning("[stderr] {Line}", e.Data);
        };

        process.Start();
        process.BeginOutputReadLine();
        process.BeginErrorReadLine();

        // Permet l'annulation via CancellationToken
        ct.Register(() =>
        {
            try { if (!process.HasExited) process.Kill(entireProcessTree: true); }
            catch { /* process déjà terminé */ }
        });

        await process.WaitForExitAsync(ct);

        if (process.ExitCode != 0)
            throw new InvalidOperationException(
                $"Process '{exeName}' terminated with exit code {process.ExitCode}.");
    }
}
