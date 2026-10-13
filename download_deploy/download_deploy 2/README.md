# Téléchargement et déploiement Styx — scripts de production

Ces scripts **téléchargent** le package Styx depuis Artifactory, l'**extraient**, puis **déploient** l'application du serveur. Aucun outil ni aucune manipulation n'est nécessaire en dehors des scripts.

```
download_deploy/
├── download_deploy.ps1            script principal (toute la logique)
├── deploy-api.ps1                 = .\download_deploy.ps1 -STX                   (serveur API)
├── deploy-api-preflight.ps1       = .\download_deploy.ps1 -STX -ValidationOnly   (contrôle préalable)
├── deploy-taskflow.ps1            = .\download_deploy.ps1 -STP                   (serveur Taskflow)
├── deploy-taskflow-preflight.ps1  = .\download_deploy.ps1 -STP -ValidationOnly   (contrôle préalable)
├── deploy-hpclite.ps1             = .\download_deploy.ps1 -STJ                   (serveur HpcLite)
└── deploy-hpclite-preflight.ps1   = .\download_deploy.ps1 -STJ -ValidationOnly   (contrôle préalable)
```

Chaque application est sur **son propre serveur**. Sur chaque serveur, on lance les scripts qui lui correspondent, **sans paramètre** : d'abord le contrôle préalable (`*-preflight.ps1`), puis le déploiement.

| Script de déploiement | Application | Dossier installé | Pilotage |
|---|---|---|---|
| `deploy-api.ps1` | API | `D:\Applications\api` | pool IIS `styx-api` |
| `deploy-taskflow.ps1` | Taskflow | `D:\Applications\taskflow` | service `TaskFlow.Runner` |
| `deploy-hpclite.ps1` | HpcLite | `D:\Applications\HpcLite\{agent, runner, scheduler}` | services `HpcLite.Agent`, `HpcLite.Scheduler` ; Runners lancés par l'Agent |

Le script fait des **mises à jour** : l'application doit déjà être installée (dossier, exécutable, service ou pool IIS).

---

## 1. Prérequis

- Windows Server, **Windows PowerShell 5.1**, console lancée **en administrateur**.
- Lecteur **D:**.
- `curl.exe` (`C:\Windows\System32\curl.exe`, présent par défaut).
- Accès réseau à Artifactory depuis le serveur.
- IIS et `appcmd.exe` sur le serveur API.
- Les services Windows et le pool IIS existent et pointent sur les exécutables de `D:\Applications`. Le script le vérifie.
- Tous les scripts restent **dans le même dossier**, et sont enregistrés en **UTF-8 avec BOM**.

---

## 2. Variables d'environnement (niveau Machine)

| Variable | Rôle |
|---|---|
| `ARTIFACTORY_USERNAME` | Compte Artifactory (ex. `usr-cd-...`) |
| `ARTIFACTORY_TOKEN` | Token Artifactory |
| `STYX_PACKAGE_URL` | URL https complète du `.nupkg` à déployer. **À mettre à jour à chaque nouvelle version** |

À définir **une fois** par serveur, en administrateur, puis ouvrir une nouvelle console :

```powershell
[Environment]::SetEnvironmentVariable("ARTIFACTORY_USERNAME", "usr-cd-...", "Machine")
[Environment]::SetEnvironmentVariable("ARTIFACTORY_TOKEN",    "eyJ2...",    "Machine")
[Environment]::SetEnvironmentVariable("STYX_PACKAGE_URL",     "https://.../Styx.Publish.<version>.nupkg", "Machine")
```

Pour changer de version :

```powershell
[Environment]::SetEnvironmentVariable("STYX_PACKAGE_URL", "https://.../Styx.Publish.<nouvelle-version>.nupkg", "Machine")
```

**Sécurité**
- Les identifiants ne sont jamais écrits dans les scripts.
- Le token n'est jamais affiché, ni journalisé, ni passé en ligne de commande à `curl.exe`.

---

## 3. Utilisation

Console **administrateur**, depuis le dossier des scripts. **Aucun paramètre.** Deux étapes sur chaque serveur :

**1. Contrôle préalable** : télécharge le package et vérifie tout (identifiants, URL, contenu du package, dossiers, exécutables, services, pool IIS), puis s'arrête **avant** tout arrêt d'application. **Aucune application n'est arrêtée, aucun fichier n'est remplacé** : il peut être lancé à tout moment, par exemple la veille du déploiement.

```powershell
.\deploy-api-preflight.ps1         # serveur API
.\deploy-taskflow-preflight.ps1    # serveur Taskflow
.\deploy-hpclite-preflight.ps1     # serveur HpcLite
```

