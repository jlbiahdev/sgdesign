using System.Net.Http.Json;
using Dapper;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Runner.Client.Configuration;
using Runner.Client.Services;
using Runner.Core.Interfaces;
using Runner.Handlers.Examples;
using Runner.Server.Configuration;
using Runner.Server.Data;

DefaultTypeMap.MatchNamesWithUnderscores = true;

// ─── Arguments ─────────────────────────────────────────────────────
int    taskCount   = GetArgInt(args, "--tasks",   10);
int    runnerCount = GetArgInt(args, "--runners",  3);
string apiHost     = GetArgStr(args, "--host",    "http://localhost:5000");
string connStr     = GetArgStr(args, "--db",      "Host=localhost;Port=5433;Database=taskflow;Username=postgres;Password=postgres");

Console.WriteLine("╔══════════════════════════════════════════╗");
Console.WriteLine("║         TaskFlow Simulator               ║");
Console.WriteLine("╠══════════════════════════════════════════╣");
Console.WriteLine($"║  Tâches   : {taskCount,-30}║");
Console.WriteLine($"║  Workers  : {runnerCount,-30}║");
Console.WriteLine($"║  API      : {apiHost,-30}║");
Console.WriteLine("╚══════════════════════════════════════════╝");

// ─── 1. Soumettre N tâches via HTTP ────────────────────────────────
var templates = new[]
{
    new { CommandType = "DotNet", ExeName = "EchoHandler",  Args = (string?)"simulation"          },
    new { CommandType = "DotNet", ExeName = "DelayHandler", Args = (string?)"3"                   },
    new { CommandType = "Shell",  ExeName = "echo",         Args = (string?)"hello from simulator" },
};

using var http = new HttpClient { BaseAddress = new Uri(apiHost) };
var submittedIds = new List<long>();

Console.Write($"\nSoumission de {taskCount} tâches ");
for (int i = 0; i < taskCount; i++)
{
    var t = templates[i % templates.Length];
    var resp = await http.PostAsJsonAsync("/taskflow/tasks", new
    {
        externalId  = i + 1,
        commandType = t.CommandType,
        exeName     = t.ExeName,
        args        = t.Args,
    });
    resp.EnsureSuccessStatusCode();
    var created = await resp.Content.ReadFromJsonAsync<TaskCreatedResponse>();
    if (created is not null) submittedIds.Add(created.Id);
    Console.Write(i % 10 == 9 ? $"\n  [{i + 1}/{taskCount}] " : ".");
}
Console.WriteLine($"\n{taskCount} tâches soumises — IDs {submittedIds.First()}…{submittedIds.Last()}\n");

// ─── 2. Démarrer M workers ─────────────────────────────────────────
var appHost = Host.CreateDefaultBuilder()
    .ConfigureLogging(log =>
    {
        log.ClearProviders();
        log.AddConsole();
        log.SetMinimumLevel(LogLevel.Information);
    })
    .ConfigureServices(services =>
    {
        var opts = new ClientOptions
        {
            ServerId                 = "sim-" + Guid.NewGuid().ToString("N")[..6],
            FriendlyName             = $"Simulator-{runnerCount}w",
            MaxConcurrentRunners     = runnerCount,
            ConnectionString         = connStr,
            PollingIntervalMs        = 500,
            TaskTimeoutSeconds       = 120,
            HeartbeatIntervalSeconds = 30,
        };
        services.AddSingleton(opts);
        services.AddSingleton(new TaskFlowOptions { ConnectionString = connStr });
        services.AddSingleton<ITaskRepository, TaskRepository>();
        services.AddSingleton<ShellExecutor>();
        services.AddSingleton<DotNetExecutor>();
        services.AddSingleton<ITaskHandler, EchoHandler>();
        services.AddSingleton<ITaskHandler, DelayHandler>();
        services.AddHostedService<HeartbeatService>();
        services.AddHostedService<RunnerPool>();
    })
    .UseConsoleLifetime()
    .Build();

// ─── Moniteur : arrêt automatique quand tout est fini ──────────────
_ = Task.Run(async () =>
{
    var lifetime = appHost.Services.GetRequiredService<IHostApplicationLifetime>();
    var repo     = appHost.Services.GetRequiredService<ITaskRepository>();

    await Task.Delay(1_000); // laisser les workers démarrer

    while (!lifetime.ApplicationStopping.IsCancellationRequested)
    {
        try
        {
            await Task.Delay(2_000, lifetime.ApplicationStopping);
            var all  = (await repo.GetAllAsync()).ToList();
            var mine = all.Where(t => submittedIds.Contains(t.Id)).ToList();
            var done = mine.Count(t => t.State is "Finished" or "Failed" or "Canceled");
            var fail = mine.Count(t => t.State == "Failed");
            var run  = mine.Count(t => t.State == "Running");

            Console.WriteLine($"  [{DateTime.Now:HH:mm:ss}] {done}/{mine.Count} terminées" +
                              $"  ({run} en cours, {fail} échecs)");

            if (done == mine.Count && mine.Count > 0)
            {
                Console.WriteLine("\nToutes les tâches terminées.");
                Console.WriteLine($"  Succès : {mine.Count - fail}  |  Échecs : {fail}");
                lifetime.StopApplication();
                break;
            }
        }
        catch (OperationCanceledException) { break; }
    }
});

await appHost.RunAsync();
Console.WriteLine("\nSimulation terminée.");

// ─── Helpers ───────────────────────────────────────────────────────
static int GetArgInt(string[] a, string key, int def)
{
    var i = Array.IndexOf(a, key);
    return i >= 0 && i + 1 < a.Length && int.TryParse(a[i + 1], out var v) ? v : def;
}

static string GetArgStr(string[] a, string key, string def)
{
    var i = Array.IndexOf(a, key);
    return i >= 0 && i + 1 < a.Length ? a[i + 1] : def;
}

record TaskCreatedResponse(long Id, string State);
