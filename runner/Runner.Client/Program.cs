using Dapper;
using Runner.Client.Configuration;
using Runner.Client.Services;
using Runner.Core.Interfaces;
using Runner.Handlers.Examples;
using Runner.Server.Data;
using Runner.Server.Configuration;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Configuration;

// snake_case PostgreSQL → PascalCase C# (exe_name → ExeName, etc.)
DefaultTypeMap.MatchNamesWithUnderscores = true;

// -----------------------------------------------------------------------
// Pour déployer en Windows Service, remplacer UseConsoleLifetime() par
// UseWindowsService() et activer le package WindowsServices dans le .csproj
// -----------------------------------------------------------------------

var host = Host.CreateDefaultBuilder(args)
    .ConfigureAppConfiguration(cfg => cfg
        .AddJsonFile("appsettings.json", optional: false)
        .AddJsonFile($"appsettings.{Environment.GetEnvironmentVariable("DOTNET_ENVIRONMENT") ?? "Production"}.json", optional: true)
        .AddEnvironmentVariables())
    .ConfigureServices((ctx, services) =>
    {
        // Options
        var clientOptions = ctx.Configuration
            .GetSection(ClientOptions.Section)
            .Get<ClientOptions>() ?? new ClientOptions();

        // Chaque processus Runner.Client reçoit un suffixe unique,
        // que ServerId soit configuré (préfixe) ou non (MachineName).
        var instanceSuffix = Guid.NewGuid().ToString("N")[..6];
        clientOptions.ServerId = (string.IsNullOrWhiteSpace(clientOptions.ServerId)
            ? Environment.MachineName
            : clientOptions.ServerId) + "-" + instanceSuffix;
        clientOptions.FriendlyName = clientOptions.FriendlyName + "-" + instanceSuffix;

        services.AddSingleton(clientOptions);

        // TaskFlowOptions (partagé avec Runner.Server pour le repository)
        services.AddSingleton(new TaskFlowOptions
        {
            ConnectionString = clientOptions.ConnectionString
        });

        // Repository
        services.AddSingleton<ITaskRepository, TaskRepository>();

        // Exécuteurs
        services.AddSingleton<ShellExecutor>();
        services.AddSingleton<DotNetExecutor>();

        // ITaskHandler enregistrés
        services.AddSingleton<ITaskHandler, EchoHandler>();
        services.AddSingleton<ITaskHandler, DelayHandler>();

        // Workers
        services.AddHostedService<HeartbeatService>();
        services.AddHostedService<RunnerPool>();
    })
    // .UseWindowsService()   // ← décommenter pour déploiement Windows Service
    .UseConsoleLifetime()
    .Build();

await host.RunAsync();