Il doit se terminer par « MODE VALIDATION : toutes les vérifications sont terminées » (code 0). Sinon, corriger l'erreur affichée (section 9) avant de déployer.

**2. Déploiement**

```powershell
.\deploy-api.ps1         # serveur API
.\deploy-taskflow.ps1    # serveur Taskflow
.\deploy-hpclite.ps1     # serveur HpcLite
```

Les scripts sont **non interactifs** : aucune question n'est posée, ils s'exécutent jusqu'au bout.

### Utilisation avancée (`download_deploy.ps1` directement)

| Paramètre | Description |
|---|---|
| `-STP` / `-STX` / `-STJ` | Application à déployer (au moins un) |
| `-ValidationOnly` | **Contrôle préalable** : téléchargement, extraction et tous les contrôles, puis arrêt **avant** tout arrêt d'application |
| `-PackageUrl <url>` | URL du `.nupkg`, au lieu de `STYX_PACKAGE_URL` |
| `-PackageFile <chemin>` | `.nupkg` déjà présent sur le serveur : aucun téléchargement, aucun identifiant nécessaire |
| `-d <racine>` | Racine des applications. Par défaut `D:\Applications` |
| `-KeepTemporaryFiles` | Conserve le dossier de travail `<d>\.deploy\...` pour diagnostic |

```powershell
.\download_deploy.ps1 -STX -ValidationOnly     # contrôle préalable sur le serveur API
```

---

## 4. Déroulement

| Étape | Action | Effet sur l'application |
|---|---|---|
| 1 | Contrôle du serveur : administrateur, lecteur D:, `curl.exe`, IIS (API) | aucun |
| 2 | Création du journal dans `D:\Applications\deployment-logs` | aucun |
| 3 | Contrôle de l'installation actuelle : dossiers, exécutables | aucun |
| 4 | Lecture des variables d'environnement, téléchargement du package | aucun |
| 5 | Extraction du `.nupkg` puis de `content\styx_publish.zip` ; contrôle du contenu | aucun |
| 6 | Copie des nouveaux fichiers dans le dossier de travail (staging) | aucun |
| 7 | Contrôle des services, des processus et du pool IIS ; mémorisation de l'état initial | aucun |
| — | **Le contrôle préalable (`-ValidationOnly`) s'arrête ici.** | — |
| 8 | Arrêt de l'application (et des Runners en cours pour HpcLite) | **arrêt** |
| 9 | Sauvegarde du dossier actuel dans `D:\Applications\.rollback\...`, puis installation | fichiers remplacés |
| 10 | Redémarrage si l'application tournait avant ; contrôle de stabilité (10 s) | redémarrage |

**Points à connaître**
- **Le package complet est téléchargé** sur chaque serveur (~245 Mo), même si un seul composant est déployé.
- **Une application arrêtée avant le déploiement reste arrêtée.**
- **HpcLite** : l'Agent, le Runner et le Scheduler sont déployés et restaurés **ensemble**. Les Runners en cours sont arrêtés brutalement et ne sont pas relancés par le script : l'Agent en recrée selon les jobs en base. **Prévenir les utilisateurs avant.**
- **Contrôle de stabilité** : 10 s après chaque démarrage, l'application doit toujours tourner, sinon c'est une erreur.
- **Rollback automatique** : en cas d'erreur après l'arrêt, l'ancienne version est restaurée et l'application redémarrée dans son état initial.

---

## 5. Configuration (en tête de `download_deploy.ps1`)

Section `>>> DEBUT CONFIGURATION` / `<<< FIN CONFIGURATION`, à vérifier **une fois** par environnement.

| Variable | Valeur | Rôle |
|---|---|---|
| `$StxApplicationPoolName` | `styx-api` | Pool IIS de l'API |
| `$TaskflowServiceName` | `TaskFlow.Runner` | Service Taskflow |
| `$HpcLiteAgentServiceName` / `$HpcLiteSchedulerServiceName` | `HpcLite.Agent` / `HpcLite.Scheduler` | Services HpcLite |
| `$TaskflowExecutableRelativePath` | `Socgen.TaskFlow.Runner.exe` | Exécutable Taskflow |
| `$HpcLite…ExecutableName` | `Styx.HpcLite.Agent.exe`, `.Runner.exe`, `.Scheduler.exe` | Exécutables HpcLite |
| `$PackageApplicationArchive` | `content\styx_publish.zip` | Archive applicative dans le `.nupkg` |
| `$StartupStabilitySeconds` | `10` | Contrôle de stabilité (`0` = désactivé) |
| `$PreservedRelativePathsSTP` / `STX` / `STJ` | `@()` | Fichiers propres au serveur, conservés d'une version à l'autre (ex. `@("appsettings.json")`) |
| `$ProcessTimeoutSeconds` / `ServiceTimeoutSeconds` / `IisTimeoutSeconds` | `30` / `60` / `60` | Délais maximum d'arrêt et de démarrage |

