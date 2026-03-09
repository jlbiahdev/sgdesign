# TaskFlow Runner

Système d'exécution de tâches distribué avec supervision en temps réel. Basé sur .NET 8 et PostgreSQL, il permet d'envoyer des jobs depuis n'importe quel client HTTP et de les faire exécuter par un ou plusieurs workers (runners) en parallèle.

---

## Table des matières

- [Architecture](#architecture)
- [Fonctionnalités](#fonctionnalités)
- [Prérequis](#prérequis)
- [Démarrage rapide](#démarrage-rapide)
- [Configuration](#configuration)
- [Intégration client](#intégration-client)
  - [API HTTP](#api-http)
  - [Exemples curl](#exemples-curl)
  - [Temps réel avec SignalR](#temps-réel-avec-signalr)
  - [Intégration dans un host ASP.NET](#intégration-dans-un-host-aspnet)
  - [Handlers .NET personnalisés](#handlers-net-personnalisés)
- [Cycle de vie d'une tâche](#cycle-de-vie-dune-tâche)
- [Dashboard](#dashboard)
- [Structure du projet](#structure-du-projet)

---

## Architecture

```
┌──────────────────────────────────────────────────────┐
│                    API Server                        │
│         (Runner.TestHost / ASP.NET Core)             │
│  ┌─────────────────┐  ┌────────────────────────────┐ │
│  │  HTTP Endpoints │  │  SignalR Hub (/taskflow/hub)│ │
│  └─────────────────┘  └────────────────────────────┘ │
│  ┌─────────────────────────────────────────────────┐  │
│  │         Dashboard (/taskflow/ui)                │  │
│  └─────────────────────────────────────────────────┘  │
└──────────────────────────┬───────────────────────────┘
                           │
            ┌──────────────┼──────────────┐
            │              │              │
       ┌────▼────┐   ┌────▼────┐   ┌────▼────┐
       │ Runner  │   │ Runner  │   │ Runner  │
       │ Client  │   │ Client  │   │ Client  │
       └────┬────┘   └────┬────┘   └────┬────┘
            └─────────────┼─────────────┘
                          │
                ┌─────────▼─────────┐
                │    PostgreSQL     │
                │  (taskflow DB)    │
                │  task             │
                │  task_state       │
                │  server           │
                └───────────────────┘
```

**Composants :**

| Projet | Rôle |
|---|---|
| `Runner.Core` | Interfaces, modèles, enums partagés |
| `Runner.Server` | API HTTP, hub SignalR, repository, services |
| `Runner.Client` | Worker pool, exécuteurs Shell/DotNet, heartbeat |
| `Runner.Handlers` | Handlers .NET personnalisés (exemples inclus) |
| `Runner.TestHost` | Host ASP.NET de démonstration |
| `runner-dashboard` | Dashboard React (Vite + Tailwind + SignalR) |

---

## Fonctionnalités

- **Exécution distribuée** : plusieurs runners en parallèle, acquisition atomique des tâches sans conflit (`SELECT FOR UPDATE SKIP LOCKED`)
- **Deux modes d'exécution** : commandes shell OS ou handlers .NET personnalisés
- **Temps réel** : événements PostgreSQL `NOTIFY` relayés via SignalR aux clients
- **Monitoring** : heartbeat des runners, tableau de bord live, historique des états
- **Annulation** : support de `CancellationToken` à tous les niveaux
- **Audit** : journal complet des transitions d'état par tâche

---

## Prérequis

- [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0)
- [Docker](https://www.docker.com/) (pour PostgreSQL)
- [Node.js 18+](https://nodejs.org/) (optionnel, pour le dashboard en développement)

---

## Démarrage rapide

```bash
# 1. Cloner le dépôt
git clone <repo-url>
cd runner

# 2. Démarrer PostgreSQL via Docker
docker-compose up -d

# 3. Lancer le serveur API
cd Runner.TestHost
dotnet run
# → API disponible sur http://localhost:5000
# → Dashboard sur http://localhost:5000/taskflow/ui

# 4. Lancer un ou plusieurs runners (dans un autre terminal)
cd Runner.Client
dotnet run
```

Ou utiliser le script de démarrage rapide :

```bash
./dev-start.sh   # Démarre PostgreSQL + Runner + Dashboard
./dev-stop.sh    # Arrête tout
```

---

## Configuration

### Serveur (`Runner.TestHost/appsettings.json`)

```json
{
  "TaskFlow": {
    "ConnectionString": "Host=localhost;Port=5433;Database=taskflow;Username=postgres;Password=postgres",
    "RoutePrefix": "/taskflow"
  }
}
```

### Runner client (`Runner.Client/appsettings.json`)

```json
{
  "Runner": {
    "ConnectionString": "Host=localhost;Port=5433;Database=taskflow;Username=postgres;Password=postgres",
    "ServerId": "runner-01",
    "FriendlyName": "Runner-MacOS-01",
    "MaxConcurrentRunners": 2,
    "PollingIntervalMs": 2000,
    "TaskTimeoutSeconds": 300,
    "HeartbeatIntervalSeconds": 30
  }
}
```

---

## Intégration client

### API HTTP

#### Soumettre une tâche

```http
POST /taskflow/tasks
Content-Type: application/json

{
  "externalId": 12345,
  "commandType": "Shell",
  "exeName": "python",
  "args": "script.py --input data.csv"
}
```

`commandType` peut être `"Shell"` (commande OS) ou `"DotNet"` (handler .NET).

Réponse :
```json
{ "id": 789 }
```

#### Consulter une tâche

```http
GET /taskflow/tasks/789
```

```json
{
  "id": 789,
  "externalId": 12345,
  "state": "Running",
  "commandType": "Shell",
  "exeName": "python",
  "args": "script.py --input data.csv",
  "createdAt": "2025-03-09T10:00:00Z"
}
```

#### Lister toutes les tâches

```http
GET /taskflow/tasks
```

#### Historique des états d'une tâche

```http
GET /taskflow/tasks/789/history
```

#### Annuler une tâche

```http
DELETE /taskflow/tasks/789
```

#### Lister les runners actifs

```http
GET /taskflow/runners
```

---

### Exemples curl

```bash
BASE=http://localhost:5000/taskflow
```

#### Soumettre une tâche Shell

```bash
curl -s -X POST "$BASE/tasks" \
  -H "Content-Type: application/json" \
  -d '{
    "externalId": 1,
    "commandType": "Shell",
    "exeName": "python",
    "args": "script.py --input data.csv"
  }' | jq
# → { "id": 42 }
```

#### Soumettre une tâche DotNet

```bash
curl -s -X POST "$BASE/tasks" \
  -H "Content-Type: application/json" \
  -d '{
    "externalId": 2,
    "commandType": "DotNet",
    "exeName": "EchoHandler",
    "args": "hello world"
  }' | jq
```

#### Lister toutes les tâches

```bash
curl -s "$BASE/tasks" | jq
```

#### Consulter une tâche

```bash
curl -s "$BASE/tasks/42" | jq
```

#### Historique des états d'une tâche

```bash
curl -s "$BASE/tasks/42/history" | jq
```

#### Annuler une tâche

```bash
curl -s -X DELETE "$BASE/tasks/42" -w "%{http_code}"
# → 204 (succès) ou 404 (tâche introuvable)
```

#### Lister les runners actifs

```bash
curl -s "$BASE/runners" | jq
```

#### Boucle d'attente jusqu'à la fin d'une tâche

```bash
TASK_ID=42
while true; do
  STATE=$(curl -s "$BASE/tasks/$TASK_ID" | jq -r '.state')
  echo "$(date +%T) → $STATE"
  case "$STATE" in
    Finished|Failed|Canceled) break ;;
  esac
  sleep 2
done
```

---

### Temps réel avec SignalR

Le hub est disponible à `/taskflow/hub`.

```javascript
import * as signalR from "@microsoft/signalr";

const connection = new signalR.HubConnectionBuilder()
  .withUrl("http://localhost:5000/taskflow/hub")
  .withAutomaticReconnect()
  .build();

// Écouter tous les changements d'état
connection.on("TaskStateChanged", (event) => {
  console.log(`Task ${event.taskId} → ${event.state}`);
});

// Écouter les changements de runners
connection.on("RunnerChanged", (runner) => {
  console.log(`Runner ${runner.serverId} mis à jour`);
});

await connection.start();

// S'abonner à une tâche spécifique
await connection.invoke("SubscribeToTask", 789);
```

**Événement `TaskStateChanged` :**

```typescript
{
  taskId: number;
  state: "Submitted" | "Running" | "Finished" | "Failed" | "Canceled";
  serverId: string;
  reason?: string;
  timestamp: string;
}
```

---

### Intégration dans un host ASP.NET

Ajoutez TaskFlow à votre application ASP.NET existante en quelques lignes.

**1. Enregistrer les services**

```csharp
// Program.cs
builder.Services.AddTaskFlow(builder.Configuration);
builder.Services.AddSignalR();
```

**2. Mapper les endpoints**

```csharp
var app = builder.Build();

app.MapTaskFlow();                                     // Routes HTTP
app.MapHub<TaskFlowHub>("/taskflow/hub");              // SignalR
app.MapTaskFlowDashboard();                            // Dashboard HTML
```

**3. Utiliser `ITaskService` dans vos controllers**

```csharp
public class JobController : ControllerBase
{
    private readonly ITaskService _taskService;

    public JobController(ITaskService taskService)
    {
        _taskService = taskService;
    }

    [HttpPost("jobs")]
    public async Task<IActionResult> Submit(JobRequest req, CancellationToken ct)
    {
        var taskId = await _taskService.SubmitAsync(new TaskSubmitRequest
        {
            ExternalId = req.JobId,
            CommandType = CommandType.Shell,
            ExeName = "ffmpeg",
            Args = $"-i {req.InputFile} -o {req.OutputFile}"
        }, ct);

        return Accepted(new { taskId });
    }

    [HttpGet("jobs/{id}/status")]
    public async Task<IActionResult> Status(long id, CancellationToken ct)
    {
        var task = await _taskService.GetAsync(id, ct);
        return task is null ? NotFound() : Ok(task);
    }
}
```

**Interface `ITaskService` complète :**

```csharp
Task<long> SubmitAsync(TaskSubmitRequest request, CancellationToken ct);
Task<TaskRecord?> GetAsync(long id, CancellationToken ct);
Task<IEnumerable<TaskRecord>> GetAllAsync(CancellationToken ct);
Task<bool> CancelAsync(long id, CancellationToken ct);
Task<IEnumerable<TaskStateRecord>> GetHistoryAsync(long id, CancellationToken ct);
Task<IEnumerable<ServerRecord>> GetRunnersAsync(CancellationToken ct);
```

---

### Handlers .NET personnalisés

Pour exécuter du code .NET arbitraire via le système de tâches :

**1. Implémenter `ITaskHandler`**

```csharp
using Runner.Core.Interfaces;

public class VideoConvertHandler : ITaskHandler
{
    public string Name => "VideoConvert";

    public async Task ExecuteAsync(string? args, CancellationToken ct)
    {
        // args peut être une chaîne JSON ou simple
        var options = JsonSerializer.Deserialize<ConvertOptions>(args!);

        // Votre logique métier ici
        await ConvertVideoAsync(options, ct);
    }
}
```

**2. Enregistrer le handler dans le runner**

```csharp
// Runner.Client/Program.cs
services.AddSingleton<ITaskHandler, VideoConvertHandler>();
```

**3. Soumettre une tâche de type DotNet**

```http
POST /taskflow/tasks
Content-Type: application/json

{
  "externalId": 42,
  "commandType": "DotNet",
  "exeName": "VideoConvert",
  "args": "{\"inputPath\": \"/media/input.mp4\", \"format\": \"webm\"}"
}
```

Le runner résout le handler par son `Name` et appelle `ExecuteAsync`.

---

## Cycle de vie d'une tâche

```
Submitted
    │
    ▼
Running  ←──── (reprise si runner crash)
    │
    ├──→ Finished   (succès)
    ├──→ Failed     (exception non gérée)
    └──→ Canceled   (DELETE /taskflow/tasks/{id})
```

Chaque transition est enregistrée dans `task_state` avec horodatage, `serverId` et raison optionnelle.

---

## Dashboard

Accessible à `/taskflow/ui` (embedded dans le serveur, aucune dépendance externe).

Affiche en temps réel :
- Statistiques globales (total, en cours, terminées, échouées)
- Liste des runners actifs avec statut heartbeat
- Tableau des tâches avec filtrage par état
- Historique des transitions pour chaque tâche

---

## Structure du projet

```
runner/
├── Runner.Core/               # Contrats partagés
│   ├── Interfaces/
│   │   ├── ITaskHandler.cs
│   │   ├── ITaskRepository.cs
│   │   └── ITaskService.cs
│   ├── Enums/
│   │   ├── CommandType.cs     # Shell | DotNet
│   │   └── WorkStatus.cs      # Submitted | Running | Finished | Failed | Canceled
│   └── Models/
│       ├── TaskRecord.cs
│       ├── TaskSubmitRequest.cs
│       ├── TaskStateRecord.cs
│       ├── ServerRecord.cs
│       └── TaskEvent.cs
│
├── Runner.Server/             # Serveur API
│   ├── Data/TaskRepository.cs
│   ├── Services/
│   │   ├── TaskService.cs
│   │   └── TaskFlowNotificationListener.cs   # LISTEN/NOTIFY → SignalR
│   ├── Endpoints/
│   │   ├── TaskFlowEndpoints.cs
│   │   └── TaskFlowDashboardEndpoints.cs
│   ├── Hubs/TaskFlowHub.cs
│   ├── Extensions/ServiceCollectionExtensions.cs
│   └── Configuration/TaskFlowOptions.cs
│
├── Runner.Client/             # Worker distribué
│   ├── Services/
│   │   ├── RunnerPool.cs
│   │   ├── HeartbeatService.cs
│   │   ├── ShellExecutor.cs
│   │   └── DotNetExecutor.cs
│   ├── Configuration/ClientOptions.cs
│   └── appsettings.json
│
├── Runner.Handlers/           # Handlers d'exemple
│   └── Examples/
│       ├── EchoHandler.cs
│       └── DelayHandler.cs
│
├── Runner.TestHost/           # Host de démonstration
│   └── Program.cs
│
├── runner-dashboard/          # Dashboard React
│   ├── package.json
│   └── src/
│
├── migrations/                # Scripts SQL PostgreSQL
│   ├── 001_initial.sql
│   └── 003_runner_notify.sql
│
├── docker-compose.yml
├── dev-start.sh
└── dev-stop.sh
```
