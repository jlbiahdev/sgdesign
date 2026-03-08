using Dapper;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Runner.Core.Interfaces;
using Runner.Server.Configuration;
using Runner.Server.Data;
using Runner.Server.Hubs;
using Runner.Server.Services;

namespace Runner.Server.Extensions;

public static class ServiceCollectionExtensions
{
    /// <summary>
    /// Injecte TaskFlow dans l'application hôte.
    ///
    /// Usage dans Program.cs de l'API hôte :
    ///   builder.Services.AddTaskFlow(builder.Configuration);
    ///   ...
    ///   app.MapTaskFlow();                  // endpoints HTTP
    ///   app.MapHub&lt;TaskFlowHub&gt;("/taskflow/hub");   // SignalR
    ///   app.MapTaskFlowDashboard();         // dashboard embarqué → /taskflow/ui
    /// </summary>
    public static IServiceCollection AddTaskFlow(
        this IServiceCollection services,
        IConfiguration configuration)
    {
        // snake_case (PostgreSQL) → PascalCase (C#) : exe_name → ExeName, etc.
        DefaultTypeMap.MatchNamesWithUnderscores = true;

        var options = configuration
            .GetSection(TaskFlowOptions.Section)
            .Get<TaskFlowOptions>() ?? new TaskFlowOptions();

        services.AddSingleton(options);
        services.AddSingleton<ITaskRepository, TaskRepository>();
        services.AddScoped<ITaskService, TaskService>();

        // SignalR
        services.AddSignalR();

        // Listener LISTEN/NOTIFY → SignalR
        services.AddHostedService<TaskFlowNotificationListener>();

        return services;
    }
}
