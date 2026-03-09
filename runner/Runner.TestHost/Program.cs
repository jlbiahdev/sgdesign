using System.Text.Json.Serialization;
using Runner.Server.Extensions;
using Runner.Server.Endpoints;
using Runner.Server.Hubs;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddTaskFlow(builder.Configuration);

builder.Services.AddCors(o => o.AddDefaultPolicy(p =>
    p.WithOrigins(
        "http://localhost:5173",   // dashboard React (Vite dev)
        "http://localhost:5024",   // self
        "http://localhost:5500",   // dashboard HTML (Live Server)
        "http://localhost:5501",   // dashboard HTML (Live Server alt)
        "http://127.0.0.1:5500",
        "http://127.0.0.1:5501")
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
