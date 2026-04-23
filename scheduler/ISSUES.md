# HpcLite — Issues Git

Ordre suggéré : les issues sont numérotées dans l'ordre d'implémentation recommandé.
Les issues marquées **bloquantes** doivent être terminées avant de passer à la suivante.

---

## Milestone 1 — Infrastructure

### #1 · Exécuter les migrations et enregistrer les nœuds en DB `infrastructure` `bloquant`

**Contexte**
Aucune table `schedulers` ni `runners` n'existe encore en production.

**À faire**
- [ ] Exécuter `setup-db.ps1` sur la DB de prod avec les vrais hostnames
- [ ] Vérifier le résultat : `SELECT * FROM schedulers; SELECT * FROM runners;`
- [ ] Vérifier que `model_job.runner_id` a bien été ajouté : `\d model_job`
- [ ] Mettre à jour les `appsettings.json` de chaque projet avec la vraie connection string

**Critère de succès**
```sql
SELECT host, status FROM schedulers; -- 1 ligne, status='inactive'
SELECT name, host, status FROM runners; -- N lignes, status='idle'
```

---

### #2 · Déployer HpcLite.Scheduler sur HEADNODE-01 `infrastructure` `bloquant`

**À faire**
- [ ] Copier la solution sur HEADNODE-01 (ou build depuis CI)
- [ ] Vérifier que .NET 8 Runtime est installé : `dotnet --version`
- [ ] Renseigner `appsettings.json` (connection string, AgentPort)
- [ ] Exécuter `install-scheduler.ps1` en tant qu'admin
- [ ] Vérifier les logs : `C:\apps\HpcLite.Scheduler\logs\`
- [ ] Vérifier en DB : `SELECT status, heartbeat FROM schedulers WHERE host='HEADNODE-01';`

**Critère de succès**
```
sc query "HpcLite Scheduler" → RUNNING
GET http://HEADNODE-01:5100/runners/ping → 200 { "runners": [...] }
```

---

### #3 · Déployer HpcLite.Agent sur chaque compute node `infrastructure` `bloquant`

**À faire (répéter par compute node)**
- [ ] Vérifier que .NET 8 Runtime est installé
- [ ] Exécuter `install-agent.ps1` en tant qu'admin
- [ ] Vérifier les logs : `C:\apps\HpcLite.Agent\logs\`
- [ ] Vérifier que le port 5200 est ouvert (firewall inbound)

**Critère de succès**
```
sc query "HpcLite Agent" → RUNNING  (sur chaque COMPUTE node)
```

---

### #4 · Ouvrir les ports firewall `infrastructure`

**Règles à créer sur chaque machine**

| Machine | Port | Direction | Source |
|---|---|---|---|
| HEADNODE-01 | 5100 TCP | inbound | Styx.JobApi |
| COMPUTE-0x | 5200 TCP | inbound | HEADNODE-01 |

**À faire**
- [ ] Créer les règles Windows Firewall (ou GPO)
- [ ] Tester la connectivité : `Test-NetConnection COMPUTE-01 -Port 5200`

---

## Milestone 2 — Intégration Runner

### #5 · Brancher la logique métier dans HpcLite.Runner `runner` `bloquant`

**Contexte**
`HpcLite.Runner/Program.cs` contient un `// PLACEHOLDER` à l'étape 7.
La logique d'exécution des data_jobs est codée séparément et doit être intégrée ici.

**À faire**
- [ ] Identifier le point d'entrée de la logique existante
- [ ] Passer `context.RunnerId`, `context.ModelJobId`, `context.SettingsPath` à la logique
- [ ] S'assurer que les exceptions remontent correctement (le `finally` garantit le désenregistrement)
- [ ] Vérifier que les `data_job.state` sont bien mis à jour en DB pendant l'exécution

**Critère de succès**
Après un `POST /schedule`, les `data_job` passent par les états attendus et `model_job.runner_id` revient à `NULL` en fin de job.

---

