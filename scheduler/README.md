# HpcLite

Remplacement du scheduler Microsoft HPC pour l'infrastructure de calcul. Composé de trois services .NET 8 et d'un dashboard web temps réel.

---

## Architecture

```
Styx.JobApi
    │
    └─ POST /schedule ──► HpcLite.Scheduler  (Windows Service · HEADNODE-01:5100)
                               │
                               └─ POST /run ──► HpcLite.Agent  (Windows Service · COMPUTE-0x:5200)
                                                     │
                                                     └─ Process.Start ──► HpcLite.Runner
                                                                               │
                                                                               └─ heartbeat ──► PostgreSQL
```

| Projet | Rôle | Port |
|---|---|---|
| `HpcLite.Scheduler` | Reçoit les demandes de job, dispatch vers un runner libre, watchdog | 5100 |
| `HpcLite.Agent` | Reçoit l'ordre de lancement, spawn le Runner en tant que process | 5200 |
| `HpcLite.Runner` | Exécute le job, envoie un heartbeat toutes les 10s | — |
| `HpcLite.Domain` | Modèles partagés (`RunStates`, `SettingsFile`) | — |

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
| `POST` | `/schedule` | Soumettre un job |
| `GET` | `/runners/ping` | État de tous les runners |
| `GET` | `/dashboard/status` | Données du dashboard (JSON) |

**POST /schedule — body :**
```json
{
  "model_job_id": 123,
  "settings_path": "\\\\fileserver\\share\\jobs\\123\\settings.json"
}
```

**Réponses :**
- `202 { status: "dispatched" }` — un runner a été assigné
- `202 { status: "queued" }` — tous les runners occupés, job en attente
- `404` — model_job introuvable
- `409` — job déjà en cours
- `502` — Agent injoignable

### HpcLite.Agent (port 5200)

| Méthode | Route | Description |
|---|---|---|
| `POST` | `/run` | Lancer le Runner pour un job |

---

## Base de données

Les migrations sont dans [Database/migrations.sql](Database/migrations.sql).

```sql
-- Tables créées
schedulers  (id, name, host, status, started_at, heartbeat)
runners     (id, name, host, exe_path, status, pid, model_job_id, started_at, heartbeat)

-- Colonne ajoutée
model_job.runner_id  BIGINT REFERENCES runners(id)
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
  "Orchestrator": {
    "AgentPort":               5200,
    "HeartbeatTimeoutSeconds": 60,
    "HeartbeatIntervalSeconds": 10,
    "WatchdogIntervalSeconds": 15
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

## Développement local

**Prérequis :** .NET 8 SDK, PostgreSQL accessible.

Lancer Scheduler + Agent simultanément via **Multiple Startup Projects** dans Visual Studio, ou :

```bash
cd HpcLite.Scheduler && dotnet run &
cd HpcLite.Agent     && dotnet run
```

Le dashboard est alors accessible sur `http://localhost:5100`.

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

Voir [ISSUES.md](ISSUES.md) pour la liste des 16 issues de déploiement et de robustesse, organisées en 5 milestones.
