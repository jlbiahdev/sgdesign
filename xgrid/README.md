# JobApi + SchedulerProcess — README pour Claude Code

## Contexte

Application .NET 8 dans la solution **Styx**, composée de deux projets :

- **JobApi** : API REST qui reçoit des demandes de lancement de jobs, génère les fichiers JSON de configuration, et orchestre le démarrage des Schedulers.
- **SchedulerProcess** : application console .NET 8 lancée en tant que process externe par l'API. Chaque instance reçoit un path en argument, lit le JSON du share, et exécute les DataJob en respectant leurs dépendances via un appel à une API interne.

Le JSON du share est le **contrat entre l'API et le Scheduler**. Il contient uniquement les identifiants et les dépendances des DataJob. Toute la configuration métier reste en DB — l'API interne la récupère elle-même lors de l'exécution de chaque DataJob.

---

## Namespace

- `Styx.JobApi`
- `Styx.SchedulerProcess`
- `Styx.Domain` (modèles partagés — projet de bibliothèque existant)

---

## Modèles existants (ne pas recréer)

Ces classes existent déjà dans `Styx.Domain.Models`. Les référencer, ne pas les redéfinir.

### `ModelJob`

Job principal soumis par l'utilisateur. Propriété à ajouter : `long? SchedulerId`.

Ne jamais modifier `IsPurged` depuis le Scheduler.

Le state du `ModelJob` n'est pas une colonne — il est calculé dynamiquement depuis les `DataJob` enfants (voir section États).

### `DataJob`

Sous-job envoyé à la grille. Propriétés clés utilisées par le Scheduler :

```csharp
public long Id { get; set; }
public long ParentModelId { get; set; }
public string Name { get; set; }
public string State { get; set; } = RunStates.Created;
public int Progress { get; set; }
public int RetryLimit { get; set; }
public DateTime? StartDateTime { get; set; }
public DateTime ChangeDateTime { get; set; }
```

### `RunStates`

```csharp
public static class RunStates
{
    public static string Created            = "Created";
    public static string Configuring        = "Configuring";
    public static string Submitted          = "Submitted";
    public static string Validating         = "Validating";
    public static string Queued             = "Queued";
    public static string Running            = "Running";
    public static string Finishing          = "Finishing";
    public static string Finished           = "Finished";
    public static string Failed             = "Failed";
    public static string Canceling          = "Canceling";
    public static string Canceled           = "Canceled";
    public static string ExternalValidation = "ExternalValidation";
}
```

**State dérivé du `ModelJob`** (requête SQL existante — ne pas modifier) :

| Condition sur les `DataJob` enfants | State dérivé |
|---|---|
| Au moins un `Failed` | `Failed` |
| Au moins un `Canceling` ou `Canceled` | `Canceled` |
| Au moins un `Running` + d'autres en cours | `Running` |
| Tous `Finishing` ou `Finished` | `Finished` |
| Sinon | `Queued` |

---

## Tables existantes (ne pas recréer)

### `public.model_job`

Colonne à ajouter :

```sql
ALTER TABLE public.model_job
ADD COLUMN IF NOT EXISTS scheduler_id BIGINT REFERENCES schedulers(id);
```

### `public.data_job`

Utilisée telle quelle. Le Scheduler met à jour `state`, `progress`, `start_date_time`, `change_date_time`.

### `public.data_job_parent`

```sql
job_id        integer NOT NULL REFERENCES data_job(id) ON DELETE CASCADE
parent_job_id integer NOT NULL REFERENCES data_job(id) ON DELETE CASCADE
PRIMARY KEY (job_id, parent_job_id)
```

Utilisée par l'API pour construire les `parent_ids` dans le JSON du share. Le Scheduler ne lit pas cette table.

---

## Table à créer

### `public.schedulers`