> ⚠️ Tant que `$PreservedRelativePaths…` est vide, **la configuration livrée dans le package remplace celle du serveur** (`appsettings.json`, `web.config`…). Les fichiers du serveur restent disponibles dans la sauvegarde.

---

## 6. Fichiers produits

| Emplacement | Contenu | Conservation |
|---|---|---|
| `D:\Applications\deployment-logs\deployment-<date>-<id>.log` | Journal complet | conservé |
| `D:\Applications\deployment-logs\deployment-<date>-<id>.state.json` | État initial des applications | conservé |
| `D:\Applications\.rollback\<date>-<id>\STP` \| `STX` \| `STJ` | Ancienne version sauvegardée | conservé (**à purger manuellement**) |
| `D:\Applications\.deploy\<date>-<id>\` | Package téléchargé, extraction, staging | supprimé en fin d'exécution, sauf `-KeepTemporaryFiles` |

---

## 7. Codes de sortie

| Code | Signification |
|---|---|
| `0` | Déploiement, ou contrôle préalable, réussi |
| `1` | Erreur. Si l'application avait été arrêtée, le rollback a été exécuté. Consulter le journal |

Si le journal contient **« ROLLBACK INCOMPLET : intervention manuelle nécessaire »**, appliquer la section 8.

---

## 8. Restauration manuelle

| Sauvegarde | À remettre dans |
|---|---|
| `D:\Applications\.rollback\<date>-<id>\STP` | `D:\Applications\taskflow` |
| `D:\Applications\.rollback\<date>-<id>\STX` | `D:\Applications\api` |
| `D:\Applications\.rollback\<date>-<id>\STJ` | `D:\Applications\HpcLite` |

Exemple pour Taskflow :

```powershell
Stop-Service TaskFlow.Runner
Rename-Item D:\Applications\taskflow taskflow.ko
Move-Item D:\Applications\.rollback\<date>-<id>\STP D:\Applications\taskflow
Start-Service TaskFlow.Runner
```

- **API** : arrêter le pool (`appcmd stop apppool /apppool.name:styx-api`), restaurer, puis le redémarrer.
- **HpcLite** : arrêter l'Agent puis le Scheduler, restaurer, puis redémarrer le Scheduler en premier.

---

## 9. Dépannage

| Symptôme | Cause probable | Action |
|---|---|---|
| « Attribut inattendu CmdletBinding », accents corrompus | Fichier sans BOM UTF-8 | Ré-enregistrer en UTF-8 avec BOM |
| « download_deploy.ps1 est introuvable » | Scripts séparés | Garder tous les scripts dans le même dossier |
| « Le nom d'utilisateur / token Artifactory est absent » | Variable Machine non définie, ou console ouverte avant sa création | Définir la variable (section 2), ouvrir une nouvelle console |
| « L'adresse du package est absente » | `STYX_PACKAGE_URL` non définie | Section 2 |
| « Identifiants refusés » (401) | Compte ou token invalide | Vérifier `ARTIFACTORY_USERNAME` / `ARTIFACTORY_TOKEN` |
| Échec de téléchargement (réseau, proxy, 404) | URL erronée ou accès réseau | Vérifier l'URL et l'accès à Artifactory depuis le serveur |
| Une ancienne version est installée | `STYX_PACKAGE_URL` pointe vers l'ancienne version | Mettre à jour la variable |
| « Destination … introuvable » | Application non installée sous `D:\Applications` | Vérifier l'installation |
| « Le pool IIS configuré pour l'API est introuvable » | Nom de pool différent | Corriger `$StxApplicationPoolName` (`appcmd list apppool`) |
| « n'exécute pas l'exécutable attendu » | Service pointant hors de `D:\Applications` | Vérifier le service (`sc.exe qc <service>`) |
| « a démarré puis s'est arrêté » | Configuration invalide, port déjà utilisé (5100 Scheduler, 5200 Agent), base inaccessible | Journal de l'application, Observateur d'événements |
| « cannot be started » (erreur 1053) | Exécutable incapable de tourner en service | Vérifier la version livrée |
| Console figée | Mode d'édition rapide (QuickEdit) | Appuyer sur Échap ; désactiver QuickEdit dans les propriétés de la console |
