using Dapper;
using Styx.Domain.Models;
using Styx.JobApi.Models;
using Styx.JobApi.Repositories;
using Styx.JobApi.Services;

var builder = WebApplication.CreateBuilder(args);

// Dapper: map snake_case columns to PascalCase properties
static void RegisterDapperMapping(params Type[] types)
{
    foreach (var type in types)
    {
        SqlMapper.SetTypeMap(type, new CustomPropertyTypeMap(
            type,
            (t, col) => t.GetProperties().FirstOrDefault(p =>
                p.Name.Equals(col.Replace("_", ""), StringComparison.OrdinalIgnoreCase))));
    }
}
RegisterDapperMapping(typeof(ModelJob), typeof(DataJob), typeof(Scheduler));

var connStr = builder.Configuration.GetConnectionString("Postgres")!;

builder.Services.AddSingleton(new ModelJobRepository(connStr));
builder.Services.AddSingleton(new DataJobRepository(connStr));
builder.Services.AddSingleton(new SchedulerRepository(connStr));
builder.Services.AddSingleton<SchedulerLauncher>();
builder.Services.AddSingleton<JobDispatchService>();
builder.Services.AddSingleton<IAlertService, NoOpAlertService>();
builder.Services.AddHostedService<WatchdogService>();

builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

var app = builder.Build();

app.UseSwagger();
app.UseSwaggerUI();
app.MapControllers();
app.Run();
