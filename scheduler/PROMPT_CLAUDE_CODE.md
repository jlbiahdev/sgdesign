# Prompt Claude Code — HpcLite (.NET 8)

## Autorisations

Tu as l'autorisation complète pour :
- Créer, modifier et supprimer des fichiers et dossiers
- Exécuter des commandes bash (dotnet new, dotnet add, dotnet build, etc.)
- Installer des packages NuGet
- Créer et structurer des projets .NET
- Exécuter des scripts SQL
- Lire et écrire dans le filesystem

**Ne demande pas de confirmation avant chaque action — exécute directement.** Si tu as besoin de faire un choix technique non spécifié dans ce prompt, fais-le de manière autonome en suivant les conventions .NET 8 et les principes déjà établis dans ce document, et mentionne-le dans un résumé en fin d'exécution.

---

## Contexte général

Cette application se substitue à Microsoft HPC :
- **HpcLite.Scheduler** = headnode HPC → Windows Service .NET 8 avec Kestrel embarqué
- **HpcLite.Agent** = service de déclenchement installé sur chaque machine Runner → Windows Service .NET 8 minimal avec Kestrel embarqué
- **HpcLite.Runner** = compute node HPC → Console App .NET 8

**Schedulers et Runners sont des nœuds fixes**, déclarés à l'avance par un administrateur via des lignes insérées manuellement en DB. Ce ne sont pas des entités créées dynamiquement.

Plusieurs Schedulers peuvent tourner simultanément sur des machines différentes. Chaque machine Runner héberge un Agent qui écoute les demandes de lancement.

**Ce que tu implémentes dans ce prompt :**
1. `HpcLite.Scheduler` — le Windows Service complet
2. `HpcLite.Agent` — le Windows Service de déclenchement (minimal)
3. `HpcLite.Runner` — le squelette minimal assurant le dialogue avec le Scheduler (enregistrement DB, heartbeat, désenregistrement). La logique fonctionnelle d'exécution des jobs est déjà codée séparément et sera intégrée plus tard via un `// PLACEHOLDER`.

**Ce qui est hors scope :**
- La page de monitoring workflow (gérée par FETEAD, une API existante qui lit la DB)
- La logique métier d'exécution des data_jobs dans le Runner

---

## Topologie

```
[Admin] → INSERT schedulers (nom, host de chaque headnode)
[Admin] → INSERT runners    (nom, host, exe_path de chaque compute node)

Styx.JobApi
    └── POST http://<scheduler-host>:5100/schedule
              { "settings_path": "...", "model_job_id": 123 }
                        │
              HpcLite.Scheduler (Windows Service + Kestrel, port 5100)
                        │
                        ├── Cherche un Runner idle en DB
                        ├── SELECT FOR UPDATE SKIP LOCKED sur model_job
                        └── POST http://<runner-host>:5200/run
                              { "runner_id": 7, "settings_path": "..." }
                                        │
                              HpcLite.Agent (Windows Service + Kestrel, port 5200)
                              installé sur chaque machine Runner
                                        │
                                        └── Process.Start(runner.ExePath,
                                              "--runner-id 7 --path ...")

              HpcLite.Runner (Console App)
                        │
                        ├── Lit runners WHERE id=7 → récupère model_job_id depuis settings.json
                        ├── UPDATE runners SET status='active', pid=@pid, heartbeat=NOW()
                        ├── UPDATE model_job SET runner_id = 7
                        ├── [PLACEHOLDER — logique métier existante à brancher ici]
                        ├── Heartbeat périodique → UPDATE runners SET heartbeat=NOW()
                        └── Fin : UPDATE runners SET status='idle'
                                  UPDATE model_job SET runner_id = NULL

              WatchdogService (dans le Scheduler, IHostedService)
                        └── Détecte heartbeats expirés → marque Failed + remet Runner en idle

              FETEAD API (existante — hors scope)
                        └── Lit schedulers + runners + data_job → page workflow
```

