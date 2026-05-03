# HpcLite

Remplacement du scheduler Microsoft HPC pour l'infrastructure de calcul. Composé de quatre services .NET 8 et d'un dashboard web temps réel.

---

## Architecture

```
Styx.JobApi
    │
    └─ (NOTIFY hpclite_job_ready) ──► HpcLite.Scheduler  (Windows Service · HEADNODE-01:5100)
                                            │
                                            ├─ job_command_type = 0 (Light)
                                            │       └─ POST /taskflow/tasks ──► TaskFlow.Server
                                            │                                        │
                                            │                                        └─ TaskFlow.Runner (workers pool)
                                            │                                                │
                                            │                                        (NOTIFY taskflow_events)
                                            │                                                │
                                            │                                   HpcLite.Scheduler (TaskFlowCompletionListener)
                                            │                                        └─ UPDATE data_task / data_job
                                            │
                                            └─ job_command_type = 1 (Grid)
                                                    └─ POST /run ──► HpcLite.Agent  (Windows Service · COMPUTE-0x:5200)
                                                                           │
                                                                           └─ Process.Start ──► HpcLite.Runner
                                                                                                     │
                                                                                                     └─ heartbeat ──► PostgreSQL
```

| Projet | Rôle | Port |
|---|---|---|
| `HpcLite.Scheduler` | Observe la DB, route les jobs vers TaskFlow (Light) ou Runner (Grid), watchdog | 5100 |
| `HpcLite.Agent` | Reçoit l'ordre de lancement Grid, spawn le Runner en tant que process | 5200 |
| `HpcLite.Runner` | Exécute les jobs Grid, envoie un heartbeat toutes les 10 s | — |
| `HpcLite.Domain` | Modèles partagés (`RunStates`, `SettingsFile`) | — |

---

## Routage Light vs Grid

Chaque `data_job` porte une colonne `job_command_type` positionnée par l'API à la création :

| Valeur | Type | Exécution |
|---|---|---|
| `0` | **Light** | `LightJobDispatchService` → POST chaque `data_task` vers `TaskFlow.Server` |
| `1` | **Grid** | `RunnerDispatchService` → POST `/run` vers `HpcLite.Agent` → `HpcLite.Runner` |

Un même `model_job` peut contenir un mix de `data_job` de type 0 et de type 1. Chaque type est dispatché indépendamment par son service dédié. Les deux services filtrent explicitement sur `job_command_type` dans leur requête SQL — ils ne se marchent jamais dessus.

### Condition de dispatchabilité (commune aux deux types)

Un `data_job` en état `Queued` est éligible au dispatch seulement si **tous ses parents sont `Finished`** (ou s'il n'a pas de parents). La dépendance est déclarée dans la table de jointure `data_job_parent (job_id, parent_job_id)`.

```sql
AND NOT EXISTS (
    SELECT 1 FROM data_job_parent djp
    JOIN data_job p ON p.id = djp.parent_job_id
    WHERE djp.job_id = dj.id
      AND p.state != 'Finished'
)
```

---

## Cycle de vie d'un job Light (TaskFlow)

```
1. API crée data_job (job_command_type=0, state=Queued) + data_tasks
2. Trigger PostgreSQL → NOTIFY hpclite_job_ready
3. JobListenerService reçoit la notification
4. LightJobDispatchService.TryDispatchAllPendingAsync()
      └─ SELECT data_jobs Queued, type=0, parents Finished  [FOR UPDATE SKIP LOCKED]
      └─ UPDATE data_job SET state='Running'
      └─ POST /taskflow/tasks  pour chaque data_task
5. TaskFlow.Runner exécute les tâches
6. Trigger PostgreSQL → NOTIFY taskflow_events  {taskId, state}
7. TaskFlowCompletionListener reçoit la notification
      └─ Résout external_id → data_task
      └─ UPDATE data_task.task_state
      └─ Si tous les tasks terminaux → UPDATE data_job SET state='Finished'|'Failed'
      └─ Si Finished → LightJobDispatchService (déblocage des dépendants)
```

## Cycle de vie d'un job Grid (HpcLite.Runner)

```
1. API crée data_job (job_command_type=1, state=Queued)
2. Trigger PostgreSQL → NOTIFY hpclite_job_ready
3. JobListenerService reçoit la notification
4. RunnerDispatchService.TryDispatchAllPendingAsync()
      └─ SELECT model_job avec data_job Queued, type=1, parents Finished  [FOR UPDATE SKIP LOCKED]
      └─ SELECT runner idle  [FOR UPDATE SKIP LOCKED]
      └─ UPDATE runners SET status='active'  /  UPDATE model_job SET runner_id=...
      └─ POST /run → HpcLite.Agent → Process.Start HpcLite.Runner --runner-id ... --path settings.json
5. HpcLite.Runner exécute le job, heartbeat toutes les 10 s
6. WatchdogService détecte les runners en timeout → marque Failed + libère le runner
```

---

## Dashboard

Le Scheduler expose un dashboard de monitoring temps réel accessible directement sur son port HTTP.

**URL :** `http://HEADNODE-01:5100`

Le dashboard affiche :
- **Stat cards** : runners idle / actifs / morts / jobs en queue
- **Schedulers** : état et heartbeat de chaque instance Scheduler en DB
- **Runners** : état (idle / active / dead), job en cours, dernier heartbeat
- **File d'attente** : model_jobs en attente d'un runner disponible

