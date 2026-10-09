# Déploiement Styx — scripts de production

Ces scripts déploient les applications Styx sur le serveur local, **à partir de fichiers déjà extraits** dans `D:\.deploy`. Le package n'est ni téléchargé ni extrait par ces scripts.

```
deploy/
├── deploy.ps1            script de déploiement (toute la logique)
├── deploy-api.ps1        = .\deploy.ps1 -STX   (serveur API)
├── deploy-taskflow.ps1   = .\deploy.ps1 -STP   (serveur Taskflow)
└── deploy-hpclite.ps1    = .\deploy.ps1 -STJ   (serveur HpcLite)
```

Chaque application est sur **son propre serveur**. Sur chaque serveur, on lance le script qui lui correspond.

| Script | Application | Nouveaux fichiers (source) | Dossier installé | Pilotage |
|---|---|---|---|---|
| `deploy-api.ps1` | API | `D:\.deploy\api` | `<d>\api` | pool IIS |
| `deploy-taskflow.ps1` | Taskflow | `D:\.deploy\taskflow` | `<d>\taskflow` | service `TaskFlow.Runner` |
| `deploy-hpclite.ps1` | HpcLite | `D:\.deploy\hpclite\{agent, runner, scheduler}` | `<d>\HpcLite\{agent, runner, scheduler}` | services `HpcLite.Agent`, `HpcLite.Scheduler` ; Runners lancés par l'Agent |

`<d>` est la racine passée avec `-d`, par exemple `D:\Applications`.

Le script fait des **mises à jour** : l'application doit déjà être installée (dossier, exécutable, service ou pool IIS).

---

## 1. Prérequis

- Windows Server, **Windows PowerShell 5.1**, console lancée **en administrateur**.
- Lecteur **D:**.
- Nouveaux fichiers présents dans `D:\.deploy\<application>` (voir tableau ci-dessus).
- IIS et `appcmd.exe` sur le serveur API.
- Les services Windows et le pool IIS existent et pointent sur les exécutables de `<d>`. Le script le vérifie.
- Les quatre scripts restent **dans le même dossier**, et sont enregistrés en **UTF-8 avec BOM**.

Aucune variable d'environnement n'est nécessaire.

---

## 2. Utilisation

Exemple sur le serveur API :

```powershell
cd <dossier des scripts>

# 1. Pré-vol : tout est vérifié, rien n'est arrêté
.\deploy-api.ps1 -d D:\Applications -ValidationOnly

# 2. Déploiement (le script demande de taper DEPLOYER)
.\deploy-api.ps1 -d D:\Applications
```

Même chose avec `deploy-taskflow.ps1` et `deploy-hpclite.ps1` sur leurs serveurs.

### Paramètres

| Paramètre | Obligatoire | Description |
|---|---|---|
| `-d` | oui | Racine des applications. Chemin complet, sur `D:`, existant. Ex. `D:\Applications` |
| `-SourceRoot <dossier>` | non | Dossier des nouveaux fichiers. Par défaut `D:\.deploy` |
| `-ValidationOnly` | non | **Pré-vol** : contrôles et préparation, puis arrêt **avant** tout arrêt d'application |
| `-Force` | non | Supprime la confirmation `DEPLOYER` (exécution automatisée) |
| `-KeepTemporaryFiles` | non | Conserve le dossier de travail `<d>\.staging\...` pour diagnostic |

`deploy.ps1` accepte les mêmes paramètres, plus `-STP`, `-STX` et `-STJ` pour choisir l'application. Les trois autres scripts ajoutent ce choix automatiquement.

---

## 3. Déroulement

| Étape | Action | Effet sur l'application |
|---|---|---|
| 1 | Contrôle du serveur : administrateur, lecteur D:, IIS (API) | aucun |
| 2 | Création du journal dans `<d>\deployment-logs` | aucun |
| 3 | Contrôle de l'installation actuelle : dossiers, exécutables | aucun |
| 4 | Contrôle des nouveaux fichiers dans `D:\.deploy` | aucun |
| 5 | Copie des nouveaux fichiers dans `<d>\.staging\...` (staging) | aucun |
| 6 | Contrôle des services, des processus et du pool IIS ; mémorisation de l'état initial | aucun |
| — | **`-ValidationOnly` s'arrête ici.** Sinon, confirmation `DEPLOYER` (sauf `-Force`) | — |
| 7 | Arrêt de l'application (et des Runners en cours pour HpcLite) | **arrêt** |
| 8 | Sauvegarde du dossier actuel dans `<d>\.rollback\...`, puis installation | fichiers remplacés |
| 9 | Redémarrage si l'application tournait avant ; contrôle de stabilité (10 s) | redémarrage |

**Points à connaître**
- **Une application arrêtée avant le déploiement reste arrêtée.**
- **HpcLite** : l'Agent, le Runner et le Scheduler sont déployés et restaurés **ensemble**. Les Runners en cours sont arrêtés brutalement et ne sont pas relancés par le script : l'Agent en recrée selon les jobs en base. **Prévenir les utilisateurs avant.**
- **Contrôle de stabilité** : 10 s après chaque démarrage, l'application doit toujours tourner, sinon c'est une erreur.
- **Rollback automatique** : en cas d'erreur après l'arrêt, l'ancienne version est restaurée et l'application redémarrée dans son état initial.
- **`D:\.deploy` n'est jamais modifié** par le script.

