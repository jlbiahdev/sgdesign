using Dapper;
using HpcLite.Scheduler.Repositories;
using HpcLite.Scheduler.Services;
using NLog;
using NLog.Web;

DefaultTypeMap.MatchNamesWithUnderscores = true;

var logger = LogManager.Setup()
    .LoadConfigurationFromFile("nlog.config")
    .GetCurrentClassLogger();

try
{
    logger.Info("HpcLite Scheduler démarrage...");

    var builder = WebApplication.CreateBuilder(args);

    builder.Host.UseWindowsService(options =>
        options.ServiceName = "HpcLite Scheduler");

    builder.Logging.ClearProviders();
    builder.Host.UseNLog();

    builder.Services.AddControllers();
    builder.Services.AddHttpClient();
    builder.Services.AddSingleton<SchedulerRepository>();
    builder.Services.AddSingleton<RunnerRepository>();
    builder.Services.AddSingleton<ModelJobRepository>();
    builder.Services.AddSingleton<DataJobRepository>();
    builder.Services.AddSingleton<RunnerDispatchService>();
    builder.Services.AddSingleton<LightJobDispatchService>();
    builder.Services.AddSingleton<IAlertService, NoOpAlertService>();
    builder.Services.AddHostedService<SchedulerRegistrationService>();
    builder.Services.AddHostedService<WatchdogService>();
    builder.Services.AddHostedService<JobListenerService>();
    builder.Services.AddHostedService<TaskFlowCompletionListener>();

    var app = builder.Build();
    app.UseDefaultFiles();
    app.UseStaticFiles();
    app.MapControllers();
    await app.RunAsync();
}
catch (Exception ex)
{
    logger.Fatal(ex, "Arrêt inattendu du Scheduler.");
    throw;
}
finally
{
    LogManager.Shutdown();
}
