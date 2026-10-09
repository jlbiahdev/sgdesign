# download_deploy.ps1 — Déploiement Styx

Script PowerShell qui télécharge le package **Styx.Publish** (NuGet) depuis Artifactory et déploie, sur le serveur local, les applications demandées :

| Trigramme | Application | Dossier sur le serveur | Pilotage |
|---|---|---|---|
| `-STP` | Taskflow | `<d>\taskflow` | service Windows `TaskFlow.Runner` |
| `-STX` | API | `<d>\api` | pool IIS |
| `-STJ` | HpcLite | `<d>\HpcLite\{agent, runner, scheduler}` | services `HpcLite.Agent` et `HpcLite.Scheduler` ; Runners lancés par l'Agent |

`<d>` est la racine passée avec `-d`, par exemple `D:\Applications`.

Le script ne fait que des **mises à jour** : chaque application demandée doit déjà être installée (dossier, exécutable, service ou pool IIS).

---

## 1. Prérequis

- Windows Server avec **Windows PowerShell 5.1**.
- Console lancée **en administrateur**.
- Lecteur **D:** : la destination, le journal, le dossier de travail et les sauvegardes y sont obligatoirement.
- `curl.exe` (`C:\Windows\System32\curl.exe`, présent par défaut), sauf avec `-PackageFile`.
- IIS et `appcmd.exe` si `-STX` est demandé.
- Les services Windows et le pool IIS existent et pointent sur les exécutables de `<d>`. Le script le vérifie : un service qui exécute un binaire situé ailleurs est refusé.
- Le fichier `download_deploy.ps1` est enregistré en **UTF-8 avec BOM**. Sans BOM, les accents sont corrompus et le script peut ne pas se lancer (« Attribut inattendu CmdletBinding »).

---

## 2. Variables d'environnement

| Variable | Obligatoire | Rôle |
|---|---|---|
| `ARTIFACTORY_USERNAME` | oui, sauf avec `-PackageFile` | Compte Artifactory (ex. `usr-cd-...`) |
| `ARTIFACTORY_TOKEN` | oui, sauf avec `-PackageFile` | Token Artifactory |
| `STYX_PACKAGE_URL` | oui, sauf avec `-PackageUrl` ou `-PackageFile` | URL https complète du `.nupkg` |

Le script lit chaque variable dans la **session** courante, puis au niveau **Machine**.

**Pour la session courante** (le temps de la console) :

```powershell
$env:ARTIFACTORY_USERNAME = "usr-cd-..."
$env:ARTIFACTORY_TOKEN    = "eyJ2..."
$env:STYX_PACKAGE_URL     = "https://dsp-artifacts.../Styx.Publish.<version>.nupkg"
```

**Au niveau Machine** (permanent ; à faire en administrateur, puis ouvrir une nouvelle console) :

```powershell
[Environment]::SetEnvironmentVariable("ARTIFACTORY_USERNAME", "usr-cd-...", "Machine")
[Environment]::SetEnvironmentVariable("ARTIFACTORY_TOKEN",    "eyJ2...",    "Machine")
[Environment]::SetEnvironmentVariable("STYX_PACKAGE_URL",     "https://.../Styx.Publish.<version>.nupkg", "Machine")
```

**Sécurité**
- Les identifiants ne sont **jamais** écrits dans le script.
- Le token n'est jamais affiché, ni journalisé, ni passé en ligne de commande à `curl.exe` : il est transmis par l'entrée standard.

---

## 3. Paramètres

| Paramètre | Obligatoire | Description |
|---|---|---|
| `-d` (`-DestinationRoot`) | oui | Racine des applications. Chemin complet, sur `D:`, existant. Ex. `D:\Applications` |
| `-STP` | au moins un trigramme | Déploie Taskflow |
| `-STX` | | Déploie l'API (IIS) |
| `-STJ` | | Déploie HpcLite (Agent, Runner, Scheduler) |
| `-PackageUrl <url>` | non | URL du `.nupkg`. Prioritaire sur `STYX_PACKAGE_URL`. Incompatible avec `-PackageFile` |
| `-PackageFile <chemin>` | non | `.nupkg` déjà présent sur le serveur. Aucun téléchargement, aucun identifiant nécessaire. Incompatible avec `-PackageUrl` |
| `-ValidationOnly` | non | **Pré-vol** : toutes les vérifications, le téléchargement, l'extraction et la préparation, puis arrêt **avant** tout arrêt d'application. Rien n'est modifié |
| `-Force` | non | Supprime la confirmation `DEPLOYER`. Pour les exécutions automatisées |
| `-KeepTemporaryFiles` | non | Conserve le dossier de travail `<d>\.deploy\...` pour diagnostic |

