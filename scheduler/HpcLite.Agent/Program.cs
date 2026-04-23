using HpcLite.Agent.Controllers;
using NLog;
using NLog.Web;

var logger = LogManager.Setup()
    .LoadConfigurationFromFile("nlog.config")
    .GetCurrentClassLogger();

try
{
    logger.Info("HpcLite Agent démarrage...");

    var builder = WebApplication.CreateBuilder(args);

    builder.Host.UseWindowsService(options =>
        options.ServiceName = "HpcLite Agent");

    builder.Logging.ClearProviders();
    builder.Host.UseNLog();

    builder.Services.AddControllers();

    var app = builder.Build();
    app.MapControllers();
    await app.RunAsync();
}
catch (Exception ex)
{
    logger.Fatal(ex, "Arrêt inattendu de l'Agent.");
    throw;
}
finally
{
    LogManager.Shutdown();
}