### #6 · Test end-to-end du cycle complet `runner` `test`

**Dépend de** : #2, #3, #5

**À faire**
- [ ] Préparer un `model_job` de test avec ses `data_job` en DB
- [ ] Déposer le `settings.json` correspondant sur le partage réseau
- [ ] Appeler `POST /schedule` depuis Styx.JobApi ou curl
- [ ] Suivre les états : `idle → active → idle` sur le runner, `NULL → X → NULL` sur `runner_id`
- [ ] Vérifier les logs Scheduler, Agent et Runner

---

## Milestone 3 — Intégration Styx.JobApi

### #7 · Remplacer l'appel Microsoft HPC par `POST /schedule` dans Styx.JobApi `integration` `bloquant`

**Contexte**
Styx.JobApi appelle actuellement Microsoft HPC pour soumettre les jobs.
Il doit maintenant appeler `POST http://HEADNODE-01:5100/schedule`.

**À faire**
- [ ] Localiser le code d'appel HPC dans Styx.JobApi
- [ ] Remplacer par `HttpClient.PostAsync("http://{scheduler}/schedule", body)`
- [ ] Body : `{ "model_job_id": X, "settings_path": "..." }`
- [ ] Gérer les réponses : `202 dispatched`, `202 queued`, `404`, `409`, `502`
- [ ] Configurer l'URL du Scheduler dans `appsettings.json` de Styx.JobApi
- [ ] Tester avec un job réel

**Config Styx.JobApi**
```json
{
  "HpcLite": {
    "SchedulerUrl": "http://HEADNODE-01:5100"
  }
}
```

---

### #8 · Mettre à jour FETEAD pour lire les nouvelles tables `integration`

**Contexte**
FETEAD lit la DB pour alimenter la page workflow. Elle doit maintenant lire les tables `schedulers` et `runners` (nouveau schéma) au lieu de l'ancien schéma HPC.

**À faire**
- [ ] Identifier les requêtes FETEAD qui lisaient l'ancien schéma HPC
- [ ] Les adapter au nouveau schéma : `runners` (id, name, host, status, model_job_id, heartbeat)
- [ ] Vérifier que la page workflow affiche correctement les runners idle/active/dead

---

## Milestone 4 — Robustesse

### #9 · Implémenter IAlertService `robustesse`

**Contexte**
`IAlertService.NotifyAsync(runnerId, modelJobId)` est actuellement un no-op.
Il est appelé par le Watchdog quand un Runner crashe.

**À faire**
- [ ] Définir le canal d'alerte (email ? webhook Teams/Slack ? SNMP ?)
- [ ] Implémenter `AlertService` dans `HpcLite.Scheduler/Services/`
- [ ] Enregistrer dans `Program.cs` en remplacement de `NoOpAlertService`
- [ ] Tester : simuler un crash Runner et vérifier la réception de l'alerte

---

### #10 · Implémenter le retry automatique des jobs en attente `robustesse`

**Contexte**
Le Watchdog détecte les `model_job` avec `runner_id IS NULL` et des `data_job` à `Queued`, mais ne peut pas les redispatchez faute de `settings_path` (non stocké côté Scheduler).

**Option A** — stocker le `settings_path` sur `model_job`
```sql
ALTER TABLE model_job ADD COLUMN IF NOT EXISTS settings_path TEXT;
```
Le Scheduler le renseigne à chaque `POST /schedule`, le Watchdog peut alors relancer.

**Option B** — Styx.JobApi re-soumet via `POST /schedule` après un délai.

**À faire**
- [ ] Choisir l'option
- [ ] Implémenter et tester le retry automatique

---

### #11 · Sécuriser les endpoints HTTP `sécurité`

**Contexte**
Actuellement, `POST /schedule` et `POST /run` sont ouverts sans authentification.

**À faire**
- [ ] Évaluer le besoin : réseau interne fermé ou exposition externe ?
- [ ] Si besoin : ajouter une clé API dans les headers (`X-Api-Key`) ou mTLS
- [ ] Protéger au minimum `POST /run` sur l'Agent (seul le Scheduler doit l'appeler)