PowerShell utilise **un seul tiret** : `-STP -STX -STJ`.

---

## 4. Exemples

```powershell
# Pré-vol complet, sans rien arrêter (recommandé avant chaque déploiement)
.\download_deploy.ps1 -d D:\Applications -STP -STX -STJ -ValidationOnly

# Déploiement complet, URL lue dans STYX_PACKAGE_URL
.\download_deploy.ps1 -d D:\Applications -STP -STX -STJ

# API seule, URL passée en paramètre
.\download_deploy.ps1 -d D:\Applications -STX -PackageUrl "https://.../Styx.Publish.<version>.nupkg"

# HpcLite depuis un package déjà présent sur le serveur
.\download_deploy.ps1 -d D:\Applications -STJ -PackageFile D:\Packages\Styx.Publish.<version>.nupkg

# Exécution automatisée (pipeline, tâche planifiée) : sans confirmation
.\download_deploy.ps1 -d D:\Applications -STP -STX -STJ -Force
```

---

## 5. Déroulement

| Étape | Action | Effet sur les applications |
|---|---|---|
| 1 | Contrôle du serveur : administrateur, lecteur D:, `curl.exe`, IIS | aucun |
| 2 | Création du journal dans `<d>\deployment-logs` | aucun |
| 3 | Validation de la demande et des dossiers de destination | aucun |
| 4 | Récupération du package : téléchargement ou copie, dans `<d>\.deploy\...` | aucun |
| 5 | Extraction du `.nupkg` puis de l'archive applicative, contrôle du contenu | aucun |
| 6 | Préparation (staging) des nouveaux fichiers ; présence des nouveaux exécutables | aucun |
| 7 | Contrôle des services, des processus et du pool IIS ; mémorisation de l'état initial (`state.json`) | aucun |
| — | **`-ValidationOnly` s'arrête ici.** Sinon, confirmation `DEPLOYER` (sauf `-Force`) | — |
| 8 | Arrêt des applications demandées (Runners en cours compris) | **arrêt** |
| 9 | Sauvegarde des dossiers actuels dans `<d>\.rollback\...`, puis installation | fichiers remplacés |
| 10 | Redémarrage des applications **qui tournaient avant** ; contrôle de stabilité | redémarrage |

**Points à connaître**
- **Un composant non demandé n'est jamais touché.**
- **Un service arrêté avant le déploiement reste arrêté.** Le script remet chaque application dans l'état où il l'a trouvée.
- **Les Runners HpcLite en cours sont arrêtés brutalement et ne sont pas relancés** par le script : l'Agent en recrée selon les jobs en base. Prévenir les utilisateurs avant le déploiement.
- **Contrôle de stabilité.** Après chaque démarrage, le script attend `$StartupStabilitySeconds` (10 s), puis vérifie que l'application tourne toujours. Une application qui démarre puis tombe est traitée comme une erreur.
- **Rollback automatique.** En cas d'erreur après l'arrêt des applications, l'ancienne version de chaque composant déjà modifié est restaurée, puis les applications sont redémarrées dans leur état initial.

---

## 6. Structure du package

```
Styx.Publish.<version>.nupkg
└── content/styx_publish.zip          archive applicative
    ├── api\
    ├── taskflow\
    ├── hpclite\{agent, runner, scheduler}\
    └── app\                          ignoré
```

Le script refuse tout autre format, et toute entrée d'archive qui sortirait du dossier d'extraction.

---

## 7. Configuration (en tête du script)

La section `>>> DEBUT CONFIGURATION` / `<<< FIN CONFIGURATION` se règle **une fois** par environnement. Une valeur par ligne.

