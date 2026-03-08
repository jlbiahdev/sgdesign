using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Routing;
using Runner.Core.Interfaces;
using Runner.Core.Models;

namespace Runner.Server.Endpoints;

public static class TaskFlowEndpoints
{
    /// <summary>
    /// Enregistre les routes Minimal API sous le préfixe configuré.
    /// Appeler dans Program.cs : app.MapTaskFlow()
    /// </summary>
    public static IEndpointRouteBuilder MapTaskFlow(
        this IEndpointRouteBuilder app,
        string prefix = "/taskflow")
    {
        var group = app.MapGroup(prefix).WithTags("TaskFlow");

        // POST /taskflow/tasks
        group.MapPost("/tasks", async (TaskSubmitRequest request, ITaskService svc, CancellationToken ct) =>
        {
            var id = await svc.SubmitAsync(request, ct);
            return Results.Created($"{prefix}/tasks/{id}", new { id });
        });

        // GET /taskflow/tasks
        group.MapGet("/tasks", async (ITaskService svc, CancellationToken ct) =>
        {
            var tasks = await svc.GetAllAsync(ct);
            return Results.Ok(tasks);
        });

        // GET /taskflow/tasks/{id}
        group.MapGet("/tasks/{id:long}", async (long id, ITaskService svc, CancellationToken ct) =>
        {
            var task = await svc.GetAsync(id, ct);
            return task is null ? Results.NotFound() : Results.Ok(task);
        });

        // GET /taskflow/tasks/{id}/history
        group.MapGet("/tasks/{id:long}/history", async (long id, ITaskService svc, CancellationToken ct) =>
        {
            var history = await svc.GetHistoryAsync(id, ct);
            return Results.Ok(history);
        });

        // DELETE /taskflow/tasks/{id}  → Cancel
        group.MapDelete("/tasks/{id:long}", async (long id, ITaskService svc, CancellationToken ct) =>
        {
            var ok = await svc.CancelAsync(id, ct);
            return ok ? Results.NoContent() : Results.NotFound();
        });

        // GET /taskflow/runners
        group.MapGet("/runners", async (ITaskService svc, CancellationToken ct) =>
        {
            var runners = await svc.GetRunnersAsync(ct);
            return Results.Ok(runners);
        });

        return app;
    }
}