```sql
CREATE TABLE IF NOT EXISTS public.schedulers (
    id           BIGSERIAL PRIMARY KEY,
    pid          INTEGER NOT NULL,
    host         TEXT NOT NULL,
    model_job_id BIGINT REFERENCES model_job(id),
    job_path     TEXT NOT NULL,
    status       TEXT NOT NULL DEFAULT 'active',  -- active | dead
    started_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    heartbeat    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

---

## Format du JSON du share

Fichier : `{ShareBasePath}/{modelJobId}_{yyyyMMddTHHmmss}/jobs.json`

```json
{
  "model_job_id": 123,
  "data_jobs": [
    { "id": 450, "parent_ids": [] },
    { "id": 451, "parent_ids": [450] },
    { "id": 452, "parent_ids": [450] },
    { "id": 453, "parent_ids": [] },
    { "id": 454, "parent_ids": [453, 452, 451] },
    { "id": 455, "parent_ids": [454] }
  ]
}
```

`parent_ids` est construit par l'API depuis `data_job_parent` au moment de la sérialisation. Le Scheduler n'a besoin que de `id` (pour l'appel à l'API interne) et de `parent_ids` (pour résoudre les dépendances).

---

## Structure de la solution

```
/Styx.sln
├── /Styx.Domain                        # Bibliothèque de modèles partagés (existante)
│   └── Models/
│       ├── ModelJob.cs                 # + ajouter long? SchedulerId
│       ├── DataJob.cs
│       ├── RunStates.cs
│       └── CommandType.cs
│
├── /Styx.JobApi                        # ASP.NET Core 8 Web API
│   ├── Controllers/
│   │   └── JobsController.cs           # POST /jobs, GET /jobs/{id}, GET /schedulers/ping
│   ├── Services/
│   │   ├── JobDispatchService.cs       # Vérification slots + tentative dispatch
│   │   ├── SchedulerLauncher.cs        # Spawn du process SchedulerProcess
│   │   └── WatchdogService.cs          # Background service : détection crash + alertes
│   ├── Repositories/
│   │   ├── SchedulerRepository.cs
│   │   ├── ModelJobRepository.cs
│   │   └── DataJobRepository.cs
│   ├── Models/
│   │   └── JobRequest.cs               # { long ModelJobId }
│   ├── appsettings.json
│   └── Program.cs
│
├── /Styx.SchedulerProcess              # Console App .NET 8
│   ├── Services/
│   │   ├── DependencyEngine.cs         # Résolution des dépendances + orchestration
│   │   ├── SubJobExecutor.cs           # Appel HTTP vers l'API interne
│   │   ├── HeartbeatService.cs         # Heartbeat périodique en DB
│   │   └── SchedulerRegistry.cs        # Enregistrement / désenregistrement en DB
│   ├── Models/
│   │   ├── JobsFile.cs                 # Désérialisation de jobs.json
│   │   └── DataJobNode.cs              # { long Id, List<long> ParentIds, string State }
│   ├── appsettings.json
│   └── Program.cs
│
└── /Database
    └── migrations.sql                  # CREATE schedulers + ALTER model_job
```

---

## Configuration

### `Styx.JobApi/appsettings.json`

```json
{
  "ConnectionStrings": {
    "Postgres": "Host=localhost;Database=styx;Username=postgres;Password=secret"
  },
  "Orchestrator": {
    "MaxConcurrentSchedulers": 5,
    "ShareBasePath": "C:\\shares\\styx\\jobs",
    "SchedulerExePath": "C:\\apps\\Styx.SchedulerProcess\\Styx.SchedulerProcess.exe",
    "HeartbeatTimeoutSeconds": 60,
    "WatchdogIntervalSeconds": 15
  }
}
```

### `Styx.SchedulerProcess/appsettings.json`

```json
{
  "ConnectionStrings": {
    "Postgres": "Host=localhost;Database=styx;Username=postgres;Password=secret"
  },
  "Scheduler": {
    "HeartbeatIntervalSeconds": 10,
    "MaxParallelSubJobs": 4,
    "InternalApiBaseUrl": "http://internal-omen-service/api",
    "SubJobHttpTimeoutSeconds": 300
  }
}
```

---

## Styx.JobApi — détail des composants

### `POST /jobs`

**Body :**
```json
{ "model_job_id": 123 }
```

**Comportement :**

1. Charger le `ModelJob` depuis la DB. Retourner `404` s'il n'existe pas, `400` si `IsPurged = true`, `409` si `SchedulerId` est déjà renseigné (job déjà en cours).
2. Charger ses `DataJob` et construire les `parent_ids` depuis `data_job_parent`.
3. Créer le dossier `{ShareBasePath}/{modelJobId}_{yyyyMMddTHHmmss}/`.
4. Écrire `jobs.json` : tableau de `{ id, parent_ids }` pour chaque `DataJob`.
5. Appeler `JobDispatchService.TryDispatchAsync(modelJobId, jobPath)`.
6. Retourner `202 Accepted` : `{ "model_job_id": 123, "status": "dispatched" | "queued" }`.

---

### `GET /jobs/{modelJobId}`

Retourne le `ModelJob` avec son state dérivé et la liste des `DataJob` avec leurs états.

---

### `GET /schedulers/ping`

Pour chaque scheduler `active` en DB, vérifie si `heartbeat > NOW() - HeartbeatTimeoutSeconds`. Retourne la liste avec état `alive` ou `stale`.

---

### `JobDispatchService`

```
Compter les schedulers actifs :
  SELECT COUNT(*) FROM schedulers
  WHERE status = 'active'
  AND heartbeat > NOW() - interval '{HeartbeatTimeoutSeconds} seconds'