| Variable | Valeur actuelle | Rôle |
|---|---|---|
| `$RequiredDrive` | `D:\` | Lecteur obligatoire |
| `$StxApplicationPoolName` | nom réel du pool (ex. `styx-api`) | Pool IIS de l'API |
| `$TaskflowExecutableRelativePath` | `Socgen.TaskFlow.Runner.exe` | Exécutable Taskflow |
| `$HpcLiteAgentFolder` / `RunnerFolder` / `SchedulerFolder` | `agent` / `runner` / `scheduler` | Sous-dossiers HpcLite |
| `$HpcLite…ExecutableName` | `Styx.HpcLite.Agent.exe`, `.Runner.exe`, `.Scheduler.exe` | Exécutables HpcLite |
| `$PackageApplicationArchive` | `content\styx_publish.zip` | Archive applicative dans le `.nupkg` |
| `$UseWindowsServices` | `$true` | `$true` en production. `$false` est réservé aux tests |
| `$TaskflowServiceName` | `TaskFlow.Runner` | Service Taskflow |
| `$HpcLiteAgentServiceName` / `SchedulerServiceName` | `HpcLite.Agent` / `HpcLite.Scheduler` | Services HpcLite |
| `$StartupStabilitySeconds` | `10` | Délai de stabilité après démarrage (`0` = désactivé) |
| `$PreservedRelativePathsSTP` / `STX` / `STJ` | `@()` | Fichiers propres au serveur, conservés d'une version à l'autre (ex. `@("appsettings.json")`) |
| `$ProcessTimeoutSeconds` / `ServiceTimeoutSeconds` / `IisTimeoutSeconds` | `30` / `60` / `60` | Délais maximum d'arrêt et de démarrage |

> ⚠️ Tant que `$PreservedRelativePaths…` est vide, **la configuration du package remplace celle du serveur** (`appsettings.json`, `web.config`…). Les fichiers du serveur restent disponibles dans la sauvegarde.

---

## 8. Fichiers produits

| Emplacement | Contenu | Conservation |
|---|---|---|
| `<d>\deployment-logs\deployment-<date>-<id>.log` | Journal complet du déploiement | conservé |
| `<d>\deployment-logs\deployment-<date>-<id>.state.json` | État initial des applications | conservé |
| `<d>\.rollback\<date>-<id>\STP`, `STX`, `STJ` | Anciennes versions sauvegardées | conservé (**à purger manuellement**) |
| `<d>\.deploy\<date>-<id>\` | Dossier de travail (package, extraction, staging) | supprimé en fin d'exécution, sauf `-KeepTemporaryFiles` |

---

## 9. Codes de sortie

| Code | Signification |
|---|---|
| `0` | Déploiement réussi, ou pré-vol (`-ValidationOnly`) réussi |
| `1` | Erreur détectée. Si les applications avaient été arrêtées, le rollback a été exécuté. Consulter le journal |
| `2` | Annulation volontaire : confirmation refusée, ou impossible (console non interactive sans `-Force`) |

Si le journal contient **« ROLLBACK INCOMPLET : intervention manuelle nécessaire »**, procéder à la restauration manuelle (section 10).

---

## 10. Restauration manuelle

Les sauvegardes sont dans `<d>\.rollback\<date>-<id>\` :

| Sauvegarde | À remettre dans |
|---|---|
| `STP` | `<d>\taskflow` |
| `STX` | `<d>\api` |
| `STJ` | `<d>\HpcLite` |

Exemple pour Taskflow :

```powershell
Stop-Service TaskFlow.Runner
Rename-Item D:\Applications\taskflow taskflow.ko
Move-Item D:\Applications\.rollback\<date>-<id>\STP D:\Applications\taskflow
Start-Service TaskFlow.Runner
```

Pour l'API : arrêter le pool IIS (`appcmd stop apppool /apppool.name:<pool>`), puis le redémarrer après restauration. Pour HpcLite : arrêter le Scheduler et l'Agent, puis redémarrer le Scheduler en premier.

---

## 11. Dépannage

| Symptôme | Cause probable | Action |
|---|---|---|
| « Attribut inattendu CmdletBinding », accents corrompus | Fichier sans BOM UTF-8 | Ré-enregistrer en UTF-8 avec BOM |
| « Identifiants refusés » (401) | Compte ou token invalide | Vérifier `ARTIFACTORY_USERNAME` / `ARTIFACTORY_TOKEN` |
| « Destination STX / API introuvable » | `<d>\api` absent | Créer le dossier et le pool IIS, ou retirer `-STX` |
| « Le pool IIS configuré pour l'API est introuvable » | `$StxApplicationPoolName` erroné | Vérifier avec `appcmd list apppool` |
| « n'exécute pas l'exécutable attendu » | Le service pointe hors de `<d>` | Corriger le chemin du service (`sc.exe qc <service>`) |
| « a démarré puis s'est arrêté » | Configuration invalide, port déjà utilisé (5100 Scheduler, 5200 Agent), base inaccessible | Journal de l'application et Observateur d'événements ; vérifier qu'aucune autre instance (ex. environnement de test) n'occupe les ports |
| « cannot be started » (erreur 1053) | Exécutable incapable de tourner en service Windows | Vérifier que l'application utilise `UseWindowsService()` |
| La console semble figée | Mode d'édition rapide (QuickEdit) : un clic a suspendu l'affichage | Appuyer sur Échap ; désactiver QuickEdit dans les propriétés de la console |
| Le déploiement installe une ancienne version | `STYX_PACKAGE_URL` pointe vers une autre version | Vérifier la variable, ou utiliser `-PackageUrl` |
