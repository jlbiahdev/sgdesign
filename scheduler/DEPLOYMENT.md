# HpcLite — Déploiement et tests

## Scripts disponibles

| Script | Machine | Usage |
|---|---|---|
| `scripts/setup-db.ps1` | n'importe laquelle | Migrations SQL + enregistrement des nœuds en DB |
| `scripts/install-scheduler.ps1` | headnode | Publie et installe HpcLite Scheduler en Windows Service |
| `scripts/install-agent.ps1` | chaque compute node | Publie et installe HpcLite Agent + Runner |
| `scripts/verify.ps1` | n'importe laquelle | Smoke tests post-installation |
| `scripts/uninstall.ps1` | headnode ou compute | Désinstalle les services |

> Tous les scripts d'installation requièrent un shell PowerShell **en tant qu'administrateur**.

---

## Ordre d'exécution — premier déploiement

```
1. setup-db.ps1          (une seule fois, depuis n'importe quelle machine)
2. install-scheduler.ps1 (sur chaque headnode)
3. install-agent.ps1     (sur chaque compute node)
4. verify.ps1            (depuis le headnode ou un poste admin)
```

---

## Prérequis

- .NET 8 Runtime installé sur toutes les machines cibles
- .NET 8 SDK installé sur la machine qui lance les scripts (build)
- PostgreSQL client (`psql`) dans le PATH pour `setup-db.ps1`
- PostgreSQL accessible depuis headnode + compute nodes
- Partage réseau accessible en lecture par les compute nodes (pour `settings.json`)

---

## 1. setup-db.ps1 — Migrations + enregistrement des nœuds

### Cas standard : premier déploiement avec 2 runners

```powershell
.\scripts\setup-db.ps1 `
    -PgHost        "db-server" `
    -PgDatabase    "hpclite" `
    -PgUser        "postgres" `
    -PgPassword    "secret" `
    -SchedulerHost "HEADNODE-01" `
    -Runners @(
        @{ Name="Runner-01"; Host="COMPUTE-01"; ExePath="C:\apps\HpcLite.Runner\HpcLite.Runner.exe" },
        @{ Name="Runner-02"; Host="COMPUTE-02"; ExePath="C:\apps\HpcLite.Runner\HpcLite.Runner.exe" }
    )
```

### Migrations seules (sans nœuds, DB locale)

```powershell
.\scripts\setup-db.ps1 -PgPassword "secret" -SchedulerHost "HEADNODE-01"
```

### Ajouter un runner après coup

```powershell
.\scripts\setup-db.ps1 `
    -PgPassword    "secret" `
    -SchedulerHost "HEADNODE-01" `
    -Runners @(
        @{ Name="Runner-03"; Host="COMPUTE-03"; ExePath="C:\apps\HpcLite.Runner\HpcLite.Runner.exe" }
    )
```

### Corriger le exe_path d'un runner existant

```powershell
.\scripts\setup-db.ps1 `
    -PgPassword    "secret" `
    -SchedulerHost "HEADNODE-01" `
    -Runners @(
        @{ Name="Runner-01"; Host="COMPUTE-01"; ExePath="D:\newpath\HpcLite.Runner\HpcLite.Runner.exe" }
    )
# ON CONFLICT (name) DO UPDATE — met à jour exe_path sans recréer la ligne
```

### psql non dans le PATH

```powershell
.\scripts\setup-db.ps1 `
    -PgPassword "secret" `
    -SchedulerHost "HEADNODE-01" `
    -PsqlPath "C:\Program Files\PostgreSQL\16\bin\psql.exe"
```

---

## 2. install-scheduler.ps1 — Headnode

### Installation standard (chemins par défaut)

```powershell
# Depuis la racine de la solution, sur HEADNODE-01
.\scripts\install-scheduler.ps1 -PgPassword "secret"
```

> Le script publie automatiquement depuis `../HpcLite.Scheduler` et déploie dans `C:\apps\HpcLite.Scheduler`.

### Chemin de déploiement personnalisé

```powershell
.\scripts\install-scheduler.ps1 -DeployPath "D:\services\Scheduler"
```

### Sources sur un partage réseau (build depuis un poste dev)

```powershell
.\scripts\install-scheduler.ps1 `
    -SolutionRoot "\\devbox\share\HpcLite" `
    -DeployPath   "C:\apps\HpcLite.Scheduler"
```

### Mise à jour (service déjà installé)

```powershell
# Même commande — le script détecte le service existant, l'arrête, republié, redémarre
.\scripts\install-scheduler.ps1
```

---

## 3. install-agent.ps1 — Compute node

### Installation standard sur COMPUTE-01

```powershell
# Sur COMPUTE-01
.\scripts\install-agent.ps1
```

### Chemins personnalisés

```powershell
.\scripts\install-agent.ps1 `
    -DeployPath       "D:\services\HpcLite.Agent" `
    -RunnerDeployPath "D:\apps\HpcLite.Runner"
