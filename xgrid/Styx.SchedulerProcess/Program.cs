using System.Text.Json;
using Microsoft.Extensions.Configuration;
using Styx.SchedulerProcess.Models;
using Styx.SchedulerProcess.Services;

// Parse args
string? jobPath = null;
long modelJobId = 0;

for (int i = 0; i < args.Length - 1; i++)
{
    if (args[i] == "--path")          jobPath    = args[i + 1];
    if (args[i] == "--model-job-id")  long.TryParse(args[i + 1], out modelJobId);
}

if (jobPath is null || modelJobId == 0)
{
    Console.Error.WriteLine("Usage: Styx.SchedulerProcess --path <jobs.json> --model-job-id <id>");
    return 1;
}

// Configuration
var config = new ConfigurationBuilder()
    .AddJsonFile("appsettings.json", optional: false)
    .AddEnvironmentVariables()
    .Build();

var connStr = config.GetConnectionString("Postgres")!;
var heartbeatInterval = config.GetValue<int>("Scheduler:HeartbeatIntervalSeconds");
var maxParallel       = config.GetValue<int>("Scheduler:MaxParallelSubJobs");
var internalApiBase   = config["Scheduler:InternalApiBaseUrl"]!;
var httpTimeout       = config.GetValue<int>("Scheduler:SubJobHttpTimeoutSeconds");

// Services
var registry    = new SchedulerRegistry(connStr);
var heartbeat   = new HeartbeatService(connStr, heartbeatInterval);
var dataJobRepo = new DataJobRepository(connStr);

var httpClient = new HttpClient
{
    BaseAddress = new Uri(internalApiBase.TrimEnd('/') + "/"),
    Timeout     = TimeSpan.FromSeconds(httpTimeout)
};
var executor = new SubJobExecutor(httpClient);
var engine   = new DependencyEngine(executor, dataJobRepo, maxParallel);

// Register: read scheduler_id set by API, update with real PID
long schedulerId;
try
{
    schedulerId = await registry.RegisterAsync(jobPath, modelJobId, Environment.ProcessId);
}
catch (Exception ex)
{
    Console.Error.WriteLine($"[Scheduler] Registration failed: {ex.Message}");
    return 1;
}

// Start heartbeat in background
using var cts = new CancellationTokenSource();
var heartbeatTask = Task.Run(() => heartbeat.RunAsync(schedulerId, cts.Token));

// Deserialize jobs.json
JobsFile jobsFile;
try
{
    var json = await File.ReadAllTextAsync(jobPath);
    jobsFile = JsonSerializer.Deserialize<JobsFile>(json)
               ?? throw new InvalidDataException("jobs.json deserialized to null");
}
catch (Exception ex)
{
    Console.Error.WriteLine($"[Scheduler] Failed to read jobs.json: {ex.Message}");
    await registry.UnregisterAsync(schedulerId, modelJobId);
    cts.Cancel();
    await heartbeatTask;
    return 1;
}

// Run
try
{
    await engine.RunAsync(jobsFile, schedulerId, modelJobId);
}
catch (Exception ex)
{
    Console.Error.WriteLine($"[Scheduler] DependencyEngine error: {ex.Message}");
}
finally
{
    await registry.UnregisterAsync(schedulerId, modelJobId);
    cts.Cancel();
    try { await heartbeatTask; } catch { /* ignore cancellation */ }
}

return 0;