Rafraîchissement automatique toutes les **5 secondes** via `GET /dashboard/status`.

---

## Endpoints

### HpcLite.Scheduler (port 5100)

| Méthode | Route | Description |
|---|---|---|
| `GET` | `/` | Dashboard HTML |
| `POST` | `/schedule` | Déclencher manuellement un dispatch (test) |
| `GET` | `/runners/ping` | État de tous les runners |
| `GET` | `/dashboard/status` | Données du dashboard (JSON) |

### HpcLite.Agent (port 5200)

| Méthode | Route | Description |
|---|---|---|
| `POST` | `/run` | Lancer le Runner Grid pour un job |

**Body POST /run :**
```json
{
  "runner_id":     42,
  "exe_path":      "C:\\apps\\HpcLite.Runner\\HpcLite.Runner.exe",
  "settings_path": "\\\\fileserver\\share\\jobs\\123\\settings.json"
}
```

---

## Base de données

Les migrations du Scheduler sont dans [Database/migrations.sql](Database/migrations.sql).

### Schéma `scheduler` (tables d'infrastructure)

```sql
scheduler.schedulers  (id, name, host, status, started_at, heartbeat)
scheduler.runners     (id, name, host, exe_path, status, pid, model_job_id, started_at, heartbeat)
```

### Schéma `public` (tables métier, partagées avec l'API)

```sql
model_job        (id, name, runner_id, template_folder, ...)
data_job         (id, parent_model_id, job_command_type, state, progress, ...)
data_job_parent  (job_id, parent_job_id)   -- graphe de dépendances
data_task        (id, data_job_id, task_index, external_id, task_state,
                  command_exe, command_args, ...)
```

### Schéma `taskflow` (tables du runner TaskFlow)

```sql
taskflow.task        (id, external_id, state, command_type, exe_name, args, ...)
taskflow.task_state  (id, task_id, name, server_id, reason, created_at)
taskflow.server      (id, friendly_name, last_heartbeat_at)
```

Le lien entre les deux mondes : `taskflow.task.external_id` = `data_task.external_id`.

---

## Configuration

### appsettings.json — Scheduler

```json
{
  "ConnectionStrings": {
    "Postgres": "Host=db-server;Database=hpclite;Username=postgres;Password=secret"
  },
  "Kestrel": {
    "Endpoints": { "Http": { "Url": "http://0.0.0.0:5100" } }
  },
  "TaskFlow": {
    "BaseUrl": "http://taskflow-server:5300"
  },
  "Orchestrator": {
    "AgentPort":                5200,
    "HeartbeatTimeoutSeconds":  60,
    "HeartbeatIntervalSeconds": 10,
    "WatchdogIntervalSeconds":  15,
    "PollIntervalSeconds":      10
  }
}
```

### appsettings.json — Agent

```json
{
  "Kestrel": {
    "Endpoints": { "Http": { "Url": "http://0.0.0.0:5200" } }
  }
}
```

---

## Déploiement

Voir [DEPLOYMENT.md](DEPLOYMENT.md) pour les commandes complètes.

### Ordre d'exécution — premier déploiement

```
1. scripts/setup-db.ps1          (migrations + enregistrement des nœuds)
2. scripts/install-scheduler.ps1 (sur HEADNODE-01)
3. scripts/install-agent.ps1     (sur chaque COMPUTE node)
4. scripts/verify.ps1            (smoke tests)
```

### Exemple minimal

```powershell
# 1. DB
.\scripts\setup-db.ps1 `
    -PgPassword    "secret" `
    -SchedulerHost "HEADNODE-01" `
    -Runners @(
        @{ Name="Runner-01"; Host="COMPUTE-01"; ExePath="C:\apps\HpcLite.Runner\HpcLite.Runner.exe" },
        @{ Name="Runner-02"; Host="COMPUTE-02"; ExePath="C:\apps\HpcLite.Runner\HpcLite.Runner.exe" }
    )

# 2. Scheduler (sur HEADNODE-01)
.\scripts\install-scheduler.ps1 -PgPassword "secret"

# 3. Agent (sur chaque COMPUTE node)
.\scripts\install-agent.ps1

# 4. Vérification
.\scripts\verify.ps1 -SchedulerHost "HEADNODE-01" -AgentHost "COMPUTE-01"
```

---

## Développement local

**Prérequis :** .NET 8 SDK, PostgreSQL accessible, TaskFlow.Server démarré.

```bash
cd HpcLite.Scheduler && dotnet run &
cd HpcLite.Agent     && dotnet run
```

Le dashboard est accessible sur `http://localhost:5100`.

---

## Logs

| Fichier | Machine |
|---|---|
| `C:\apps\HpcLite.Scheduler\logs\scheduler-YYYY-MM-DD.log` | HEADNODE-01 |
| `C:\apps\HpcLite.Agent\logs\agent-YYYY-MM-DD.log` | chaque COMPUTE node |
| `C:\apps\HpcLite.Runner\logs\runner-YYYY-MM-DD.log` | chaque COMPUTE node |

Archives conservées 30 jours. Erreurs critiques aussi dans l'**Event Viewer Windows** → Application.

```powershell
Get-EventLog -LogName Application -Source "HpcLite*" -EntryType Error -Newest 20
```

---

## Issues

Voir [ISSUES.md](ISSUES.md) pour la liste des issues de déploiement et de robustesse.