---

### #12 · Tester le comportement multi-Scheduler `robustesse`

**Contexte**
Plusieurs instances du Scheduler peuvent tourner simultanément. Le `SELECT FOR UPDATE SKIP LOCKED` protège contre les doubles dispatches, mais cela n'a pas encore été testé.

**À faire**
- [ ] Installer un second Scheduler sur HEADNODE-02
- [ ] Soumettre des jobs simultanément sur les deux Schedulers
- [ ] Vérifier qu'aucun job n'est dispatché deux fois
- [ ] Vérifier que les heartbeats `schedulers` sont bien maintenus par chaque instance

---

### #13 · Tester le Watchdog en conditions réelles `robustesse` `test`

**À faire**
- [ ] Lancer un job, puis tuer le process Runner (`taskkill /PID X /F`)
- [ ] Attendre `HeartbeatTimeoutSeconds` (60s) + `WatchdogIntervalSeconds` (15s)
- [ ] Vérifier : runner `idle`, data_jobs `Failed`, `model_job.runner_id = NULL`
- [ ] Vérifier que l'alerte (#9) est bien reçue
- [ ] Vérifier que le runner est disponible pour un nouveau job

---

## Milestone 5 — Opérationnel

### #14 · Centraliser les logs `ops`

**Contexte**
Les logs sont actuellement en fichier local sur chaque machine. En production, il faut pouvoir les consulter depuis un seul endroit.

**Options**
- Partage réseau commun pour les logs
- Envoi vers Elasticsearch / Loki / Seq (via NLog target)
- Copie via Filebeat / Promtail

**À faire**
- [ ] Choisir la solution de centralisation
- [ ] Configurer le target NLog approprié dans les 3 `nlog.config`
- [ ] Vérifier la réception des logs

---

### #15 · Ajouter un endpoint `/health` `ops`

**Contexte**
Permettre à un monitoring externe (Zabbix, Prometheus, Uptime Kuma...) de vérifier que le Scheduler et l'Agent sont vivants.

**À faire**
- [ ] Ajouter `app.MapHealthChecks("/health")` dans les deux `Program.cs`
- [ ] Ajouter `builder.Services.AddHealthChecks()` avec une vérification DB pour le Scheduler
- [ ] Configurer le monitoring externe sur `GET /health`

---

### #16 · Procédure de rollback `ops`

**À faire**
- [ ] Documenter la procédure en cas de bug bloquant post-déploiement
- [ ] Garder les anciens binaires HPC disponibles pendant la transition
- [ ] Définir les critères de rollback (ex : plus de X jobs Failed en moins de Y minutes)

---

## Récapitulatif

| # | Titre | Labels | Dépend de |
|---|---|---|---|
| 1 | Migrations + enregistrement nœuds DB | infra | — |
| 2 | Déployer Scheduler sur HEADNODE-01 | infra | #1 |
| 3 | Déployer Agent sur compute nodes | infra | #1 |
| 4 | Ouvrir les ports firewall | infra | — |
| 5 | Brancher logique métier dans Runner | runner | #1 |
| 6 | Test end-to-end cycle complet | runner, test | #2, #3, #5 |
| 7 | Remplacer appel HPC dans Styx.JobApi | integration | #2 |
| 8 | Mettre à jour FETEAD | integration | #1 |
| 9 | Implémenter IAlertService | robustesse | #2 |
| 10 | Retry automatique jobs en attente | robustesse | #2 |
| 11 | Sécuriser les endpoints HTTP | sécurité | #2, #3 |
| 12 | Tester multi-Scheduler | robustesse, test | #2 |
| 13 | Tester Watchdog en conditions réelles | robustesse, test | #6 |
| 14 | Centraliser les logs | ops | #2, #3 |
| 15 | Endpoint /health | ops | #2, #3 |
| 16 | Procédure de rollback | ops | #7 |