Si count < MaxConcurrentSchedulers :
    SELECT id FROM model_job
    WHERE id = @modelJobId AND scheduler_id IS NULL
    FOR UPDATE SKIP LOCKED
    → Si verrou obtenu : SchedulerLauncher.SpawnAsync(modelJobId, jobPath)
    → Sinon : log "Already dispatched"

Sinon :
    Log "No slot available — model_job {id} remains Queued"
    Retourner status = "queued"
```

---

### `SchedulerLauncher`

```csharp
var process = new Process
{
    StartInfo = new ProcessStartInfo
    {
        FileName        = schedulerExePath,
        Arguments       = $"--path \"{jobPath}\" --model-job-id {modelJobId}",
        UseShellExecute = false,
        CreateNoWindow  = true
    }
};
process.Start();
// Ne pas appeler WaitForExit — le suivi se fait via la DB
```

Après le spawn, mettre à jour `model_job.scheduler_id` avec l'id du scheduler nouvellement inséré.

---

### `WatchdogService` (IHostedService)

S'exécute toutes les `WatchdogIntervalSeconds` secondes.

1. Détecter les Schedulers expirés :
```sql
SELECT * FROM schedulers
WHERE status = 'active'
AND heartbeat < NOW() - INTERVAL '{HeartbeatTimeoutSeconds} seconds';
```

2. Pour chaque Scheduler expiré :
   - `UPDATE schedulers SET status = 'dead' WHERE id = @id`
   - `UPDATE data_job SET state = 'Failed', change_date_time = NOW() WHERE parent_model_id = @modelJobId AND state NOT IN ('Finished', 'Failed', 'Canceled')`
   - `UPDATE model_job SET scheduler_id = NULL WHERE id = @modelJobId`
   - Logger `ERROR` : `"[Watchdog] Scheduler {id} (PID {pid} on {host}) timed out. ModelJob {modelJobId} marked Failed."`
   - Appeler `IAlertService.NotifyAsync(schedulerId, modelJobId)` — interface à implémenter selon l'infra

3. Tenter un dispatch pour les `ModelJob` dont `scheduler_id IS NULL` et qui ont des `DataJob` à `Queued`.

---

## Styx.SchedulerProcess — détail des composants

### `Program.cs`

Parse `--path` et `--model-job-id`. Configure les services via `IServiceCollection`.

**Séquence :**

1. `SchedulerRegistry.RegisterAsync(jobPath, modelJobId, pid)` → INSERT dans `schedulers`, retourne `schedulerId`
2. `UPDATE model_job SET scheduler_id = @schedulerId WHERE id = @modelJobId`
3. Démarrer `HeartbeatService` en tâche de fond (`CancellationTokenSource`)
4. Lire et désérialiser `jobs.json` → `JobsFile`
5. `DependencyEngine.RunAsync(jobsFile, schedulerId, modelJobId)`
6. Fin (succès ou exception) :
   - `UPDATE schedulers SET status = 'dead' WHERE id = @schedulerId`
   - `UPDATE model_job SET scheduler_id = NULL WHERE id = @modelJobId`
7. Annuler le `CancellationToken` du HeartbeatService et attendre son arrêt propre

---

### `DataJobNode`

```csharp
public class DataJobNode
{
    public long Id { get; set; }
    public List<long> ParentIds { get; set; } = [];

    // État géré en mémoire uniquement — non présent dans le JSON
    [JsonIgnore] public string State { get; set; } = RunStates.Queued;
}
```

---

### `DependencyEngine`

**Validation au démarrage :** détecter les cycles (algorithme de Kahn). Si cycle détecté → passer tous les `DataJob` à `Failed` en DB + logger l'erreur → terminer.

**Algorithme d'exécution :**

```
Charger tous les DataJobNode depuis jobsFile en mémoire

Tant qu'il reste des nodes avec State ∉ { Finished, Failed, Canceled } :

    Identifier les nodes "prêts" :
        State == Queued
        ET (ParentIds vide OU tous les ParentIds ont State == Finished en mémoire)

    Si aucun prêt ET des nodes non terminés existent :
        → Impossible sans cycle — logger WARNING, attendre 1s

    Pour chaque node prêt, dans la limite de MaxParallelSubJobs (SemaphoreSlim) :
        → State = Running en mémoire
        → UPDATE data_job SET state='Running', start_date_time=NOW(), change_date_time=NOW()
        → Lancer SubJobExecutor.ExecuteAsync(node) comme Task

    Attendre Task.WhenAny sur les tâches en cours

    Succès :
        → State = Finished en mémoire
        → UPDATE data_job SET state='Finished', progress=100, change_date_time=NOW()

    Échec :
        → State = Failed en mémoire
        → UPDATE data_job SET state='Failed', change_date_time=NOW()
        → Propager Failed récursivement à tous les descendants
        → Les branches indépendantes continuent
