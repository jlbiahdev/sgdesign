using Microsoft.AspNetCore.SignalR;

namespace Runner.Server.Hubs;

/// <summary>
/// Hub SignalR — le dashboard React se connecte ici.
/// Événements envoyés :
///   "TaskStateChanged" → payload TaskEvent (JSON)
/// </summary>
public class TaskFlowHub : Hub
{
    // Les clients peuvent rejoindre un groupe par tâche pour écouter
    // uniquement les événements qui les intéressent.
    public async Task SubscribeToTask(long taskId)
        => await Groups.AddToGroupAsync(Context.ConnectionId, $"task-{taskId}");

    public async Task UnsubscribeFromTask(long taskId)
        => await Groups.RemoveFromGroupAsync(Context.ConnectionId, $"task-{taskId}");
}
