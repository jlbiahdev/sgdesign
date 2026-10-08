# Tests de `download_deploy.ps1`

Ce dossier contient le script de déploiement Styx et **162 scénarios de test**
répartis en **20 jalons (0 à 19)**. Chaque jalon ajoute un petit groupe de
fonctionnalités. Les erreurs sont détectées le plus tôt possible, et les opérations
dangereuses ne sont jamais testées en premier :

- l'arrêt d'une application ;
- le remplacement de fichiers ;
- le redémarrage d'un service ;
- le rollback d'un déploiement.

> **Attention**
>
> Les jalons 0 à 11 sont **non destructifs** : ils travaillent dans des dossiers
> factices créés puis supprimés par les tests.
> Les jalons 12 à 18 **arrêtent de vraies applications et remplacent de vrais
> fichiers** : ils ne s'exécutent que sur l'environnement réel de **test**, jamais
> sur la production (garde-fou automatique).
> Le jalon 19 se lance sur le serveur cible : pré-vol `-ValidationOnly` et
> contrôles en lecture seule.

---

## Sommaire

1. [Contenu](#1-contenu)
2. [Principe](#2-principe)
3. [Préparer la machine de test](#3-préparer-la-machine-de-test)
4. [Lancer les tests](#4-lancer-les-tests)
5. [Lire un résultat](#5-lire-un-résultat)
6. [Progression des jalons](#6-progression-des-jalons)
7. [Règles de sécurité](#7-règles-de-sécurité)
8. [Points de test (erreurs volontaires)](#8-points-de-test-erreurs-volontaires)
9. [Ajouter un scénario](#9-ajouter-un-scénario)
10. [Limites connues](#10-limites-connues)
11. [Jalon 19 : contrôles fonctionnels manuels](#11-jalon-19--contrôles-fonctionnels-manuels)
12. [Tableau de suivi](#12-tableau-de-suivi)
13. [Critères de validation d'un jalon](#13-critères-de-validation-dun-jalon)
14. [Historique des validations](#14-historique-des-validations)

---

## 1. Contenu

```text
tests_download_deploy\
├── README.md                  ce fichier
├── download_deploy.ps1        LE script de déploiement (version de production, générée)
├── run_jalon.ps1              lance tous les scénarios d'un jalon + bilan
├── _tools\
│   ├── download_deploy.template.ps1   SOURCE unique du script, balisée par jalon
│   ├── Build-JalonVersions.ps1        génère la production et les versions par jalon
│   └── New-FakeStyxTest.ps1           binaires factices + services de test (D:\Styx-Test)
├── _common\
│   ├── TestHelpers.psm1       boîte à outils commune à tous les tests
│   └── test-config.psd1       configuration de la machine de test (à adapter)
├── jalon_0_compatibilite_serveur\
│   ├── CHANGEMENTS.md         code ajouté par ce jalon (généré)
│   ├── t_0_01_psversion_ok\
│   │   ├── launch_test.ps1    lanceur documenté du scénario
│   │   └── download_deploy.ps1  version INCRÉMENTALE du script pour ce jalon
│   └── ...
├── ...
├── jalon_19_production\
└── resultats\                 créé par run_jalon.ps1 (bilans CSV)
```

Tous les fichiers `.ps1`, `.psm1` et `.psd1` sont encodés en **UTF-8 avec BOM**, avec
des fins de ligne Windows. **Conservez cet encodage** si vous les modifiez : sans BOM,
Windows PowerShell 5.1 lit les fichiers en ANSI et corrompt les accents.

### Nommage

| Élément | Signification |
|---|---|
| `jalon_X_description` | tous les scénarios du jalon X |
| `t_X_YY_description_ok` | scénario YY du jalon X ; `download_deploy.ps1` doit **réussir** |
| `t_X_YY_description_ko` | `download_deploy.ps1` doit **refuser de continuer**, proprement |

Un scénario `_ko` est **réussi** quand l'échec est : attendu, détecté, expliqué par un
message compréhensible, accompagné du bon code de sortie, et sans effet indésirable sur
la machine.

---

## 2. Principe

### Un code qui grandit d'un jalon à l'autre

Le `download_deploy.ps1` d'un scénario du jalon N est une **version incrémentale** :
il ne contient **que** le code des jalons 0 à N (fonctions, configuration, étapes du
programme principal). Il se termine par :

```text
JALON N ATTEINT : <ce qui vient d'être vérifié>.
TEST TERMINÉ : ...
```

puis `exit 0`. La version du jalon N+1 reprend celle du jalon N et y ajoute le code du
jalon N+1. Le fichier `CHANGEMENTS.md` de chaque dossier de jalon montre **exactement**
ce code ajouté, pour que la relecture porte sur l'incrément. Les versions des jalons 15
à 19 sont identiques au script de production.

Toutes ces versions sont **générées** à partir d'une source unique,
`_tools\download_deploy.template.ps1`. C'est le script complet, découpé par des
balises de jalon (voir §9). Le script de production à la racine est lui aussi généré
depuis cette source : les versions incrémentales et la production ne peuvent donc pas
diverger.

| Version du jalon | Contient en plus du jalon précédent | Se termine après... |
|---|---|---|
| 0 | journal console, droits, compatibilité serveur | compatibilité du serveur |
| 1 | affichage des paramètres | affichage des paramètres |
| 2 | validation de `-d` et fichier journal (*) | création du journal |
| 3 | contrôle des trigrammes, synthèse de la demande | validation de la demande |
| 4 | contrôle des dossiers et exécutables | contrôle des destinations |
| 5 | variables d'environnement, `-PackageFile` | identification de la source du package |
| 6 | téléchargement curl / copie du package local | récupération du package |
| 7 | extraction et contrôle du contenu | extraction |
| 8 | staging | staging |
| 9 | services Windows et processus | services et processus |
| 10 | lecture du pool IIS | lecture du pool IIS |
| 11 | état initial (`state.json`), `-ValidationOnly` | état initial |
| 12 | confirmation, arrêt des applications | arrêt (**les applications restent arrêtées** ; le lanceur les restaure) |
| 13 | redémarrage | arrêt **puis** redémarrage, sans toucher aux fichiers |
| 14 | sauvegarde, rollback (**) | sauvegarde vérifiée, **restaurée**, puis redémarrage |
| 15 | installation, message de succès | aucun arrêt : version de production |
| 16 à 19 | rien (ces jalons testent le code existant) | version de production |

(*) Le journal est créé dans `<d>\deployment-logs` : `-d` doit donc être validé dès le
jalon 2. Le jalon 3 ajoute le contrôle des trigrammes et la synthèse de la demande.
Les scénarios de validation de `-d` restent au jalon 3, comme dans le plan d'origine.

(**) Dès que le jalon 14 déplace des dossiers, le code de rollback doit exister : sinon
une erreur aux jalons 14 ou 15 laisserait l'environnement de test cassé. Il arrive donc
au jalon 14. Le jalon 16 le teste volontairement, à chaque étape.

### Le lanceur adapte une copie, jamais l'original

`launch_test.ps1` ne modifie jamais le `download_deploy.ps1` de son dossier. Il en écrit
une **copie temporaire** (`%TEMP%\styx-tests\<scénario>\`) dans laquelle il peut :

- reporter les valeurs de `test-config.psd1` (pool IIS, noms des services), si la version
  du jalon contient déjà la ligne correspondante ;
- passer en **mode test** (`$UseWindowsServices = $false`) : les composants sont alors de
  simples processus factices, et aucun vrai service n'est touché ;
- simuler un serveur différent : lecteur absent, IIS ou curl absents ;
- injecter une **erreur volontaire** à un point de test (rollback, voir §8).

Les remplacements ne portent que sur la section `CONFIGURATION` du script. Une valeur
demandée explicitement par un test doit trouver exactement une ligne. Sinon le test
s'arrête au statut « non exécuté » : un test ne tourne jamais sur un script qu'il croit,
à tort, avoir adapté.

### Deux environnements

| Environnement | Où | Utilisé par | Contenu |
|---|---|---|---|
| **Factice** | `D:\Styx-Tests-Auto\<scénario>` | jalons 1 à 11, variantes « mode test » des jalons 12 à 16 | arborescence créée par le test ; les `.exe` sont des copies d'un petit programme « dormeur » qui attend sans rien faire ; tout est supprimé à la fin |
| **Réel de test** | `D:\Styx-Test` | jalons 9 à 18 (scénarios marqués *EnvironnementReel*) | vrais binaires Styx, vrais services Windows, vrai pool IIS de **test** |
| Production | `D:\Applications` | jalon 19 uniquement | pré-vol `-ValidationOnly` et contrôles en lecture seule |

### Structure d'un lanceur

```powershell
Import-Module ..\..\_common\TestHelpers.psm1
try {
    Start-Test ...                    # en-tête, prérequis, dossier de travail
    # --- Préparation ---             # environnement factice, package, copie adaptée
    # --- Exécution ---               # Invoke-ScriptUnderTest (processus séparé)
    # --- Vérifications ---           # Assert-* (toutes évaluées, aucune n'interrompt)
}
catch   { Register-TestError $_ }    # prérequis absent / erreur du test lui-même
finally { Clear-TestEnvironment }    # nettoyage TOUJOURS exécuté
exit (Complete-Test)                  # TEST RÉUSSI / ÉCHOUÉ / NON EXÉCUTÉ
```

Chaque `launch_test.ps1` documente dans son en-tête : l'objectif, les préconditions, les
étapes, le résultat attendu et le nettoyage. `Get-Help .\launch_test.ps1 -Full` les
affiche.

---

## 3. Préparer la machine de test

À faire **une fois**.

### 3.1 Copier et débloquer

```powershell
# Fichiers venus d'un zip ou d'un partage : Windows les marque comme « téléchargés ».
Get-ChildItem -Path D:\tests_download_deploy -Recurse | Unblock-File
```

Si l'exécution de scripts est bloquée, pour la session courante seulement :

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

### 3.2 Renseigner `_common\test-config.psd1`

| Clé | Valeur par défaut | Rôle |
|---|---|---|
| `RacineTestsAuto` | `D:\Styx-Tests-Auto` | environnements factices (doit être sous `D:\`, sans donnée utile) |
| `RacineReelle` | `D:\Styx-Test` | environnement réel de test |
| `RacineProduction` | `D:\Applications` | garde-fou + jalon 19 |
| `ServiceTaskflow` / `ServiceAgent` / `ServiceScheduler` | `TaskFlow.Runner.Test` / `HpcLite.Agent.Test` / `HpcLite.Scheduler.Test` | services de **test** (différents de ceux de production) |
| `PoolIis` | `STYX` | pool IIS de l'API sur la machine de test |
| `Executable*` | `Socgen.TaskFlow.Runner.exe`, `Styx.HpcLite.{Agent,Runner,Scheduler}.exe` | noms des exécutables (identiques au script) |
| `PackageReel` | `D:\Styx-Test-Packages\Styx.Publish.nupkg` | vrai package (jalons 15 à 18) |
| `UrlPackageReel` | *(vide)* | URL Artifactory d'un vrai package (jalon 6) |

Aucun secret dans ce fichier.

### 3.3 Environnement réel de test (jalons 9 à 18)

1. Installer les binaires sous `D:\Styx-Test\taskflow`, `\api` et
   `\HpcLite\{agent, runner, scheduler}`, et créer les trois services de **test**.
   Le plus simple, en console administrateur :

   ```powershell
   .\_tools\New-FakeStyxTest.ps1
   ```

   Ce script compile un binaire **factice** (il attend sans rien faire, et sait se
   comporter en service Windows), le copie sous les noms `Executable*` et crée les
   services `Service*` de `test-config.psd1` en démarrage manuel. Il refuse de
   toucher à un service existant qui pointe hors de `D:\Styx-Test` (production).
   Les vrais binaires remplaceront les factices quand ils seront nécessaires.
2. Les trois services de test doivent exécuter les binaires de `D:\Styx-Test`. Pour le vérifier :

   ```powershell
   Get-CimInstance Win32_Service |
       Where-Object Name -in "TaskFlow.Runner.Test", "HpcLite.Agent.Test", "HpcLite.Scheduler.Test" |
       Select-Object Name, State, PathName
   ```

   Avant chaque test réel, le module vérifie automatiquement que chaque `PathName`
   commence par `RacineReelle`, et que `RacineReelle` est différente de
   `RacineProduction`. Sinon le test est refusé.
3. Le pool IIS de test (`PoolIis`) doit exister et servir `D:\Styx-Test\api`.
4. Télécharger **une fois** un vrai package vers `PackageReel` :

   ```powershell
   New-Item -ItemType Directory -Force D:\Styx-Test-Packages | Out-Null
   curl.exe -u "$env:ARTIFACTORY_USERNAME`:$env:ARTIFACTORY_TOKEN" -L `
       -o D:\Styx-Test-Packages\Styx.Publish.nupkg "https://.../Styx.Publish.<version>.nupkg"
   ```

   Les tests n'utilisent jamais ce fichier directement. Ils en font une copie marquée
   (`version.txt = nouvelle-version`) pour pouvoir vérifier ce qui a été installé.

### 3.4 Identifiants (jalon 6 uniquement)

Les scénarios de vrai téléchargement lisent `ARTIFACTORY_USERNAME` et `ARTIFACTORY_TOKEN`,
dans la session ou au niveau Machine. Sans ces variables ou sans `UrlPackageReel`, ils
sont signalés « non exécutés » (code 2), et non en échec.

---

## 4. Lancer les tests

Toujours depuis une console **Windows PowerShell 5.1 administrateur** (sauf
`t_0_08_administrateur_ko`, voir §10).

```powershell
# Un scénario
Set-Location D:\tests_download_deploy\jalon_3_validation_demande\t_3_08_chemin_sur_c_ko
.\launch_test.ps1

# Tout un jalon, avec bilan (et CSV dans .\resultats)
Set-Location D:\tests_download_deploy
.\run_jalon.ps1 -Jalon 3

# Une partie d'un jalon
.\run_jalon.ps1 -Jalon 4 -Filtre "stj"
```

`run_jalon.ps1` demande de taper `OUI` avant les jalons 12 et plus.

Les scénarios sont indépendants : chacun prépare son contexte et le défait. Ils peuvent
être lancés dans n'importe quel ordre, et plusieurs fois de suite avec le même résultat.

---

## 5. Lire un résultat

### Codes de sortie de `download_deploy.ps1`

| Code | Signification |
|:---:|---|
| 0 | déploiement, validation (`-ValidationOnly`) ou jalon de test terminé |
| 1 | erreur détectée par le script (avec rollback si des fichiers avaient été remplacés) |
| 2 | annulation volontaire : confirmation refusée, ou impossible en session non interactive |

### Codes de sortie d'un `launch_test.ps1`

| Code | Verdict | Signification |
|:---:|---|---|
| 0 | TEST RÉUSSI | le comportement observé est celui attendu |
| 1 | TEST ÉCHOUÉ | au moins une vérification a échoué (la liste est affichée) |
| 2 | TEST NON EXÉCUTÉ | prérequis absent, ou erreur du lanceur lui-même |

Un scénario `_ko` peut donc être **réussi** alors que `download_deploy.ps1` a renvoyé 1 :

```text
======================================================================
TEST RÉUSSI
Scénario          : t_3_08_chemin_sur_c_ko
Résultat attendu  : Échec contrôlé
Code attendu      : 1
Code obtenu       : 1
Vérifications OK  : 3
======================================================================
```

Pendant l'exécution, la sortie du script testé est affichée en retrait (`  | ...`), puis
chaque vérification en `[OK]` ou `[ÉCHEC]`.

---

## 6. Progression des jalons

| Jalon | Dossier | Fonctionnalité | Risque | Environnement | Scénarios |
|:---:|---|---|---|---|:---:|
| 0 | `jalon_0_compatibilite_serveur` | Compatibilité du serveur | Aucun | Factice | 11 |
| 1 | `jalon_1_parametres` | Lecture des paramètres | Aucun | Factice | 10 |
| 2 | `jalon_2_journalisation` | Journalisation | Aucun | Factice | 7 |
| 3 | `jalon_3_validation_demande` | Validation de la demande | Aucun | Factice | 12 |
| 4 | `jalon_4_validation_destinations` | Validation des destinations | Aucun | Factice | 14 |
| 5 | `jalon_5_variables_environnement` | Variables d'environnement et source du package | Aucun | Factice | 12 |
| 6 | `jalon_6_telechargement` | Téléchargement | Faible | Factice | 10 |
| 7 | `jalon_7_extraction` | Extraction du package | Faible | Factice | 8 |
| 8 | `jalon_8_staging` | Préparation du staging | Faible | Factice | 6 |
| 9 | `jalon_9_services_processus` | Services Windows et processus | Faible | Réel + factice | 17 |
| 10 | `jalon_10_iis` | Lecture de la configuration IIS | Faible | Factice + IIS/services | 5 |
| 11 | `jalon_11_etat_initial` | Mémorisation de l'état initial | Faible | Réel + factice | 5 |
| 12 | `jalon_12_arrets` | Arrêt des applications | Élevé | Réel + factice | 9 |
| 13 | `jalon_13_redemarrages` | Redémarrage des applications | Élevé | Réel + factice | 8 |
| 14 | `jalon_14_sauvegarde` | Sauvegarde des fichiers | Élevé | Réel + factice | 5 |
| 15 | `jalon_15_installation` | Installation des fichiers | Très élevé | Réel + factice | 6 |
| 16 | `jalon_16_rollback` | Rollback | Très élevé | Réel + factice | 6 |
| 17 | `jalon_17_composants_complets` | Test complet par composant | Très élevé | Réel | 3 |
| 18 | `jalon_18_combinaisons` | Test des combinaisons | Très élevé | Réel | 6 |
| 19 | `jalon_19_production` | Validation en conditions réelles | Réel | Serveur cible | 2 |

**Règle** : on ne commence un jalon qu'après avoir validé le précédent (§13). Les jalons à
risque élevé ne se lancent qu'une fois **tous** les jalons non destructifs validés.

**Ordre conseillé aux jalons 17 et 18** : STX d'abord (le plus simple : un pool IIS), puis
STP, puis STJ (plusieurs services et des Runners).

**Après le jalon 11**, `-ValidationOnly` sur le script complet constitue un vrai pré-vol.
On peut le lancer sans risque sur la machine cible : il arrête tout avant le premier
arrêt d'application.

---

## 7. Règles de sécurité

Un test ne doit **jamais** :

- utiliser un dossier ou un processus de production (garde-fou : `RacineReelle` ≠
  `RacineProduction`, et les services doivent pointer sur `RacineReelle`) ;
- arrêter IIS entier : seul le pool est arrêté, et le jalon 12 le vérifie ;
- afficher ou journaliser un secret : `Assert-NoSecret` contrôle la console, le journal et
  `state.json` ;
- supprimer un dossier qu'il n'a pas créé ;
- modifier durablement une variable d'environnement : les valeurs d'origine, session et
  Machine, sont restaurées dans `finally` ;
- laisser une application dans un état différent de son état initial : l'état des
  services et du pool est mémorisé, puis restauré.

Le nettoyage (`Clear-TestEnvironment`) s'exécute **même si le test plante**. Il arrête
les processus factices, restaure services, pool et variables, remet le `version.txt`
d'origine, supprime les sauvegardes `.rollback` créées pendant le test, puis les dossiers
factices et le dossier de travail.

> Les jalons 15 à 18 **installent réellement** le vrai package dans `D:\Styx-Test`.
> Après ces tests, l'environnement de test tourne donc avec la version de `PackageReel`,
> et les services retrouvent leur état initial (démarré ou arrêté).

---

## 8. Points de test (erreurs volontaires)

Le script de production contient quelques commentaires sans effet :

```powershell
# [POINT-DE-TEST:apres-arret]
```

Les lanceurs du jalon 16 (rollback) remplacent un de ces commentaires, **dans la copie
temporaire**, par une erreur volontaire déclenchée une seule fois. Cela permet de tester
le rollback à chaque étape :

| Point | Emplacement |
|---|---|
| `apres-journal` | juste après la création du journal (test du niveau ERREUR, jalon 2) |
| `apres-arret` | après l'arrêt des applications, avant toute sauvegarde |
| `apres-sauvegarde` | après la sauvegarde d'un composant, avant son installation |
| `apres-installation-composant` | après l'installation d'un composant (option : condition, ex. au 2e composant) |
| `pendant-redemarrage` | au milieu du redémarrage (après STP/STX, avant STJ) |

L'erreur ne se déclenche qu'une fois. Le redémarrage après rollback, qui repasse au même
endroit, peut donc réussir.

---

## 9. Ajouter un scénario

1. Copier le dossier d'un scénario proche du même jalon et le renommer
   `t_X_YY_description_ok|ko` : pas d'espace, pas d'accent.
2. Ne **pas** toucher à son `download_deploy.ps1` : il est généré.
3. Adapter l'en-tête et le corps de `launch_test.ps1`. Les briques disponibles sont
   documentées dans `_common\TestHelpers.psm1` (`Get-Help` fonctionne sur chaque
   fonction) :
   - préparation : `New-FakeEnvironment`, `New-TestPackage`, `New-PackageFromReal`,
     `New-CorruptPackage`, `New-ScriptUnderTest`, `Start-FakeProcess`,
     `Set-TestEnvironmentVariables`, `Clear-ArtifactoryVariables`, `Set-ServiceStatus`,
     `Set-PoolState`, `Register-PoolRestore`, `Set-RealVersionMarkers` ;
   - exécution : `Invoke-ScriptUnderTest` ;
   - vérifications : `Assert-ExitCode`, `Assert-OutputMatch`, `Assert-OutputNotMatch`,
     `Assert-LogMatch`, `Assert-Condition`, `Assert-NoSecret`,
     `Assert-ApplicationStateUnchanged`.
4. Ajouter une ligne au tableau de suivi (§12).

### Modifier le script de déploiement

Ne jamais modifier un `download_deploy.ps1` généré : la modification serait écrasée.

1. Modifier `_tools\download_deploy.template.ps1`.
2. Placer le nouveau code dans la région du jalon qui l'introduit. Les balises sont des
   lignes qui commencent en colonne 0 :

   | Balise | Effet |
   |---|---|
   | `#>>J7` ... `#<<J7` | code présent à partir du jalon 7 |
   | `#>>J14-14` ... `#<<J14-14` | code présent **uniquement** dans la version du jalon 14 |
   | `#@FIN 7\|description` | fin de la version du jalon 7 (« JALON 7 ATTEINT ») |

3. Régénérer :

   ```powershell
   .\_tools\Build-JalonVersions.ps1
   ```

   Le script réécrit `download_deploy.ps1` à la racine et dans chaque scénario, ainsi que
   les `CHANGEMENTS.md`. Il vérifie que les balises sont équilibrées, que chaque version
   est syntaxiquement valide, que chaque jalon 0 à 14 a exactement une fin, et que les
   versions 15 à 19 sont identiques à la production.
4. Relancer les jalons concernés : celui qui a changé et tous les suivants.

---

## 10. Limites connues

- **`t_0_08_administrateur_ko`** doit être lancé à la main depuis une console **non**
  administrateur. Dans `run_jalon.ps1` (console administrateur), il apparaît « NON
  EXÉCUTÉ », ce qui est normal.
- **`t_0_02_psversion_ko`** simule un PowerShell trop ancien en exigeant la version 99.0 :
  c'est le mécanisme `#requires` qui est vérifié.
- **`t_0_04`, `t_0_06`, `t_0_10`** simulent l'absence d'IIS, de D: ou de curl.exe en
  modifiant le chemin configuré dans la copie temporaire.
- **Jalon 6** : les scénarios 01 à 04 et 06 ont besoin du réseau Artifactory et de vrais
  identifiants. Le 05 (serveur injoignable) n'en a pas besoin.
- **Jalon 9 et suivants (mode test)** : le « dormeur » est compilé localement à la
  première utilisation (`Add-Type`, compilateur C# du .NET Framework). Si une politique
  de sécurité l'interdit, les scénarios concernés seront « non exécutés ».
- Les messages d'erreur **de PowerShell lui-même** (paramètre manquant, conflit de
  paramètres) dépendent de la langue de Windows. Les vérifications correspondantes
  acceptent l'anglais et le français.
- Ces tests ont été **analysés et vérifiés hors Windows**. Le premier passage de chaque
  jalon sur la machine de test fait donc aussi office de validation des lanceurs : en
  cas de verdict « NON EXÉCUTÉ » dû à une erreur du lanceur, corriger le lanceur, pas le
  script.

---

## 11. Jalon 19 : contrôles fonctionnels manuels

Avant le premier déploiement réel :

- [ ] prévenir les utilisateurs ;
- [ ] confirmer l'existence d'une sauvegarde externe ;
- [ ] vérifier les variables Machine (`ARTIFACTORY_USERNAME`, `ARTIFACTORY_TOKEN`,
      `STYX_PACKAGE_URL`) ;
- [ ] vérifier l'URL exacte du package ;
- [ ] vérifier les noms des exécutables, des services et du pool IIS dans la section
      CONFIGURATION ;
- [ ] fermer les outils susceptibles de verrouiller des fichiers (explorateur, éditeurs,
      consoles ouvertes dans les dossiers) ;
- [ ] lancer `t_19_01_preflight_validation_only_ok` ;
- [ ] lancer le déploiement en administrateur et surveiller le journal.

Après le déploiement :

- [ ] lancer `t_19_02_controles_post_deploiement_ok` (lecture seule) ;
- [ ] Taskflow répond ;
- [ ] l'API répond sous IIS ;
- [ ] le Scheduler fonctionne ;
- [ ] l'Agent fonctionne et peut déclencher un Runner ;
- [ ] les jobs sont correctement mis à jour en base.

---

## 12. Tableau de suivi

Cocher « Validé » quand le scénario a été exécuté et a produit le résultat attendu. Les
bilans CSV de `run_jalon.ps1` sont dans `resultats\`.

### Jalon 0 - Compatibilité du serveur

| Créé | Validé | Scénario | Résultat attendu | Code |
|:---:|:---:|---|---|:---:|
| ☑ | ☐ | `t_0_01_psversion_ok` | Succès | 0 |
| ☑ | ☐ | `t_0_02_psversion_ko` | Échec contrôlé | 1 |
| ☑ | ☐ | `t_0_03_iis_disponible_ok` | Succès | 0 |
| ☑ | ☐ | `t_0_04_iis_indisponible_ko` | Échec contrôlé | 1 |
| ☑ | ☐ | `t_0_05_lecteur_d_disponible_ok` | Succès | 0 |
| ☑ | ☐ | `t_0_06_lecteur_d_indisponible_ko` | Échec contrôlé | 1 |
| ☑ | ☐ | `t_0_07_administrateur_ok` | Succès | 0 |
| ☑ | ☐ | `t_0_08_administrateur_ko` | Échec contrôlé | 1 |
| ☑ | ☐ | `t_0_09_curl_disponible_ok` | Succès | 0 |
| ☑ | ☐ | `t_0_10_curl_indisponible_ko` | Échec contrôlé | 1 |
| ☑ | ☐ | `t_0_11_curl_inutile_avec_packagefile_ok` | Succès | 0 |

### Jalon 1 - Lecture des paramètres

| Créé | Validé | Scénario | Résultat attendu | Code |
|:---:|:---:|---|---|:---:|
| ☑ | ☐ | `t_1_01_destination_et_stp_ok` | Succès | 0 |
| ☑ | ☐ | `t_1_02_destination_et_stx_ok` | Succès | 0 |
| ☑ | ☐ | `t_1_03_destination_et_stj_ok` | Succès | 0 |
| ☑ | ☐ | `t_1_04_tous_les_trigrammes_ok` | Succès | 0 |
| ☑ | ☐ | `t_1_05_alias_d_ok` | Succès | 0 |
| ☑ | ☐ | `t_1_06_destination_absente_ko` | Échec contrôlé | 1 |
| ☑ | ☐ | `t_1_07_parametre_inconnu_ko` | Échec contrôlé | 1 |
| ☑ | ☐ | `t_1_08_packageurl_et_packagefile_ko` | Échec contrôlé | 1 |
| ☑ | ☐ | `t_1_09_packagefile_affiche_ok` | Succès | 0 |
| ☑ | ☐ | `t_1_10_options_affichees_ok` | Succès | 0 |

### Jalon 2 - Journalisation

| Créé | Validé | Scénario | Résultat attendu | Code |
|:---:|:---:|---|---|:---:|
| ☑ | ☐ | `t_2_01_log_info_ok` | Succès | 0 |
| ☑ | ☐ | `t_2_02_log_ok_ok` | Succès | 0 |
| ☑ | ☐ | `t_2_03_log_attention_ok` | Succès | 0 |
| ☑ | ☐ | `t_2_04_log_erreur_ok` | Échec contrôlé | 1 |
| ☑ | ☐ | `t_2_05_fichier_log_cree_ok` | Succès | 0 |
| ☑ | ☐ | `t_2_06_contenu_fichier_log_ok` | Succès | 0 |
| ☑ | ☐ | `t_2_07_dossier_log_inaccessible_ko` | Échec contrôlé | 1 |

### Jalon 3 - Validation de la demande

| Créé | Validé | Scénario | Résultat attendu | Code |
|:---:|:---:|---|---|:---:|
| ☑ | ☐ | `t_3_01_un_trigramme_stp_ok` | Succès | 0 |
| ☑ | ☐ | `t_3_02_un_trigramme_stx_ok` | Succès | 0 |
| ☑ | ☐ | `t_3_03_un_trigramme_stj_ok` | Succès | 0 |
| ☑ | ☐ | `t_3_04_plusieurs_trigrammes_ok` | Succès | 0 |
| ☑ | ☐ | `t_3_05_aucun_trigramme_ko` | Échec contrôlé | 1 |
| ☑ | ☐ | `t_3_06_chemin_absolu_sur_d_ok` | Succès | 0 |
| ☑ | ☐ | `t_3_07_chemin_relatif_ko` | Échec contrôlé | 1 |
| ☑ | ☐ | `t_3_08_chemin_sur_c_ko` | Échec contrôlé | 1 |
| ☑ | ☐ | `t_3_09_chemin_sur_autre_lecteur_ko` | Échec contrôlé | 1 |
| ☑ | ☐ | `t_3_10_dossier_existant_ok` | Succès | 0 |
| ☑ | ☐ | `t_3_11_dossier_inexistant_ko` | Échec contrôlé | 1 |
| ☑ | ☐ | `t_3_12_lecteur_d_sans_antislash_ko` | Échec contrôlé | 1 |

### Jalon 4 - Validation des destinations

| Créé | Validé | Scénario | Résultat attendu | Code |
|:---:|:---:|---|---|:---:|
| ☑ | ☐ | `t_4_01_stp_taskflow_existant_ok` | Succès | 0 |
| ☑ | ☐ | `t_4_02_stp_taskflow_absent_ko` | Échec contrôlé | 1 |
| ☑ | ☐ | `t_4_03_stx_api_existant_ok` | Succès | 0 |
| ☑ | ☐ | `t_4_04_stx_api_absent_ko` | Échec contrôlé | 1 |
| ☑ | ☐ | `t_4_05_stj_arborescence_complete_ok` | Succès | 0 |
| ☑ | ☐ | `t_4_06_stj_hpclite_absent_ko` | Échec contrôlé | 1 |
| ☑ | ☐ | `t_4_07_stj_agent_absent_ko` | Échec contrôlé | 1 |
| ☑ | ☐ | `t_4_08_stj_runner_absent_ko` | Échec contrôlé | 1 |
| ☑ | ☐ | `t_4_09_stj_scheduler_absent_ko` | Échec contrôlé | 1 |
| ☑ | ☐ | `t_4_10_stx_ignore_taskflow_absent_ok` | Succès | 0 |
| ☑ | ☐ | `t_4_11_stp_ignore_api_absente_ok` | Succès | 0 |
| ☑ | ☐ | `t_4_12_stj_ignore_stp_et_stx_absents_ok` | Succès | 0 |
| ☑ | ☐ | `t_4_13_stp_executable_absent_ko` | Échec contrôlé | 1 |
| ☑ | ☐ | `t_4_14_stj_executable_runner_absent_ko` | Échec contrôlé | 1 |

### Jalon 5 - Variables d'environnement et source du package

| Créé | Validé | Scénario | Résultat attendu | Code |
|:---:|:---:|---|---|:---:|
| ☑ | ☐ | `t_5_01_variables_machine_presentes_ok` | Succès | 0 |
| ☑ | ☐ | `t_5_02_username_absent_ko` | Échec contrôlé | 1 |
| ☑ | ☐ | `t_5_03_token_absent_ko` | Échec contrôlé | 1 |
| ☑ | ☐ | `t_5_04_package_url_absente_ko` | Échec contrôlé | 1 |
| ☑ | ☐ | `t_5_05_package_url_https_ok` | Succès | 0 |
| ☑ | ☐ | `t_5_06_package_url_http_ko` | Échec contrôlé | 1 |
| ☑ | ☐ | `t_5_07_token_non_affiche_console_ok` | Succès | 0 |
| ☑ | ☐ | `t_5_08_token_non_ecrit_logs_ok` | Succès | 0 |
| ☑ | ☐ | `t_5_09_variables_session_prioritaires_ok` | Succès | 0 |
| ☑ | ☐ | `t_5_10_packagefile_sans_identifiants_ok` | Succès | 0 |
| ☑ | ☐ | `t_5_11_packagefile_absent_ko` | Échec contrôlé | 1 |
| ☑ | ☐ | `t_5_12_packagefile_relatif_ko` | Échec contrôlé | 1 |

### Jalon 6 - Téléchargement

| Créé | Validé | Scénario | Résultat attendu | Code |
|:---:|:---:|---|---|:---:|
| ☑ | ☐ | `t_6_01_telechargement_ok` | Succès | 0 |
| ☑ | ☐ | `t_6_02_mauvais_token_ko` | Échec contrôlé | 1 |
| ☑ | ☐ | `t_6_03_mauvais_utilisateur_ko` | Échec contrôlé | 1 |
| ☑ | ☐ | `t_6_04_package_introuvable_ko` | Échec contrôlé | 1 |
| ☑ | ☐ | `t_6_05_serveur_injoignable_ko` | Échec contrôlé | 1 |
| ☑ | ☐ | `t_6_06_token_absent_console_et_logs_ok` | Succès | 0 |
| ☑ | ☐ | `t_6_07_package_local_ok` | Succès | 0 |
| ☑ | ☐ | `t_6_08_fichiers_temporaires_conserves_ok` | Succès | 0 |
| ☑ | ☐ | `t_6_09_fichiers_temporaires_supprimes_ok` | Succès | 0 |
| ☑ | ☐ | `t_6_10_dossier_travail_sur_d_ok` | Succès | 0 |

### Jalon 7 - Extraction du package

| Créé | Validé | Scénario | Résultat attendu | Code |
|:---:|:---:|---|---|:---:|
| ☑ | ☐ | `t_7_01_package_valide_stx_ok` | Succès | 0 |
| ☑ | ☐ | `t_7_02_package_valide_tous_ok` | Succès | 0 |
| ☑ | ☐ | `t_7_03_archive_invalide_ko` | Échec contrôlé | 1 |
| ☑ | ☐ | `t_7_04_contenu_stx_absent_ko` | Échec contrôlé | 1 |
| ☑ | ☐ | `t_7_05_contenu_vide_ko` | Échec contrôlé | 1 |
| ☑ | ☐ | `t_7_06_noms_encodes_decodes_ok` | Succès | 0 |
| ☑ | ☐ | `t_7_07_entree_hors_dossier_ko` | Échec contrôlé | 1 |
| ☑ | ☐ | `t_7_08_seul_contenu_demande_controle_ok` | Succès | 0 |

### Jalon 8 - Préparation du staging

| Créé | Validé | Scénario | Résultat attendu | Code |
|:---:|:---:|---|---|:---:|
| ☑ | ☐ | `t_8_01_staging_stx_ok` | Succès | 0 |
| ☑ | ☐ | `t_8_02_staging_tous_ok` | Succès | 0 |
| ☑ | ☐ | `t_8_03_executable_taskflow_absent_du_package_ko` | Échec contrôlé | 1 |
| ☑ | ☐ | `t_8_04_executable_agent_absent_du_package_ko` | Échec contrôlé | 1 |
| ☑ | ☐ | `t_8_05_staging_sur_lecteur_d_ok` | Succès | 0 |
| ☑ | ☐ | `t_8_06_aucune_application_arretee_ok` | Succès | 0 |

### Jalon 9 - Services Windows et processus

| Créé | Validé | Scénario | Résultat attendu | Code |
|:---:|:---:|---|---|:---:|
| ☑ | ☐ | `t_9_01_aucun_processus_ok` | Succès | 0 |
| ☑ | ☐ | `t_9_02_agent_seul_ok` | Succès | 0 |
| ☑ | ☐ | `t_9_03_scheduler_seul_ok` | Succès | 0 |
| ☑ | ☐ | `t_9_04_agent_et_scheduler_ok` | Succès | 0 |
| ☑ | ☐ | `t_9_05_plusieurs_runners_ok` | Succès | 0 |
| ☑ | ☐ | `t_9_06_complet_avec_runners_ok` | Succès | 0 |
| ☑ | ☐ | `t_9_07_deux_agents_ko` | Échec contrôlé | 1 |
| ☑ | ☐ | `t_9_08_deux_schedulers_ko` | Échec contrôlé | 1 |
| ☑ | ☐ | `t_9_09_un_taskflow_ok` | Succès | 0 |
| ☑ | ☐ | `t_9_10_deux_taskflows_ko` | Échec contrôlé | 1 |
| ☑ | ☐ | `t_9_11_processus_homonyme_ignore_ok` | Succès | 0 |
| ☑ | ☐ | `t_9_12_mode_test_signale_ok` | Succès | 0 |
| ☑ | ☐ | `t_9_13_services_configures_ok` | Succès | 0 |
| ☑ | ☐ | `t_9_14_service_inexistant_ko` | Échec contrôlé | 1 |
| ☑ | ☐ | `t_9_15_service_autre_executable_ko` | Échec contrôlé | 1 |
| ☑ | ☐ | `t_9_16_nom_service_vide_ko` | Échec contrôlé | 1 |
| ☑ | ☐ | `t_9_17_etat_service_arrete_detecte_ok` | Succès | 0 |

### Jalon 10 - Lecture de la configuration IIS

| Créé | Validé | Scénario | Résultat attendu | Code |
|:---:|:---:|---|---|:---:|
| ☑ | ☐ | `t_10_01_pool_existant_demarre_ok` | Succès | 0 |
| ☑ | ☐ | `t_10_02_pool_inexistant_ko` | Échec contrôlé | 1 |
| ☑ | ☐ | `t_10_03_pool_arrete_ok` | Succès | 0 |
| ☑ | ☐ | `t_10_04_pool_non_arrete_par_le_script_ok` | Succès | 0 |
| ☑ | ☐ | `t_10_05_iis_non_consulte_sans_stx_ok` | Succès | 0 |

### Jalon 11 - Mémorisation de l'état initial

| Créé | Validé | Scénario | Résultat attendu | Code |
|:---:|:---:|---|---|:---:|
| ☑ | ☐ | `t_11_01_etat_initial_enregistre_ok` | Succès | 0 |
| ☑ | ☐ | `t_11_02_etat_contenu_limite_ok` | Succès | 0 |
| ☑ | ☐ | `t_11_03_validation_only_ok` | Succès | 0 |
| ☑ | ☐ | `t_11_04_etat_services_reels_ok` | Succès | 0 |
| ☑ | ☐ | `t_11_05_etat_pool_arrete_ok` | Succès | 0 |

### Jalon 12 - Arrêt des applications

| Créé | Validé | Scénario | Résultat attendu | Code |
|:---:|:---:|---|---|:---:|
| ☑ | ☐ | `t_12_01_arret_taskflow_processus_ok` | Succès | 0 |
| ☑ | ☐ | `t_12_02_arret_runners_multiples_ok` | Succès | 0 |
| ☑ | ☐ | `t_12_03_arret_composant_deja_arrete_ok` | Succès | 0 |
| ☑ | ☐ | `t_12_04_confirmation_non_interactive_ko` | Annulation | 2 |
| ☑ | ☐ | `t_12_05_composant_non_selectionne_intact_ok` | Succès | 0 |
| ☑ | ☐ | `t_12_06_arret_service_taskflow_ok` | Succès | 0 |
| ☑ | ☐ | `t_12_07_arret_pool_iis_ok` | Succès | 0 |
| ☑ | ☐ | `t_12_08_arret_hpclite_ordre_ok` | Succès | 0 |
| ☑ | ☐ | `t_12_09_arret_services_deja_arretes_ok` | Succès | 0 |

### Jalon 13 - Redémarrage des applications

| Créé | Validé | Scénario | Résultat attendu | Code |
|:---:|:---:|---|---|:---:|
| ☑ | ☐ | `t_13_01_redemarrage_taskflow_ok` | Succès | 0 |
| ☑ | ☐ | `t_13_02_redemarrage_pool_ok` | Succès | 0 |
| ☑ | ☐ | `t_13_03_redemarrage_hpclite_ordre_ok` | Succès | 0 |
| ☑ | ☐ | `t_13_04_service_arrete_avant_reste_arrete_ok` | Succès | 0 |
| ☑ | ☐ | `t_13_05_pool_arrete_avant_reste_arrete_ok` | Succès | 0 |
| ☑ | ☐ | `t_13_06_runners_non_redemarres_ok` | Succès | 0 |
| ☑ | ☐ | `t_13_07_tous_composants_ok` | Succès | 0 |
| ☑ | ☐ | `t_13_08_redemarrage_mode_test_ok` | Succès | 0 |

### Jalon 14 - Sauvegarde des fichiers

| Créé | Validé | Scénario | Résultat attendu | Code |
|:---:|:---:|---|---|:---:|
| ☑ | ☐ | `t_14_01_sauvegarde_stx_ok` | Succès | 0 |
| ☑ | ☐ | `t_14_02_sauvegarde_tous_ok` | Succès | 0 |
| ☑ | ☐ | `t_14_03_sauvegardes_precedentes_non_ecrasees_ok` | Succès | 0 |
| ☑ | ☐ | `t_14_04_chemin_sauvegarde_journalise_ok` | Succès | 0 |
| ☑ | ☐ | `t_14_05_sauvegarde_mode_test_ok` | Succès | 0 |

### Jalon 15 - Installation des fichiers

| Créé | Validé | Scénario | Résultat attendu | Code |
|:---:|:---:|---|---|:---:|
| ☑ | ☐ | `t_15_01_installation_stx_ok` | Succès | 0 |
| ☑ | ☐ | `t_15_02_installation_stp_ok` | Succès | 0 |
| ☑ | ☐ | `t_15_03_installation_stj_ok` | Succès | 0 |
| ☑ | ☐ | `t_15_04_nombre_fichiers_conforme_ok` | Succès | 0 |
| ☑ | ☐ | `t_15_05_fichiers_conserves_ok` | Succès | 0 |
| ☑ | ☐ | `t_15_06_installation_mode_test_ok` | Succès | 0 |

### Jalon 16 - Rollback

| Créé | Validé | Scénario | Résultat attendu | Code |
|:---:|:---:|---|---|:---:|
| ☑ | ☐ | `t_16_01_erreur_apres_arret_ko` | Échec contrôlé | 1 |
| ☑ | ☐ | `t_16_02_erreur_apres_sauvegarde_ko` | Échec contrôlé | 1 |
| ☑ | ☐ | `t_16_03_erreur_apres_installation_un_composant_ko` | Échec contrôlé | 1 |
| ☑ | ☐ | `t_16_04_erreur_apres_plusieurs_composants_ko` | Échec contrôlé | 1 |
| ☑ | ☐ | `t_16_05_erreur_pendant_redemarrage_ko` | Échec contrôlé | 1 |
| ☑ | ☐ | `t_16_06_rollback_mode_test_ko` | Échec contrôlé | 1 |

### Jalon 17 - Test complet par composant

| Créé | Validé | Scénario | Résultat attendu | Code |
|:---:|:---:|---|---|:---:|
| ☑ | ☐ | `t_17_01_stx_complet_ok` | Succès | 0 |
| ☑ | ☐ | `t_17_02_stp_complet_ok` | Succès | 0 |
| ☑ | ☐ | `t_17_03_stj_complet_ok` | Succès | 0 |

### Jalon 18 - Test des combinaisons

| Créé | Validé | Scénario | Résultat attendu | Code |
|:---:|:---:|---|---|:---:|
| ☑ | ☐ | `t_18_01_stp_stx_ok` | Succès | 0 |
| ☑ | ☐ | `t_18_02_stp_stj_ok` | Succès | 0 |
| ☑ | ☐ | `t_18_03_stx_stj_ok` | Succès | 0 |
| ☑ | ☐ | `t_18_04_tous_ok` | Succès | 0 |
| ☑ | ☐ | `t_18_05_composant_non_selectionne_intact_ok` | Succès | 0 |
| ☑ | ☐ | `t_18_06_rollback_combinaison_ko` | Échec contrôlé | 1 |

### Jalon 19 - Validation en conditions réelles

| Créé | Validé | Scénario | Résultat attendu | Code |
|:---:|:---:|---|---|:---:|
| ☑ | ☐ | `t_19_01_preflight_validation_only_ok` | Succès | 0 |
| ☑ | ☐ | `t_19_02_controles_post_deploiement_ok` | Succès | 0 |

---

## 13. Critères de validation d'un jalon

Un jalon est validé lorsque :

1. tous ses scénarios sont créés ;
2. tous ses scénarios ont été exécutés ;
3. les cas `_ok` réussissent ;
4. les cas `_ko` échouent de manière contrôlée ;
5. les messages sont compréhensibles ;
6. les codes de sortie sont corrects ;
7. les tests sont reproductibles : relancés, ils donnent le même résultat ;
8. aucun secret n'est exposé ;
9. aucun effet indésirable ne subsiste après les tests ;
10. la version de `download_deploy.ps1` testée (et son `CHANGEMENTS.md`) est archivée.

Le jalon suivant ne doit être commencé qu'après validation du jalon courant.

---

## 14. Historique des validations

| Date | Jalon | Version du script | Machine | Résultat | Validé par |
|---|---|---|---|---|---|
| À compléter | Jalon 0 | À compléter | À compléter | À compléter | À compléter |

---

## Rappel

Le but de ces tests n'est pas seulement de vérifier que le script fonctionne dans le cas
normal. Ils vérifient aussi qu'il :

- refuse une demande incorrecte ;
- s'arrête avant toute action dangereuse ;
- explique clairement la cause d'une erreur ;
- ne révèle aucun secret ;
- respecte l'état initial des applications ;
- restaure les fichiers en cas d'échec.