```

---

### `SubJobExecutor`

```
POST {InternalApiBaseUrl}/datajobs/{node.Id}/execute
Body : { "id": 450 }
Succès si HTTP 2xx
Timeout : SubJobHttpTimeoutSeconds
```

| Cas | State | Persisté en DB |
|---|---|---|
| HTTP 2xx | `Finished` | `state='Finished', progress=100` |
| HTTP 4xx/5xx | `Failed` | `state='Failed'` + code + body |
| Timeout | `Failed` | `"HTTP timeout after {n}s"` |
| Exception réseau | `Failed` | message exception |

---

### `HeartbeatService`

```csharp
while (!cancellationToken.IsCancellationRequested)
{
    await _schedulerRepository.UpdateHeartbeatAsync(schedulerId);
    await Task.Delay(TimeSpan.FromSeconds(intervalSeconds), cancellationToken);
}
```

---

## Dépendances NuGet

### Styx.JobApi

```xml
<PackageReference Include="Npgsql" Version="8.*" />
<PackageReference Include="Dapper" Version="2.*" />
<PackageReference Include="Microsoft.AspNetCore.OpenApi" Version="8.*" />
<PackageReference Include="Swashbuckle.AspNetCore" Version="6.*" />
```

### Styx.SchedulerProcess

```xml
<PackageReference Include="Npgsql" Version="8.*" />
<PackageReference Include="Dapper" Version="2.*" />
<PackageReference Include="Microsoft.Extensions.Hosting" Version="8.*" />
<PackageReference Include="Microsoft.Extensions.Configuration.Json" Version="8.*" />
```

---

## Flux complet — exemple

```
Client → POST /jobs { "model_job_id": 123 }

Styx.JobApi :
  → Charge ModelJob 123 + DataJobs (450..455) + data_job_parent
  → Crée /shares/styx/jobs/123_20240315T093000/jobs.json
  → 2 schedulers actifs < 5 max → slot disponible
  → SELECT model_job FOR UPDATE SKIP LOCKED → verrou OK
  → Spawn : Styx.SchedulerProcess.exe --path ... --model-job-id 123
  → UPDATE model_job SET scheduler_id = 7
  → 202 Accepted

Styx.SchedulerProcess :
  → INSERT schedulers → id = 7
  → UPDATE model_job SET scheduler_id = 7
  → HeartbeatService démarre (toutes les 10s)
  → Désérialise jobs.json → 6 DataJobNode en mémoire

DependencyEngine :
  Tour 1 — prêts : 450, 453 (parent_ids vides)
    → state = Running en mémoire + DB
    → POST /datajobs/450/execute  |  POST /datajobs/453/execute  (en parallèle)

  Tour 2 — 450 terminé → prêts : 451, 452
    → data_job 450 → Finished
    → POST /datajobs/451/execute  |  POST /datajobs/452/execute

  Tour 3 — 453, 451, 452 terminés → prêt : 454
    → data_job 451, 452, 453 → Finished
    → POST /datajobs/454/execute

  Tour 4 — 454 terminé → prêt : 455
    → data_job 454 → Finished
    → POST /datajobs/455/execute

  Tour 5 — 455 terminé
    → data_job 455 → Finished
    → ModelJob state dérivé = 'Finished' (requête SQL existante)

  → UPDATE schedulers SET status = 'dead' WHERE id = 7
  → UPDATE model_job SET scheduler_id = NULL WHERE id = 123
  → Process terminé
```

---

## Points d'extension futurs

- **Retry** : `RetryLimit` existe sur `DataJob`. Le `SubJobExecutor` peut l'utiliser pour retenter avant de passer à `Failed`.
- **Annulation** : détecter `State = Canceling` pendant l'exécution, passer à `Canceled`, propager aux descendants non démarrés.
- **Alertes** : `IAlertService` dans le `WatchdogService` — email SMTP, Teams webhook, etc.
- **Schedulers distants** : remplacer `Process.Start` par un appel HTTP vers un agent distant.
- **Nettoyage du share** : supprimer le dossier `job_path` après exécution (flag `KeepFiles` en config).
