using System.Text.Json.Serialization;
using Runner.Server.Extensions;
using Runner.Server.Endpoints;
using Runner.Server.Hubs;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddTaskFlow(builder.Configuration);

builder.Services.AddCors(o => o.AddDefaultPolicy(p =>
    p.WithOrigins("http://localhost:5173")
     .AllowAnyMethod()
     .AllowAnyHeader()
     .AllowCredentials()));

// Enums sérialisés en string (Shell/DotNet au lieu de 0/1)
builder.Services.ConfigureHttpJsonOptions(o =>
    o.SerializerOptions.Converters.Add(new JsonStringEnumConverter()));

var app = builder.Build();

app.UseCors();
app.MapTaskFlow();
app.MapHub<TaskFlowHub>("/taskflow/hub");
app.MapTaskFlowDashboard();         // → http://localhost:5000/taskflow/ui

app.MapGet("/", () => Results.Redirect("/taskflow/ui"));

app.Run();