---

## Base de données

**PostgreSQL + Dapper** (pas d'EF Core).

### Tables existantes (ne pas recréer, ne pas modifier structurellement)

#### `public.model_job`
Colonne à ajouter :
```sql
ALTER TABLE public.model_job
ADD COLUMN IF NOT EXISTS runner_id BIGINT REFERENCES runners(id);
```

#### `public.data_job`
Colonnes utiles pour le Runner :
- `id BIGSERIAL PRIMARY KEY`
- `parent_model_id BIGINT NOT NULL`
- `name VARCHAR(255)`
- `state VARCHAR(64) NOT NULL`
- `progress INTEGER NOT NULL`
- `start_date_time TIMESTAMP`
- `change_date_time TIMESTAMP`

#### `public.data_job_parent`
```sql
job_id        INTEGER NOT NULL REFERENCES data_job(id) ON DELETE CASCADE
parent_job_id INTEGER NOT NULL REFERENCES data_job(id) ON DELETE CASCADE
PRIMARY KEY (job_id, parent_job_id)
```

### Tables à créer

#### `public.schedulers`
Insérée manuellement par un admin. Le Scheduler met à jour sa ligne au démarrage/arrêt.

```sql
CREATE TABLE IF NOT EXISTS public.schedulers (
    id         BIGSERIAL PRIMARY KEY,
    name       TEXT NOT NULL,
    host       TEXT NOT NULL UNIQUE,
    status     TEXT NOT NULL DEFAULT 'inactive', -- inactive | active | dead
    started_at TIMESTAMPTZ,
    heartbeat  TIMESTAMPTZ
);
```

#### `public.runners`
Insérée manuellement par un admin. Cycle de vie géré par le Runner et le Watchdog.

```sql
CREATE TABLE IF NOT EXISTS public.runners (
    id           BIGSERIAL PRIMARY KEY,
    name         TEXT NOT NULL,
    host         TEXT NOT NULL,
    exe_path     TEXT NOT NULL,        -- chemin vers HpcLite.Runner.exe sur la machine Runner
    status       TEXT NOT NULL DEFAULT 'idle', -- idle | active | dead
    pid          INTEGER,
    model_job_id BIGINT REFERENCES model_job(id),
    started_at   TIMESTAMPTZ,
    heartbeat    TIMESTAMPTZ
);
```

**Cycle de vie du status Runner :**

| Status | Signification |
|---|---|
| `idle` | Disponible, prêt à recevoir un job |
| `active` | En cours d'exécution, heartbeat attendu |
| `dead` | Crashé (détecté par le Watchdog) |

Le Watchdog remet à `idle` après traitement du crash. Le Runner repasse à `idle` à la fin normale.

### États (`RunStates`)

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

**State dérivé de `model_job`** (requête SQL existante — ne pas modifier) :

| Condition sur les `data_job` enfants | State dérivé |
|---|---|
| Au moins un `Failed` | `Failed` |
| Au moins un `Canceling` ou `Canceled` | `Canceled` |
| Au moins un `Running` + d'autres en cours | `Running` |
| Tous `Finishing` ou `Finished` | `Finished` |
| Sinon | `Queued` |

---

## Format du `settings.json`

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

---

## Structure de la solution

```
/HpcLite.sln
├── /HpcLite.Domain                        # Bibliothèque partagée
│   └── Models/
│       ├── RunStates.cs
│       └── SettingsFile.cs                # { long ModelJobId, List<DataJobEntry> DataJobs }
│                                          # DataJobEntry { long Id, List<long> ParentIds }
│
├── /HpcLite.Scheduler                     # Worker Service .NET 8 (Windows Service + Kestrel :5100)
│   ├── Controllers/
│   │   └── SchedulerController.cs         # POST /schedule, GET /runners/ping
│   ├── Services/
│   │   ├── SchedulerRegistrationService.cs # Enregistrement/heartbeat en DB au démarrage
│   │   ├── RunnerDispatchService.cs        # Sélection Runner idle + appel Agent
│   │   └── WatchdogService.cs             # IHostedService — détection crash runners
│   ├── Repositories/
│   │   ├── SchedulerRepository.cs
│   │   ├── RunnerRepository.cs
│   │   └── ModelJobRepository.cs
│   ├── appsettings.json
│   └── Program.cs
│
├── /HpcLite.Agent                         # Worker Service .NET 8 (Windows Service + Kestrel :5200)
│   ├── Controllers/
│   │   └── AgentController.cs             # POST /run
│   ├── appsettings.json
│   └── Program.cs
│
├── /HpcLite.Runner                        # Console App .NET 8
│   ├── Services/
│   │   ├── RunnerRegistrationService.cs   # UPDATE runners + UPDATE model_job.runner_id
│   │   └── HeartbeatService.cs            # UPDATE runners SET heartbeat périodiquement
│   ├── Repositories/
│   │   ├── RunnerRepository.cs
│   │   └── ModelJobRepository.cs
│   ├── Models/
│   │   └── RunnerContext.cs               # { long RunnerId, long ModelJobId, string SettingsPath }
│   ├── appsettings.json
│   └── Program.cs
│
└── /Database/
    └── migrations.sql                     # CREATE schedulers, CREATE runners, ALTER model_job
```

---

## HpcLite.Scheduler — détail des composants

### `Program.cs`

```csharp
var builder = Host.CreateApplicationBuilder(args);
builder.Services.AddWindowsService(options => options.ServiceName = "HpcLite Scheduler");
builder.Services.AddHostedService<SchedulerRegistrationService>();
builder.Services.AddHostedService<WatchdogService>();
builder.WebHost.ConfigureKestrel(/* url depuis appsettings */);
builder.Services.AddControllers();
```

### `SchedulerRegistrationService` (IHostedService)

```
StartAsync :
  → host = Dns.GetHostName()
  → UPDATE schedulers SET status='active', started_at=NOW(), heartbeat=NOW() WHERE host=@host
  → Si 0 lignes → logger ERROR "Ce Scheduler n'est pas enregistré en DB. Contacter l'admin."
  → Boucle heartbeat toutes les HeartbeatIntervalSeconds :
      UPDATE schedulers SET heartbeat=NOW() WHERE host=@host

StopAsync :
  → UPDATE schedulers SET status='inactive' WHERE host=@host
```

### `POST /schedule`

**Body :**
```json
{
  "settings_path": "\\\\fileserver\\share\\jobs\\123\\settings.json",
  "model_job_id": 123
}
```

**Comportement :**
1. Vérifier que `model_job` existe (`404` si absent).
2. Vérifier que `runner_id IS NULL` (`409` si déjà en cours).
3. Appeler `RunnerDispatchService.TryDispatchAsync(modelJobId, settingsPath)`.
4. Retourner `202 Accepted` : `{ "model_job_id": 123, "status": "dispatched" | "queued" }`.

Le Scheduler **ne lit pas** `settings.json` — il transmet le path tel quel à l'Agent.

### `GET /runners/ping`

Retourne l'état de tous les runners en DB :

```json
{
  "runners": [
    {
      "id": 1, "name": "Runner-01", "host": "COMPUTE-01",
      "status": "active", "is_alive": true, "model_job_id": 123
    },
    {
      "id": 2, "name": "Runner-02", "host": "COMPUTE-02",
      "status": "idle", "is_alive": null, "model_job_id": null
    }
  ]
}
```

`is_alive` = `null` si `idle`, sinon `heartbeat > NOW() - HeartbeatTimeoutSeconds`.

### `RunnerDispatchService`

**Load balancing : premier Runner `idle`.**

```
Dans une transaction :
  SELECT id, host, exe_path FROM runners
  WHERE status = 'idle'
  ORDER BY id ASC
  LIMIT 1
  FOR UPDATE SKIP LOCKED

  → Si aucun Runner idle : log "No runner available" → retourner "queued"

  → UPDATE runners SET status='active', model_job_id=@modelJobId, started_at=NOW()
    WHERE id = @runnerId

  → UPDATE model_job SET runner_id = @runnerId WHERE id = @modelJobId AND runner_id IS NULL

  → POST http://{runner.host}:{AgentPort}/run
    { "runner_id": @runnerId, "settings_path": @settingsPath }

  → Si l'appel Agent échoue :
      Rollback : UPDATE runners SET status='idle', model_job_id=NULL WHERE id=@runnerId
                 UPDATE model_job SET runner_id=NULL WHERE id=@modelJobId
      Retourner erreur 502
```

### `WatchdogService` (IHostedService)

S'exécute toutes les `WatchdogIntervalSeconds` secondes.

1. Détecter les Runners expirés :
```sql
SELECT r.id, r.name, r.pid, r.host, r.model_job_id
FROM runners r
WHERE r.status = 'active'
AND r.heartbeat < NOW() - INTERVAL '{HeartbeatTimeoutSeconds} seconds';
```

2. Pour chaque Runner expiré :
   - `UPDATE runners SET status = 'idle', model_job_id = NULL, pid = NULL WHERE id = @id`
   - `UPDATE data_job SET state = 'Failed', change_date_time = NOW() WHERE parent_model_id = @modelJobId AND state NOT IN ('Finished', 'Failed', 'Canceled')`
   - `UPDATE model_job SET runner_id = NULL WHERE id = @modelJobId`
   - Logger `ERROR` : `"[Watchdog] Runner {name} (PID {pid} on {host}) timed out. ModelJob {modelJobId} marked Failed."`
   - Appeler `IAlertService.NotifyAsync(runnerId, modelJobId)` — interface vide, à brancher plus tard

3. Tenter un nouveau dispatch pour les `model_job` dont `runner_id IS NULL` et qui ont des `data_job` à `Queued`.

---

## HpcLite.Agent — détail des composants

Windows Service minimal. Un seul endpoint.

### `POST /run`

**Body :**
```json
{ "runner_id": 7, "settings_path": "\\\\fileserver\\share\\jobs\\123\\settings.json" }
```

**Comportement :**
```csharp
var process = new Process
{
    StartInfo = new ProcessStartInfo
    {
        FileName        = runnerExePath,  // lu depuis appsettings ou depuis runners.exe_path en DB
        Arguments       = $"--runner-id {request.RunnerId} --path \"{request.SettingsPath}\"",
        UseShellExecute = false,
        CreateNoWindow  = true
    }
};
process.Start();
return Accepted();
```

`runnerExePath` est soit lu depuis `appsettings.json` de l'Agent, soit depuis `runners.exe_path` passé par le Scheduler dans le body. **Utiliser `runners.exe_path`** — c'est plus flexible et évite une config supplémentaire sur chaque Agent.

Mettre à jour le body du `POST /run` en conséquence :
```json
{
  "runner_id": 7,
  "exe_path": "C:\\apps\\HpcLite.Runner\\HpcLite.Runner.exe",
  "settings_path": "\\\\fileserver\\share\\jobs\\123\\settings.json"
}
```

### `Program.cs`

```csharp
var builder = Host.CreateApplicationBuilder(args);
builder.Services.AddWindowsService(options => options.ServiceName = "HpcLite Agent");
builder.WebHost.ConfigureKestrel(/* port 5200 depuis appsettings */);
builder.Services.AddControllers();
```

---

## HpcLite.Runner — squelette minimal

Reçoit `--runner-id` et `--path` en arguments.

### `Program.cs` — séquence de démarrage

```csharp
// 1. Parser les arguments
var runnerId    = args.ParseArg<long>("--runner-id");
var settingsPath = args.ParseArg("--path");

// 2. Lire settings.json → extraire model_job_id
var settings   = JsonSerializer.Deserialize<SettingsFile>(File.ReadAllText(settingsPath));
var modelJobId = settings.ModelJobId;

// 3. S'enregistrer en DB
var context = await registrationService.RegisterAsync(runnerId, modelJobId, settingsPath);

// 4. Démarrer le heartbeat
using var cts = new CancellationTokenSource();
var heartbeatTask = heartbeatService.RunAsync(runnerId, cts.Token);

try
{
    // 5. [PLACEHOLDER — logique métier existante à brancher ici]
    // Reçoit : context.RunnerId, context.ModelJobId, context.SettingsPath
    await Task.CompletedTask;
}
finally
{
    // 6. Arrêter le heartbeat
    cts.Cancel();
    await heartbeatTask;

    // 7. Se désenregistrer
    await registrationService.UnregisterAsync(runnerId, modelJobId);
}
```

### `RunnerRegistrationService`

```
RegisterAsync(runnerId, modelJobId, settingsPath) :
  → pid  = Environment.ProcessId
  → UPDATE runners
    SET status='active', pid=@pid, model_job_id=@modelJobId,
        started_at=NOW(), heartbeat=NOW()
    WHERE id = @runnerId
  → Retourner RunnerContext { RunnerId, ModelJobId, SettingsPath }

UnregisterAsync(runnerId, modelJobId) :
  → UPDATE runners
    SET status='idle', pid=NULL, model_job_id=NULL
    WHERE id = @runnerId
  → UPDATE model_job SET runner_id = NULL WHERE id = @modelJobId
```

### `HeartbeatService`

```csharp
public async Task RunAsync(long runnerId, CancellationToken cancellationToken)
{
    while (!cancellationToken.IsCancellationRequested)
    {
        await _runnerRepository.UpdateHeartbeatAsync(runnerId);
        await Task.Delay(TimeSpan.FromSeconds(_intervalSeconds), cancellationToken);
    }
}
```

---

## Configuration

### `HpcLite.Scheduler/appsettings.json`

```json
{
  "ConnectionStrings": {
    "Postgres": "Host=localhost;Database=hpclite;Username=postgres;Password=secret"
  },
  "Kestrel": {
    "Endpoints": {
      "Http": { "Url": "http://0.0.0.0:5100" }
    }
  },
  "Orchestrator": {
    "AgentPort": 5200,
    "HeartbeatTimeoutSeconds": 60,
    "HeartbeatIntervalSeconds": 10,
    "WatchdogIntervalSeconds": 15
  }
}
```

### `HpcLite.Agent/appsettings.json`

```json
{
  "Kestrel": {
    "Endpoints": {
      "Http": { "Url": "http://0.0.0.0:5200" }
    }
  }
}
```

### `HpcLite.Runner/appsettings.json`

```json
{
  "ConnectionStrings": {
    "Postgres": "Host=localhost;Database=hpclite;Username=postgres;Password=secret"
  },
  "Runner": {
    "HeartbeatIntervalSeconds": 10
  }
}
```

---

## Dépendances NuGet

### HpcLite.Scheduler

```xml
<PackageReference Include="Microsoft.Extensions.Hosting.WindowsServices" Version="8.*" />
<PackageReference Include="Microsoft.AspNetCore.App" />
<PackageReference Include="Npgsql" Version="8.*" />
<PackageReference Include="Dapper" Version="2.*" />
```

### HpcLite.Agent

```xml
<PackageReference Include="Microsoft.Extensions.Hosting.WindowsServices" Version="8.*" />
<PackageReference Include="Microsoft.AspNetCore.App" />
```

### HpcLite.Runner

```xml
<PackageReference Include="Npgsql" Version="8.*" />
<PackageReference Include="Dapper" Version="2.*" />
<PackageReference Include="Microsoft.Extensions.Configuration.Json" Version="8.*" />
<PackageReference Include="Microsoft.Extensions.DependencyInjection" Version="8.*" />
```

---

## Contraintes importantes

1. **Ne pas implémenter la logique métier du Runner** — laisser un `// PLACEHOLDER` explicite.
2. **Ne pas modifier** `model_job`, `data_job`, `data_job_parent` au-delà de l'`ALTER TABLE` spécifié.
3. **Dapper uniquement** — pas d'EF Core.
4. **`SELECT FOR UPDATE SKIP LOCKED`** obligatoire dans `RunnerDispatchService`.
5. **Schedulers et Runners sont des nœuds fixes** — jamais créés dynamiquement, toujours mis à jour.
6. Le Scheduler **ne lit pas `settings.json`** — il transmet path + model_job_id reçus de Styx.JobApi.
7. Plusieurs Schedulers peuvent tourner simultanément — la DB est le seul état partagé.
8. L'Agent **n'a pas accès à la DB** — il se contente de spawner le process Runner.

---

## Flux complet — exemple

```
[Admin] → INSERT INTO schedulers (name, host) VALUES ('Scheduler-01', 'HEADNODE-01')
[Admin] → INSERT INTO runners (name, host, exe_path)
          VALUES ('Runner-01', 'COMPUTE-01', 'C:\apps\HpcLite.Runner\HpcLite.Runner.exe'),
                 ('Runner-02', 'COMPUTE-02', 'C:\apps\HpcLite.Runner\HpcLite.Runner.exe')

HpcLite.Scheduler démarre sur HEADNODE-01 :
  → UPDATE schedulers SET status='active', heartbeat=NOW() WHERE host='HEADNODE-01'
  → WatchdogService démarre (toutes les 15s)
  → Kestrel écoute sur :5100

HpcLite.Agent démarre sur COMPUTE-01 et COMPUTE-02 :
  → Kestrel écoute sur :5200 (pas de DB)

Styx.JobApi → POST http://HEADNODE-01:5100/schedule
              { "settings_path": "\\fileserver\share\123\settings.json", "model_job_id": 123 }

HpcLite.Scheduler :
  → model_job 123 OK, runner_id IS NULL
  → SELECT runners WHERE status='idle' FOR UPDATE SKIP LOCKED → Runner-01 (id=1)
  → UPDATE runners SET status='active', model_job_id=123 WHERE id=1
  → UPDATE model_job SET runner_id=1 WHERE id=123
  → POST http://COMPUTE-01:5200/run
    { "runner_id": 1, "exe_path": "C:\apps\...\HpcLite.Runner.exe", "settings_path": "..." }
  → 202 Accepted { "model_job_id": 123, "status": "dispatched" }

HpcLite.Agent sur COMPUTE-01 :
  → Process.Start("HpcLite.Runner.exe --runner-id 1 --path \\fileserver\share\123\settings.json")
  → 202 Accepted

HpcLite.Runner sur COMPUTE-01 :
  → Lit settings.json → model_job_id = 123
  → UPDATE runners SET status='active', pid=4521, started_at=NOW(), heartbeat=NOW() WHERE id=1
  → HeartbeatService démarre (toutes les 10s)
  → [PLACEHOLDER logique métier — exécution des data_jobs]
  → UPDATE runners SET status='idle', pid=NULL, model_job_id=NULL WHERE id=1
  → UPDATE model_job SET runner_id=NULL WHERE id=123
  → Process terminé

WatchdogService (si Runner crashe) :
  → Heartbeat expiré pour runner id=1
  → UPDATE runners SET status='idle', pid=NULL, model_job_id=NULL WHERE id=1
  → UPDATE data_job SET state='Failed' WHERE parent_model_id=123 AND state NOT IN (...)
  → UPDATE model_job SET runner_id=NULL WHERE id=123
  → ERROR "[Watchdog] Runner Runner-01 timed out. ModelJob 123 marked Failed."
```