---

## 4. Configuration (en tête de `deploy.ps1`)

Section `>>> DEBUT CONFIGURATION` / `<<< FIN CONFIGURATION`, à vérifier **une fois** par environnement.

| Variable | Valeur | Rôle |
|---|---|---|
| `$StxApplicationPoolName` | `styx-api` | Pool IIS de l'API |
| `$TaskflowServiceName` | `TaskFlow.Runner` | Service Taskflow |
| `$HpcLiteAgentServiceName` / `$HpcLiteSchedulerServiceName` | `HpcLite.Agent` / `HpcLite.Scheduler` | Services HpcLite |
| `$TaskflowExecutableRelativePath` | `Socgen.TaskFlow.Runner.exe` | Exécutable Taskflow |
| `$HpcLite…ExecutableName` | `Styx.HpcLite.Agent.exe`, `.Runner.exe`, `.Scheduler.exe` | Exécutables HpcLite |
| `$SourceFolderSTP` / `STX` / `STJ` | `taskflow` / `api` / `hpclite` | Sous-dossiers de `D:\.deploy` |
| `$StartupStabilitySeconds` | `10` | Contrôle de stabilité (`0` = désactivé) |
| `$PreservedRelativePathsSTP` / `STX` / `STJ` | `@()` | Fichiers propres au serveur, conservés d'une version à l'autre (ex. `@("appsettings.json")`) |
| `$ProcessTimeoutSeconds` / `ServiceTimeoutSeconds` / `IisTimeoutSeconds` | `30` / `60` / `60` | Délais maximum d'arrêt et de démarrage |

> ⚠️ Tant que `$PreservedRelativePaths…` est vide, **la configuration livrée dans `D:\.deploy` remplace celle du serveur** (`appsettings.json`, `web.config`…). Les fichiers du serveur restent disponibles dans la sauvegarde.

---

## 5. Fichiers produits

| Emplacement | Contenu | Conservation |
|---|---|---|
| `<d>\deployment-logs\deployment-<date>-<id>.log` | Journal complet | conservé |
| `<d>\deployment-logs\deployment-<date>-<id>.state.json` | État initial des applications | conservé |
| `<d>\.rollback\<date>-<id>\STP` \| `STX` \| `STJ` | Ancienne version sauvegardée | conservé (**à purger manuellement**) |
| `<d>\.staging\<date>-<id>\` | Copie de travail des nouveaux fichiers | supprimé en fin d'exécution, sauf `-KeepTemporaryFiles` |

---

## 6. Codes de sortie

| Code | Signification |
|---|---|
| `0` | Déploiement, ou pré-vol, réussi |
| `1` | Erreur. Si l'application avait été arrêtée, le rollback a été exécuté. Consulter le journal |
| `2` | Annulation : confirmation refusée, ou impossible (console non interactive sans `-Force`) |

Si le journal contient **« ROLLBACK INCOMPLET : intervention manuelle nécessaire »**, appliquer la section 7.

---

## 7. Restauration manuelle

| Sauvegarde | À remettre dans |
|---|---|
| `<d>\.rollback\<date>-<id>\STP` | `<d>\taskflow` |
| `<d>\.rollback\<date>-<id>\STX` | `<d>\api` |
| `<d>\.rollback\<date>-<id>\STJ` | `<d>\HpcLite` |

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

## 8. Dépannage

| Symptôme | Cause probable | Action |
|---|---|---|
| « Attribut inattendu CmdletBinding », accents corrompus | Fichier sans BOM UTF-8 | Ré-enregistrer en UTF-8 avec BOM |
| « deploy.ps1 est introuvable » | Scripts séparés | Garder les quatre scripts dans le même dossier |
| « Dossier source des nouveaux fichiers … introuvable » | `D:\.deploy` absent | Déposer les fichiers, ou utiliser `-SourceRoot` |
| « Nouveaux fichiers … dans le dossier source introuvable » | Sous-dossier `api` / `taskflow` / `hpclite` absent | Vérifier le contenu de `D:\.deploy` |
| « Destination … introuvable » | Application non installée sous `<d>` | Vérifier `-d` |
| « Le pool IIS configuré pour l'API est introuvable » | Nom de pool différent | Corriger `$StxApplicationPoolName` (`appcmd list apppool`) |
| « n'exécute pas l'exécutable attendu » | Service pointant hors de `<d>` | Vérifier le service (`sc.exe qc <service>`) |
| « a démarré puis s'est arrêté » | Configuration invalide, port déjà utilisé (5100 Scheduler, 5200 Agent), base inaccessible | Journal de l'application, Observateur d'événements |
| « cannot be started » (erreur 1053) | Exécutable incapable de tourner en service | Vérifier la version livrée |
| Console figée | Mode d'édition rapide (QuickEdit) | Appuyer sur Échap ; désactiver QuickEdit dans les propriétés de la console |
