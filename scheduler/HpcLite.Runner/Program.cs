using Dapper;
using HpcLite.Domain.Models;
using HpcLite.Runner.Repositories;
using HpcLite.Runner.Services;
using Microsoft.Extensions.Configuration;
using NLog;
using System.Text.Json;

DefaultTypeMap.MatchNamesWithUnderscores = true;

var logger = LogManager.Setup()
    .LoadConfigurationFromFile("nlog.config")
    .GetCurrentClassLogger();

try
{
    // 1. Parser les arguments
    var runnerId     = ParseArg<long>(args, "--runner-id");
    var settingsPath = ParseArg<string>(args, "--path");

    logger.Info("Runner id={RunnerId} démarrage pour settings={Path}", runnerId, settingsPath);

    // 2. Charger la configuration
    var configuration = new ConfigurationBuilder()
        .AddJsonFile("appsettings.json", optional: false)
        .AddEnvironmentVariables()
        .Build();

    var connectionString  = configuration.GetConnectionString("Postgres")!;
    var heartbeatInterval = configuration.GetValue<int>("Runner:HeartbeatIntervalSeconds", 10);

    // 3. Lire settings.json → extraire model_job_id
    var settings   = JsonSerializer.Deserialize<SettingsFile>(File.ReadAllText(settingsPath))
                     ?? throw new InvalidDataException("settings.json invalide");
    var modelJobId = settings.ModelJobId;

    logger.Info("model_job_id={ModelJobId} extrait depuis settings.json", modelJobId);

    // 4. Instancier les services
    var runnerRepo   = new RunnerRepository(connectionString);
    var modelJobRepo = new ModelJobRepository(connectionString);
    var registration = new RunnerRegistrationService(runnerRepo, modelJobRepo);
    var heartbeat    = new HeartbeatService(runnerRepo, heartbeatInterval);

    // 5. S'enregistrer en DB
    var context = await registration.RegisterAsync(runnerId, modelJobId, settingsPath);
    logger.Info("Runner id={RunnerId} actif en DB pour model_job={ModelJobId}", context.RunnerId, context.ModelJobId);

    // 6. Démarrer le heartbeat
    using var cts = new CancellationTokenSource();
    var heartbeatTask = heartbeat.RunAsync(runnerId, cts.Token);

    try
    {
        // 7. PLACEHOLDER — logique métier existante à brancher ici
        // Reçoit : context.RunnerId, context.ModelJobId, context.SettingsPath
        await Task.CompletedTask;
    }
    finally
    {
        // 8. Arrêter le heartbeat
        await cts.CancelAsync();
        await heartbeatTask;

        // 9. Se désenregistrer
        await registration.UnregisterAsync(runnerId, modelJobId);
        logger.Info("Runner id={RunnerId} terminé, statut remis à idle.", runnerId);
    }
}
catch (Exception ex)
{
    logger.Fatal(ex, "Runner terminé avec une erreur.");
    throw;
}
finally
{
    LogManager.Shutdown();
}

// -----------------------------------------------------------------------

static T ParseArg<T>(string[] args, string flag)
{
    for (var i = 0; i < args.Length - 1; i++)
    {
        if (args[i].Equals(flag, StringComparison.OrdinalIgnoreCase))
            return (T)Convert.ChangeType(args[i + 1], typeof(T));
    }
    throw new ArgumentException($"Argument manquant : {flag}");
}