```

### Sources sur un partage réseau

```powershell
.\scripts\install-agent.ps1 `
    -SolutionRoot     "\\devbox\share\HpcLite" `
    -DeployPath       "C:\apps\HpcLite.Agent" `
    -RunnerDeployPath "C:\apps\HpcLite.Runner"
```

### Mise à jour (service déjà installé)

```powershell
# Même commande — arrête, republié, redémarre
.\scripts\install-agent.ps1
```

> Après une mise à jour du `RunnerDeployPath`, vérifier que `runners.exe_path` en DB est toujours valide :
> ```sql
> SELECT name, exe_path FROM runners;
> ```

---

## 4. verify.ps1 — Smoke tests

### Vérifier le Scheduler local

```powershell
.\scripts\verify.ps1
```

### Vérifier Scheduler + Agent distants

```powershell
.\scripts\verify.ps1 -SchedulerHost "HEADNODE-01" -AgentHost "COMPUTE-01"
```

### Vérifier Scheduler distant uniquement

```powershell
.\scripts\verify.ps1 -SchedulerHost "HEADNODE-01"
```

### Vérifier avec ports non standard

```powershell
.\scripts\verify.ps1 `
    -SchedulerHost "HEADNODE-01" -SchedulerPort 6100 `
    -AgentHost     "COMPUTE-01"  -AgentPort     6200
```

---

## 5. uninstall.ps1

### Désinstaller tout (services uniquement)

```powershell
.\scripts\uninstall.ps1
```

### Désinstaller tout + supprimer les fichiers déployés

```powershell
.\scripts\uninstall.ps1 -RemoveFiles
```

### Désinstaller le Scheduler seulement

```powershell
.\scripts\uninstall.ps1 -Target scheduler
```

### Désinstaller l'Agent seulement (+ fichiers)

```powershell
.\scripts\uninstall.ps1 -Target agent -RemoveFiles
```

### Chemins de déploiement non standard

```powershell
.\scripts\uninstall.ps1 `
    -RemoveFiles `
    -SchedulerPath "D:\services\HpcLite.Scheduler" `
    -AgentPath     "D:\services\HpcLite.Agent" `
    -RunnerPath    "D:\apps\HpcLite.Runner"
```

---

## 6. Tests fonctionnels manuels

### Ping des runners

```powershell
Invoke-RestMethod -Uri "http://HEADNODE-01:5100/runners/ping" -Method GET
```

### Soumettre un job

```powershell
$body = @{
    model_job_id  = 123
    settings_path = "\\fileserver\share\jobs\123\settings.json"
} | ConvertTo-Json

Invoke-RestMethod `
    -Uri         "http://HEADNODE-01:5100/schedule" `
    -Method      POST `
    -Body        $body `
    -ContentType "application/json"
```

### Vérifier l'état en DB après dispatch

```sql
SELECT name, status, pid, model_job_id FROM runners;
SELECT id, runner_id FROM model_job WHERE id = 123;
```

### Simuler un crash Runner (test Watchdog)

```sql
UPDATE runners
SET heartbeat = NOW() - INTERVAL '120 seconds'
WHERE name = 'Runner-01';
-- Attendre 15s (WatchdogIntervalSeconds), puis :
SELECT name, status, pid FROM runners WHERE name = 'Runner-01'; -- doit être idle
SELECT state FROM data_job WHERE parent_model_id = 123;          -- doit être Failed
```

---

## 7. Cas d'erreur à tester

| Scénario | Commande | Réponse attendue |
|---|---|---|
| `model_job` inexistant | `POST /schedule { model_job_id: 9999, ... }` | `404 Not Found` |
| Job déjà en cours | `POST /schedule` deux fois de suite | `409 Conflict` |
| Tous les runners occupés | Soumettre N+1 jobs simultanément | `202 { status: "queued" }` |
| Agent injoignable | Couper réseau vers COMPUTE-01, puis `POST /schedule` | `502 Bad Gateway` |

---

## 8. Logs NLog

Les logs sont dans `{DeployPath}\logs\` sur chaque machine.

| Fichier | Machine |
|---|---|
| `C:\apps\HpcLite.Scheduler\logs\scheduler-YYYY-MM-DD.log` | HEADNODE-01 |
| `C:\apps\HpcLite.Agent\logs\agent-YYYY-MM-DD.log` | chaque COMPUTE node |
| `C:\apps\HpcLite.Runner\logs\runner-YYYY-MM-DD.log` | chaque COMPUTE node |

Archives conservées 30 jours dans `{DeployPath}\logs\archive\`.

Erreurs critiques (Watchdog, crash Agent) aussi dans l'**Event Viewer Windows** → Application → source `HpcLite Scheduler` / `HpcLite Agent`.

```powershell
# Lire les erreurs récentes depuis l'Event Viewer
Get-EventLog -LogName Application -Source "HpcLite*" -EntryType Error -Newest 20
```
