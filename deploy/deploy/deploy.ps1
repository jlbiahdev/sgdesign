#requires -Version 5.1

<#
.SYNOPSIS
    Déploie les applications Styx sur le serveur local, à partir de
    fichiers déjà extraits dans D:\.deploy.

.DESCRIPTION
    Script de déploiement livré à l'équipe de production.

    Le package Styx a été récupéré et extrait AVANT l'exécution de ce
    script, dans le dossier source (par défaut D:\.deploy) :

        D:\.deploy\api\
        D:\.deploy\taskflow\
        D:\.deploy\hpclite\{agent, runner, scheduler}\

    Chaque application est sur son propre serveur, sauf HpcLite dont les
    trois composants (Agent, Runner, Scheduler) sont déployés ensemble.
    En pratique, ce script est lancé par :
        deploy-api.ps1       (équivaut à deploy.ps1 -STX)
        deploy-taskflow.ps1  (équivaut à deploy.ps1 -STP)
        deploy-hpclite.ps1   (équivaut à deploy.ps1 -STJ)

    Étapes :
      J0   vérifie le serveur : droits administrateur, lecteur D:,
           IIS (appcmd.exe) si l'API est demandée ;
      J1   affiche la demande reçue (paramètres) ;
      J2   crée le journal dans <d>\deployment-logs ;
      J3   valide la demande : au moins un trigramme, -d complet, sur D:,
           existant ;
      J4   vérifie les dossiers et exécutables des applications en place ;
      J5   vérifie le dossier source (nouveaux fichiers) ;
      J7   contrôle le contenu source de chaque application demandée ;
      J8   prépare un « staging » : copie complète des nouveaux fichiers
           dans <d>\.staging, AVANT tout arrêt ;
      J9   vérifie les services Windows et compte les processus ;
      J10  lit l'état du pool IIS de l'API ;
      J11  mémorise l'état initial (state.json) ;
           -> -ValidationOnly s'arrête ici ; sinon confirmation « DEPLOYER » ;
      J12  arrête les applications sélectionnées ;
      J14  sauvegarde les dossiers actuels dans <d>\.rollback ;
      J15  installe les nouveaux fichiers ;
      J13  redémarre les applications qui fonctionnaient avant, puis
           vérifie qu'elles restent démarrées (contrôle de stabilité) ;
      J16  en cas d'erreur après l'arrêt : rollback automatique (tous les
           composants déjà modifiés, Agent + Runner + Scheduler ensemble
           pour HpcLite) puis redémarrage de l'état initial.

    Associations trigramme > dossiers :
      -STP  Taskflow  : D:\.deploy\taskflow  > <d>\taskflow   (service Windows)
      -STX  API (IIS) : D:\.deploy\api       > <d>\api        (pool IIS)
      -STJ  HpcLite   : D:\.deploy\hpclite   > <d>\HpcLite\{agent|runner|scheduler}
                        Agent et Scheduler : services Windows
                        Runners : processus lancés par l'Agent

    Les Runners en cours sont arrêtés brutalement et ne sont pas relancés
    par le script : l'Agent en recrée selon les jobs présents en base.
    Les utilisateurs doivent avoir été prévenus avant le déploiement.

.PARAMETER DestinationRoot
    Alias : -d. Racine contenant taskflow, api et HpcLite.
    Doit être un chemin complet, sur le lecteur D:, et exister.
    Exemple : D:\Applications

.PARAMETER SourceRoot
    Dossier contenant les nouveaux fichiers déjà extraits (api, taskflow,
    hpclite). Par défaut : D:\.deploy. Il n'est jamais modifié.

.PARAMETER STP
    Déploie Taskflow.

.PARAMETER STX
    Déploie l'API (IIS).

.PARAMETER STJ
    Déploie HpcLite (Agent, Runner, Scheduler).

.PARAMETER ValidationOnly
    Exécute toutes les vérifications et le staging, enregistre l'état
    initial, puis s'arrête avant toute action destructive. Aucune
    application n'est arrêtée.

.PARAMETER Force
    Supprime la confirmation interactive « DEPLOYER ». À réserver aux
    exécutions automatisées.

.PARAMETER KeepTemporaryFiles
    Conserve le dossier de travail (<d>\.staging\...) pour diagnostic.

.EXAMPLE
    # Pré-vol : tout est vérifié, rien n'est arrêté.
    .\deploy.ps1 -d "D:\Applications" -STX -ValidationOnly

.EXAMPLE
    # Déploiement de l'API (équivaut à .\deploy-api.ps1 -d "D:\Applications").
    .\deploy.ps1 -d "D:\Applications" -STX

.EXAMPLE
    # Nouveaux fichiers placés ailleurs que dans D:\.deploy.
    .\deploy.ps1 -d "D:\Applications" -STJ -SourceRoot "D:\Livraisons\Styx-1.2.3"

.NOTES
    Exécution : en tant qu'administrateur, avec Windows PowerShell 5.1.

    PowerShell utilise un seul tiret : -STP -STX -STJ.

    Codes de sortie :
      0  déploiement ou validation terminé avec succès
      1  erreur détectée par le script (avec rollback si nécessaire)
      2  annulation volontaire (confirmation refusée ou impossible)

    Encodage : enregistrer ce fichier en « UTF-8 avec BOM ». Sans BOM,
    Windows PowerShell 5.1 le lit en ANSI et les accents sont corrompus.

    Les commentaires « # [POINT-DE-TEST:nom] » sont de simples
    commentaires, sans effet. Ils servent aux tests automatisés.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [Alias("d")]
    [string] $DestinationRoot,

    [Parameter()]
    [string] $SourceRoot = "D:\.deploy",

    [Parameter()] [switch] $STP,
    [Parameter()] [switch] $STX,
    [Parameter()] [switch] $STJ,

    [Parameter()] [switch] $ValidationOnly,
    [Parameter()] [switch] $Force,
    [Parameter()] [switch] $KeepTemporaryFiles
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# >>> DEBUT CONFIGURATION
# ============================================================
# CONFIGURATION À ADAPTER UNE SEULE FOIS
# ============================================================
#
# Vérifier attentivement ces valeurs avant la première utilisation
# en production.
#
# Règle de format (importante pour les tests) : une valeur par ligne,
# sous la forme « $Nom = valeur ». Les lanceurs de test remplacent
# certaines de ces lignes dans une copie temporaire du script.
# ============================================================

# Lecteur obligatoire pour la destination, le journal, le staging et
# les sauvegardes.
$RequiredDrive = "D:\"

# Nom exact du pool IIS qui héberge l'API STX.
$StxApplicationPoolName = "styx-api"

# Exécutable Taskflow, relatif à <d>\taskflow. Une seule instance autorisée.
$TaskflowExecutableRelativePath = "Socgen.TaskFlow.Runner.exe"

# Dossiers HpcLite, relatifs à <d>\HpcLite.
$HpcLiteAgentFolder = "agent"
$HpcLiteRunnerFolder = "runner"
$HpcLiteSchedulerFolder = "scheduler"

# Exécutables HpcLite, relatifs à leur dossier.
$HpcLiteAgentExecutableName = "Styx.HpcLite.Agent.exe"
$HpcLiteRunnerExecutableName = "Styx.HpcLite.Runner.exe"
$HpcLiteSchedulerExecutableName = "Styx.HpcLite.Scheduler.exe"

# Sous-dossiers du dossier source (-SourceRoot) contenant les nouveaux
# fichiers de chaque application.
$SourceFolderSTP = "taskflow"
$SourceFolderSTX = "api"
$SourceFolderSTJ = "hpclite"

# $true  : production. Taskflow, l'Agent et le Scheduler sont pilotés par
#          le gestionnaire de services (Stop-Service / Start-Service).
#          Tuer le processus d'un service déclencherait ses options de
#          récupération : il pourrait redémarrer pendant le déploiement.
# $false : réservé aux tests avec des exécutables factices ; arrêt brutal
#          et redémarrage par Start-Process.
$UseWindowsServices = $true

# Noms des services Windows (colonne « Nom du service » de services.msc).
# Attention : « TaskFlow.Runner » est le service de Taskflow (STP), à ne
# pas confondre avec les Runners HpcLite.
$TaskflowServiceName = "TaskFlow.Runner"
$HpcLiteAgentServiceName = "HpcLite.Agent"
$HpcLiteSchedulerServiceName = "HpcLite.Scheduler"

# Délai de stabilité (secondes) après chaque démarrage. Une application
# peut démarrer puis s'arrêter quelques secondes plus tard (configuration
# invalide, port déjà utilisé...). Après ce délai, le service (ou le
# processus) doit TOUJOURS fonctionner ; sinon c'est une erreur, et le
# rollback est déclenché. 0 désactive ce contrôle.
$StartupStabilitySeconds = 10

# Arguments de démarrage, utilisés seulement si $UseWindowsServices = $false.
$TaskflowStartArguments = @()
$HpcLiteAgentStartArguments = @()
$HpcLiteSchedulerStartArguments = @()

# Fichiers propres au serveur, conservés d'une version à l'autre.
# Chemins relatifs au dossier du composant (<d>\taskflow, <d>\api,
# <d>\HpcLite). Ils sont recopiés depuis la sauvegarde après installation.
# Exemple : $PreservedRelativePathsSTJ = @("agent\appsettings.Production.json")
$PreservedRelativePathsSTP = @()
$PreservedRelativePathsSTX = @()
$PreservedRelativePathsSTJ = @()

# Délais maximum (secondes) pour constater un arrêt ou un démarrage.
$ProcessTimeoutSeconds = 30
$ServiceTimeoutSeconds = 60
$IisTimeoutSeconds = 60

# Outil d'administration IIS.
$AppCmdPath = Join-Path $env:WINDIR "System32\inetsrv\appcmd.exe"

# <<< FIN CONFIGURATION

# ============================================================
# VARIABLES INTERNES
# ============================================================

# Chemin du journal ; $null tant que le dossier racine n'est pas validé.
$script:LogFile = $null

# Lignes écrites avant la création du journal : elles y sont recopiées
# dès sa création, pour que le fichier contienne tout l'historique.
$script:PendingLogLines = [System.Collections.Generic.List[string]]::new()

# Composants dont le dossier a été déplacé en sauvegarde. Sert au rollback.
$script:ChangedComponents = [System.Collections.ArrayList]::new()

# Initialisée ici pour que le bloc finally fonctionne même si l'erreur
# survient très tôt (Set-StrictMode interdit les variables non définies).
$workingDirectory = $null


# ============================================================
# AFFICHAGE ET JOURNAL
# ============================================================

<#
.SYNOPSIS
    Écrit un message horodaté dans la console (en couleur) et dans le journal.
.DESCRIPTION
    Format : [yyyy-MM-dd HH:mm:ss] [NIVEAU] message
    Avant la création du journal, les lignes sont mises en attente puis
    recopiées dans le fichier par Set-LogFile.
    Ne jamais passer de secret à cette fonction.
#>
function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Message,

        [ValidateSet("INFO", "OK", "ATTENTION", "ERREUR")]
        [string] $Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] [$Level] $Message"

    switch ($Level) {
        "OK"        { Write-Host $line -ForegroundColor Green }
        "ATTENTION" { Write-Host $line -ForegroundColor Yellow }
        "ERREUR"    { Write-Host $line -ForegroundColor Red }
        default     { Write-Host $line }
    }

    if ([string]::IsNullOrWhiteSpace($script:LogFile)) {
        $script:PendingLogLines.Add($line)
        return
    }

    Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
}

<#
.SYNOPSIS
    Affiche un titre d'étape encadré et l'écrit dans le journal.
#>
function Write-Step {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Title
    )

    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host $Title -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor Cyan

    Write-Log -Message $Title
}

<#
.SYNOPSIS
    Crée le fichier journal et y recopie les lignes en attente.
.DESCRIPTION
    Échoue (exception) si le fichier ne peut pas être écrit : un
    déploiement sans journal n'est pas acceptable.
#>
function Set-LogFile {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    Set-Content -LiteralPath $Path -Value $script:PendingLogLines -Encoding UTF8 -ErrorAction Stop

    $script:LogFile = $Path
    $script:PendingLogLines.Clear()
}

# ============================================================
# VALIDATIONS GÉNÉRALES (J0, J3, J4)
# ============================================================

<#
.SYNOPSIS
    Vérifie que la console est ouverte en tant qu'administrateur. (J0)
#>
function Assert-Administrator {
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)

    $isAdministrator = $principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )

    if (-not $isAdministrator) {
        throw @"
Ce script doit être exécuté en tant qu'administrateur.

Fermez cette fenêtre, puis :
1. faites un clic droit sur PowerShell ;
2. choisissez « Exécuter en tant qu'administrateur » ;
3. relancez la commande.
"@
    }

    Write-Log -Message "Console administrateur : oui." -Level "OK"
}

<#
.SYNOPSIS
    Vérifie que le serveur dispose de ce dont le script a besoin. (J0)
.DESCRIPTION
    - version de PowerShell (garantie par #requires, journalisée ici) ;
    - lecteur obligatoire ($RequiredDrive) ;
    - appcmd.exe (IIS), si l'API est demandée (-STX).
#>
function Assert-ServerCompatibility {
    Write-Log -Message "Version de PowerShell : $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))." -Level "OK"

    if (-not (Test-Path -LiteralPath $RequiredDrive -PathType Container)) {
        throw @"
Le lecteur $RequiredDrive est introuvable sur ce serveur.

Le déploiement exige ce lecteur pour les applications, le journal,
les fichiers temporaires et les sauvegardes.
"@
    }

    Write-Log -Message "Lecteur $RequiredDrive disponible." -Level "OK"

    if ($STX) {
        Assert-ExistingFile -Path $AppCmdPath -Description "Outil d'administration IIS appcmd.exe"
        Write-Log -Message "IIS (appcmd.exe) disponible : $AppCmdPath" -Level "OK"
    }
}

<#
.SYNOPSIS
    Valide la racine -d et la renvoie sous forme normalisée. (J3)
.DESCRIPTION
    Refuse : chemin vide, relatif, « D: » sans antislash, situé sur un
    autre lecteur que $RequiredDrive, inexistant. Ne crée jamais le dossier.
#>
function Get-ValidatedDestinationRoot {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string] $Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw "Le paramètre -d est vide."
    }

    # « D: » seul est accepté par IsPathRooted mais désigne le dossier
    # courant du lecteur : on exige un chemin du type D:\...
    if (-not [IO.Path]::IsPathRooted($Path) -or $Path -notmatch '^[A-Za-z]:\\') {
        throw @"
La destination doit être un chemin Windows complet.

Chemin reçu :
$Path

Exemple correct :
D:\Applications
"@
    }

    try {
        $fullPath = [IO.Path]::GetFullPath($Path)
    }
    catch {
        throw "Le chemin de destination n'est pas valide : $Path"
    }

    $root = [IO.Path]::GetPathRoot($fullPath)

    if (-not $root.Equals($RequiredDrive, [StringComparison]::OrdinalIgnoreCase)) {
        throw @"
Le dossier de destination doit obligatoirement être situé sur le lecteur $RequiredDrive

Chemin reçu :
$fullPath

Lecteur détecté :
$root
"@
    }

    if (-not (Test-Path -LiteralPath $fullPath -PathType Container)) {
        throw @"
Le dossier fourni avec -d n'existe pas.

Dossier recherché :
$fullPath

Le script ne crée pas automatiquement ce dossier.
"@
    }

    $resolvedPath = (Resolve-Path -LiteralPath $fullPath -ErrorAction Stop).ProviderPath

    # On ne retire pas le "\" si le chemin est simplement D:\.
    if ($resolvedPath.Length -gt 3) {
        $resolvedPath = $resolvedPath.TrimEnd("\")
    }

    # Un lien symbolique pourrait pointer ailleurs : on revérifie.
    $resolvedRoot = [IO.Path]::GetPathRoot($resolvedPath)

    if (-not $resolvedRoot.Equals($RequiredDrive, [StringComparison]::OrdinalIgnoreCase)) {
        throw @"
Après résolution, le dossier ne se trouve pas sur $RequiredDrive

Dossier résolu :
$resolvedPath
"@
    }

    return $resolvedPath
}

<#
.SYNOPSIS
    Échoue avec un message clair si le dossier n'existe pas.
#>
function Assert-ExistingDirectory {
    param(
        [Parameter(Mandatory = $true)] [string] $Path,
        [Parameter(Mandatory = $true)] [string] $Description
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw @"
$Description introuvable.

Dossier attendu :
$Path

Le déploiement est annulé avant l'arrêt des applications.
"@
    }
}

<#
.SYNOPSIS
    Échoue avec un message clair si le fichier n'existe pas.
#>
function Assert-ExistingFile {
    param(
        [Parameter(Mandatory = $true)] [string] $Path,
        [Parameter(Mandatory = $true)] [string] $Description
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw @"
$Description introuvable.

Fichier attendu :
$Path

Vérifiez le nom configuré au début du script.
"@
    }
}

<#
.SYNOPSIS
    Compte les fichiers d'un dossier, sous-dossiers compris.
#>
function Get-FileCount {
    param(
        [Parameter(Mandatory = $true)] [string] $Path
    )

    return @(Get-ChildItem -LiteralPath $Path -File -Recurse -Force).Count
}

# ============================================================
# IDENTIFICATION DES PROCESSUS (J9, J12)
# ============================================================

<#
.SYNOPSIS
    Renvoie les processus dont l'exécutable est exactement ce chemin.
.DESCRIPTION
    Win32_Process fournit le chemin complet : on n'arrête jamais par erreur
    une autre application portant le même nom ailleurs sur le disque.
#>
function Get-ProcessesByExecutablePath {
    param(
        [Parameter(Mandatory = $true)]
        [string] $ExecutablePath
    )

    $expectedPath = [IO.Path]::GetFullPath($ExecutablePath)

    $processes = @(
        Get-CimInstance -ClassName Win32_Process -ErrorAction Stop |
            Where-Object {
                -not [string]::IsNullOrWhiteSpace($_.ExecutablePath) -and
                $_.ExecutablePath.Equals($expectedPath, [StringComparison]::OrdinalIgnoreCase)
            }
    )

    return $processes
}

<#
.SYNOPSIS
    Échoue si plus d'une instance est détectée (Taskflow, Agent, Scheduler).
.DESCRIPTION
    [AllowEmptyCollection()] est indispensable : sans lui, PowerShell refuse
    un tableau vide sur un paramètre obligatoire, et le script échouerait dès
    qu'une application est arrêtée.
#>
function Assert-SingleProcessMaximum {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]] $Processes,

        [Parameter(Mandatory = $true)]
        [string] $ComponentName
    )

    if ($Processes.Count -gt 1) {
        $processIds = $Processes.ProcessId -join ", "

        throw @"
Anomalie détectée pour $ComponentName.

Une seule instance au maximum est autorisée.
Nombre d'instances détectées : $($Processes.Count)
Identifiants des processus : $processIds

Aucun processus n'a été arrêté.
Le déploiement est annulé.
"@
    }
}

<#
.SYNOPSIS
    Arrête brutalement tous les processus lancés depuis cet exécutable.
.DESCRIPTION
    Utilisé pour les Runners HpcLite, et pour tout composant en mode test
    ($UseWindowsServices = $false). Attend la disparition effective des
    processus ($ProcessTimeoutSeconds).
#>
function Stop-ProcessesByExecutablePath {
    param(
        [Parameter(Mandatory = $true)] [string] $ExecutablePath,
        [Parameter(Mandatory = $true)] [string] $ComponentName,
        [Parameter()] [switch] $SingleInstance
    )

    $processes = @(Get-ProcessesByExecutablePath -ExecutablePath $ExecutablePath)

    if ($SingleInstance) {
        Assert-SingleProcessMaximum -Processes $processes -ComponentName $ComponentName
    }

    if ($processes.Count -eq 0) {
        Write-Log -Message "$ComponentName : aucun processus en cours. Aucune action nécessaire."
        return
    }

    Write-Log -Message "$ComponentName : $($processes.Count) processus à arrêter."

    foreach ($process in $processes) {
        Write-Log -Message "Arrêt brutal de $ComponentName, PID $($process.ProcessId)."

        # Le processus peut s'être terminé entre la détection et l'arrêt.
        Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
    }

    $deadline = (Get-Date).AddSeconds($ProcessTimeoutSeconds)

    do {
        Start-Sleep -Milliseconds 500
        $remainingProcesses = @(Get-ProcessesByExecutablePath -ExecutablePath $ExecutablePath)
    }
    while ($remainingProcesses.Count -gt 0 -and (Get-Date) -lt $deadline)

    if ($remainingProcesses.Count -gt 0) {
        $remainingIds = $remainingProcesses.ProcessId -join ", "

        throw @"
Impossible d'arrêter complètement $ComponentName.

Processus encore présents :
$remainingIds
"@
    }

    Write-Log -Message "$ComponentName est maintenant arrêté." -Level "OK"
}

<#
.SYNOPSIS
    Démarre un exécutable (mode test uniquement) et attend son processus.
#>
function Start-Executable {
    param(
        [Parameter(Mandatory = $true)] [string] $ExecutablePath,
        [Parameter(Mandatory = $true)] [string] $ComponentName,
        [Parameter()] [string[]] $Arguments = @(),
        [Parameter()] [switch] $SingleInstance
    )

    Assert-ExistingFile -Path $ExecutablePath -Description "Exécutable de $ComponentName"

    $existingProcesses = @(Get-ProcessesByExecutablePath -ExecutablePath $ExecutablePath)

    if ($SingleInstance) {
        Assert-SingleProcessMaximum -Processes $existingProcesses -ComponentName $ComponentName
    }

    if ($existingProcesses.Count -gt 0) {
        Write-Log -Message "$ComponentName fonctionne déjà. Aucun nouveau processus ne sera créé." -Level "ATTENTION"
        return
    }

    Write-Log -Message "Démarrage de $ComponentName depuis $ExecutablePath."

    $startParameters = @{
        FilePath         = $ExecutablePath
        WorkingDirectory = (Split-Path -Parent -Path $ExecutablePath)
        WindowStyle      = "Hidden"
        ErrorAction      = "Stop"
    }

    if ($Arguments.Count -gt 0) {
        $startParameters["ArgumentList"] = $Arguments
    }

    Start-Process @startParameters | Out-Null

    $deadline = (Get-Date).AddSeconds($ProcessTimeoutSeconds)

    do {
        Start-Sleep -Milliseconds 500
        $startedProcesses = @(Get-ProcessesByExecutablePath -ExecutablePath $ExecutablePath)
    }
    while ($startedProcesses.Count -eq 0 -and (Get-Date) -lt $deadline)

    if ($startedProcesses.Count -eq 0) {
        throw @"
Le démarrage de $ComponentName a échoué.

Aucun processus n'a été détecté après le démarrage de :
$ExecutablePath
"@
    }

    if ($SingleInstance) {
        Assert-SingleProcessMaximum -Processes $startedProcesses -ComponentName $ComponentName
    }

    # Contrôle de stabilité (voir $StartupStabilitySeconds).
    if ($StartupStabilitySeconds -gt 0) {
        Write-Log -Message "Contrôle de stabilité de $ComponentName ($StartupStabilitySeconds s)."
        Start-Sleep -Seconds $StartupStabilitySeconds

        if (@(Get-ProcessesByExecutablePath -ExecutablePath $ExecutablePath).Count -eq 0) {
            throw @"
$ComponentName a démarré puis s'est arrêté (plus aucun processus après
$StartupStabilitySeconds s).

Exécutable :
$ExecutablePath
"@
        }
    }

    Write-Log -Message "$ComponentName a démarré correctement." -Level "OK"
}

# ============================================================
# SERVICES WINDOWS : TASKFLOW, AGENT, SCHEDULER (J9, J12, J13)
# ============================================================

<#
.SYNOPSIS
    Renvoie le service Windows, ou échoue clairement s'il n'existe pas.
#>
function Get-ServiceSafe {
    param(
        [Parameter(Mandatory = $true)] [string] $ServiceName,
        [Parameter(Mandatory = $true)] [string] $ComponentName
    )

    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue

    if ($null -eq $service) {
        throw @"
Le service Windows de $ComponentName est introuvable.

Nom du service :
$ServiceName

Vérifiez la configuration au début du script.
"@
    }

    return $service
}

<#
.SYNOPSIS
    Vérifie qu'un service existe ET exécute l'exécutable du dossier -d. (J9)
.DESCRIPTION
    Si le service lançait un exécutable situé ailleurs, remplacer les
    fichiers de -d n'aurait aucun effet sur l'application réelle : on
    s'arrête avant toute action.
#>
function Assert-ServiceConfiguration {
    param(
        [Parameter(Mandatory = $true)] [AllowEmptyString()] [string] $ServiceName,
        [Parameter(Mandatory = $true)] [string] $ComponentName,
        [Parameter(Mandatory = $true)] [string] $ExpectedExecutablePath
    )

    if ([string]::IsNullOrWhiteSpace($ServiceName)) {
        throw @"
Le nom du service Windows de $ComponentName n'est pas configuré.

Renseignez-le au début du script (section CONFIGURATION).
"@
    }

    Get-ServiceSafe -ServiceName $ServiceName -ComponentName $ComponentName | Out-Null

    $cimService = Get-CimInstance `
        -ClassName Win32_Service `
        -Filter "Name = '$($ServiceName.Replace("'", "''"))'" `
        -ErrorAction Stop

    # PathName : "D:\...\App.exe" --args   ou   D:\...\App.exe --args
    $pathName = $cimService.PathName.Trim()

    if ($pathName.StartsWith('"')) {
        $serviceExecutable = $pathName.Substring(1, $pathName.IndexOf('"', 1) - 1)
    }
    else {
        $exeIndex = $pathName.IndexOf(".exe", [StringComparison]::OrdinalIgnoreCase)
        $serviceExecutable = if ($exeIndex -ge 0) { $pathName.Substring(0, $exeIndex + 4) } else { $pathName }
    }

    $expected = [IO.Path]::GetFullPath($ExpectedExecutablePath)

    if (-not [IO.Path]::GetFullPath($serviceExecutable).Equals($expected, [StringComparison]::OrdinalIgnoreCase)) {
        throw @"
Le service $ComponentName ('$ServiceName') n'exécute pas l'exécutable attendu.

Exécutable du service :
$serviceExecutable

Exécutable attendu (dossier de déploiement) :
$expected

Vérifiez -d et les noms configurés au début du script.
"@
    }

    Write-Log -Message "Service $ComponentName ('$ServiceName') trouvé et cohérent avec la destination." -Level "OK"
}

<#
.SYNOPSIS
    Arrête un service et attend l'état Stopped.
#>
function Stop-ServiceSafe {
    param(
        [Parameter(Mandatory = $true)] [string] $ServiceName,
        [Parameter(Mandatory = $true)] [string] $ComponentName
    )

    $service = Get-ServiceSafe -ServiceName $ServiceName -ComponentName $ComponentName

    if ($service.Status -eq "Stopped") {
        Write-Log -Message "Le service $ComponentName ('$ServiceName') est déjà arrêté."
        return
    }

    Write-Log -Message "Arrêt du service $ComponentName ('$ServiceName')."

    Stop-Service -Name $ServiceName -Force -ErrorAction Stop

    try {
        $service.WaitForStatus(
            [ServiceProcess.ServiceControllerStatus]::Stopped,
            [TimeSpan]::FromSeconds($ServiceTimeoutSeconds)
        )
    }
    catch {
        throw "Le service $ComponentName ('$ServiceName') ne s'est pas arrêté dans le délai imparti."
    }

    Write-Log -Message "Le service $ComponentName est arrêté." -Level "OK"
}

<#
.SYNOPSIS
    Démarre un service et attend l'état Running.
#>
function Start-ServiceSafe {
    param(
        [Parameter(Mandatory = $true)] [string] $ServiceName,
        [Parameter(Mandatory = $true)] [string] $ComponentName
    )

    $service = Get-ServiceSafe -ServiceName $ServiceName -ComponentName $ComponentName

    if ($service.Status -eq "Running") {
        Write-Log -Message "Le service $ComponentName ('$ServiceName') fonctionne déjà."
        return
    }

    Write-Log -Message "Démarrage du service $ComponentName ('$ServiceName')."

    Start-Service -Name $ServiceName -ErrorAction Stop

    try {
        $service.WaitForStatus(
            [ServiceProcess.ServiceControllerStatus]::Running,
            [TimeSpan]::FromSeconds($ServiceTimeoutSeconds)
        )
    }
    catch {
        throw "Le service $ComponentName ('$ServiceName') n'a pas démarré dans le délai imparti."
    }

    # Contrôle de stabilité : le service doit toujours fonctionner après
    # $StartupStabilitySeconds secondes (voir CONFIGURATION).
    if ($StartupStabilitySeconds -gt 0) {
        Write-Log -Message "Contrôle de stabilité du service $ComponentName ($StartupStabilitySeconds s)."
        Start-Sleep -Seconds $StartupStabilitySeconds
        $service.Refresh()

        if ($service.Status -ne [ServiceProcess.ServiceControllerStatus]::Running) {
            throw @"
Le service $ComponentName ('$ServiceName') a démarré puis s'est arrêté
(état après $StartupStabilitySeconds s : $($service.Status)).

Causes fréquentes : configuration invalide, port déjà utilisé, base de
données inaccessible. Consultez le journal de l'application et
l'Observateur d'événements Windows (journaux Application et Système).
"@
        }
    }

    Write-Log -Message "Le service $ComponentName fonctionne." -Level "OK"
}

<#
.SYNOPSIS
    Arrête un composant à instance unique (Taskflow, Agent, Scheduler).
.DESCRIPTION
    Production : arrêt par le gestionnaire de services, puis contrôle
    qu'aucun processus ne subsiste depuis cet exécutable.
    Mode test : arrêt brutal du processus.
#>
function Stop-SingleComponent {
    param(
        [Parameter(Mandatory = $true)] [string] $ExecutablePath,
        [Parameter(Mandatory = $true)] [string] $ComponentName,
        [Parameter()] [string] $ServiceName
    )

    if ($UseWindowsServices) {
        Stop-ServiceSafe -ServiceName $ServiceName -ComponentName $ComponentName
    }

    Stop-ProcessesByExecutablePath -ExecutablePath $ExecutablePath -ComponentName $ComponentName -SingleInstance
}

<#
.SYNOPSIS
    Démarre un composant à instance unique (Taskflow, Agent, Scheduler).
#>
function Start-SingleComponent {
    param(
        [Parameter(Mandatory = $true)] [string] $ExecutablePath,
        [Parameter(Mandatory = $true)] [string] $ComponentName,
        [Parameter()] [string] $ServiceName,
        [Parameter()] [string[]] $Arguments = @()
    )

    if ($UseWindowsServices) {
        Start-ServiceSafe -ServiceName $ServiceName -ComponentName $ComponentName

        $processes = @(Get-ProcessesByExecutablePath -ExecutablePath $ExecutablePath)
        Assert-SingleProcessMaximum -Processes $processes -ComponentName $ComponentName
        return
    }

    Start-Executable -ExecutablePath $ExecutablePath -ComponentName $ComponentName -Arguments $Arguments -SingleInstance
}

<#
.SYNOPSIS
    Indique si un composant à instance unique fonctionne actuellement.
.DESCRIPTION
    Production : état du service (Running). Mode test : présence d'un processus.
#>
function Test-SingleComponentRunning {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]] $Processes,

        [Parameter(Mandatory = $true)] [string] $ComponentName,
        [Parameter()] [string] $ServiceName
    )

    if ($UseWindowsServices) {
        $service = Get-ServiceSafe -ServiceName $ServiceName -ComponentName $ComponentName
        return ($service.Status -eq "Running")
    }

    return ($Processes.Count -gt 0)
}

# ============================================================
# POOL IIS DE L'API (J10, J12, J13)
# ============================================================

<#
.SYNOPSIS
    Vérifie que le pool IIS configuré existe. (J10)
#>
function Assert-IisConfiguration {
    param(
        [Parameter(Mandatory = $true)]
        [string] $ApplicationPoolName
    )

    Assert-ExistingFile -Path $AppCmdPath -Description "Outil d'administration IIS appcmd.exe"

    $output     = & $AppCmdPath list apppool "/apppool.name:$ApplicationPoolName" 2>&1
    $exitCode   = $LASTEXITCODE
    $outputText = $output -join [Environment]::NewLine

    if ($exitCode -ne 0 -or [string]::IsNullOrWhiteSpace($outputText)) {
        throw @"
Le pool IIS configuré pour l'API est introuvable.

Nom du pool :
$ApplicationPoolName

Vérifiez la variable StxApplicationPoolName au début du script.
"@
    }

    Write-Log -Message "Pool IIS '$ApplicationPoolName' trouvé." -Level "OK"
}

<#
.SYNOPSIS
    Renvoie Started, Stopped ou Unknown pour le pool IIS.
#>
function Get-IisApplicationPoolState {
    param(
        [Parameter(Mandatory = $true)]
        [string] $ApplicationPoolName
    )

    $output = & $AppCmdPath list apppool "/apppool.name:$ApplicationPoolName" 2>&1

    if ($LASTEXITCODE -ne 0) {
        throw "Impossible de lire l'état du pool IIS '$ApplicationPoolName'."
    }

    $text = $output -join " "

    if ($text -match "state:Started") { return "Started" }
    if ($text -match "state:Stopped") { return "Stopped" }

    # Sortie inattendue : on ne prétend pas connaître une information incertaine.
    return "Unknown"
}

<#
.SYNOPSIS
    Attend la fin du processus w3wp.exe du pool.
.DESCRIPTION
    Un pool à l'état Stopped peut encore avoir un w3wp.exe en cours
    d'arrêt qui verrouille les fichiers de l'API.
#>
function Wait-IisWorkerProcessExit {
    param(
        [Parameter(Mandatory = $true)]
        [string] $ApplicationPoolName
    )

    $pattern  = "*-ap `"$ApplicationPoolName`"*"
    $deadline = (Get-Date).AddSeconds($IisTimeoutSeconds)

    do {
        $workers = @(
            Get-CimInstance -ClassName Win32_Process -Filter "Name = 'w3wp.exe'" -ErrorAction Stop |
                Where-Object { $null -ne $_.CommandLine -and $_.CommandLine -like $pattern }
        )

        if ($workers.Count -eq 0) {
            return
        }

        Start-Sleep -Seconds 1
    }
    while ((Get-Date) -lt $deadline)

    $workerIds = $workers.ProcessId -join ", "
    throw "Le processus IIS (w3wp.exe) du pool '$ApplicationPoolName' ne s'est pas terminé. PID : $workerIds"
}

<#
.SYNOPSIS
    Arrête le pool IIS (jamais IIS entier) et attend la fin de son w3wp.
#>
function Stop-IisApplicationPoolSafe {
    param(
        [Parameter(Mandatory = $true)]
        [string] $ApplicationPoolName
    )

    $state = Get-IisApplicationPoolState -ApplicationPoolName $ApplicationPoolName

    if ($state -eq "Stopped") {
        Write-Log -Message "Le pool IIS '$ApplicationPoolName' est déjà arrêté."
        Wait-IisWorkerProcessExit -ApplicationPoolName $ApplicationPoolName
        return
    }

    Write-Log -Message "Arrêt du pool IIS '$ApplicationPoolName'."

    $output = & $AppCmdPath stop apppool "/apppool.name:$ApplicationPoolName" 2>&1

    if ($LASTEXITCODE -ne 0) {
        throw @"
Impossible d'arrêter le pool IIS '$ApplicationPoolName'.

Message IIS :
$($output -join [Environment]::NewLine)
"@
    }

    $deadline = (Get-Date).AddSeconds($IisTimeoutSeconds)

    do {
        Start-Sleep -Seconds 1
        $state = Get-IisApplicationPoolState -ApplicationPoolName $ApplicationPoolName
    }
    while ($state -ne "Stopped" -and (Get-Date) -lt $deadline)

    if ($state -ne "Stopped") {
        throw "Le pool IIS '$ApplicationPoolName' ne s'est pas arrêté."
    }

    Wait-IisWorkerProcessExit -ApplicationPoolName $ApplicationPoolName

    Write-Log -Message "Le pool IIS '$ApplicationPoolName' est arrêté." -Level "OK"
}

<#
.SYNOPSIS
    Démarre le pool IIS et attend l'état Started.
#>
function Start-IisApplicationPoolSafe {
    param(
        [Parameter(Mandatory = $true)]
        [string] $ApplicationPoolName
    )

    $state = Get-IisApplicationPoolState -ApplicationPoolName $ApplicationPoolName

    if ($state -eq "Started") {
        Write-Log -Message "Le pool IIS '$ApplicationPoolName' fonctionne déjà."
        return
    }

    Write-Log -Message "Démarrage du pool IIS '$ApplicationPoolName'."

    $output = & $AppCmdPath start apppool "/apppool.name:$ApplicationPoolName" 2>&1

    if ($LASTEXITCODE -ne 0) {
        throw @"
Impossible de démarrer le pool IIS '$ApplicationPoolName'.

Message IIS :
$($output -join [Environment]::NewLine)
"@
    }

    $deadline = (Get-Date).AddSeconds($IisTimeoutSeconds)

    do {
        Start-Sleep -Seconds 1
        $state = Get-IisApplicationPoolState -ApplicationPoolName $ApplicationPoolName
    }
    while ($state -ne "Started" -and (Get-Date) -lt $deadline)

    if ($state -ne "Started") {
        throw "Le pool IIS '$ApplicationPoolName' n'a pas redémarré."
    }

    Write-Log -Message "Le pool IIS '$ApplicationPoolName' fonctionne." -Level "OK"
}

# ============================================================
# STAGING (J8)
# ============================================================

<#
.SYNOPSIS
    Copie le contenu d'un dossier et vérifie le nombre de fichiers. (J8)
.OUTPUTS
    Nombre de fichiers copiés.
#>
function Copy-DirectoryContent {
    param(
        [Parameter(Mandatory = $true)] [string] $Source,
        [Parameter(Mandatory = $true)] [string] $Destination
    )

    New-Item -Path $Destination -ItemType Directory -Force | Out-Null

    Get-ChildItem -LiteralPath $Source -Force |
        Copy-Item -Destination $Destination -Recurse -Force -ErrorAction Stop

    $sourceCount  = Get-FileCount -Path $Source
    $stagingCount = Get-FileCount -Path $Destination

    if ($sourceCount -ne $stagingCount) {
        throw "La préparation des fichiers est incomplète ($stagingCount / $sourceCount fichiers copiés)."
    }

    return $sourceCount
}

# ============================================================
# ARRÊT ET DÉMARRAGE DES APPLICATIONS (J12, J13)
# ============================================================

<#
.SYNOPSIS
    Arrête les applications sélectionnées. (J12)
.DESCRIPTION
    Ordre HpcLite : Agent (pour qu'il ne crée plus de Runners), puis
    Scheduler, puis tous les Runners.
#>
function Stop-SelectedApplications {
    param(
        [Parameter(Mandatory = $true)]
        [object] $Paths
    )

    if ($STP) {
        Write-Step "Arrêt de Taskflow"

        Stop-SingleComponent -ExecutablePath $Paths.TaskflowExecutable -ComponentName "Taskflow" -ServiceName $TaskflowServiceName
    }

    if ($STX) {
        Write-Step "Arrêt de l'API STX sous IIS"

        Stop-IisApplicationPoolSafe -ApplicationPoolName $StxApplicationPoolName
    }

    if ($STJ) {
        Write-Step "Arrêt de HpcLite"

        Stop-SingleComponent -ExecutablePath $Paths.AgentExecutable -ComponentName "HpcLite Agent" -ServiceName $HpcLiteAgentServiceName

        Stop-SingleComponent -ExecutablePath $Paths.SchedulerExecutable -ComponentName "HpcLite Scheduler" -ServiceName $HpcLiteSchedulerServiceName

        # Zéro, un ou plusieurs Runners : tous sont arrêtés.
        Stop-ProcessesByExecutablePath -ExecutablePath $Paths.RunnerExecutable -ComponentName "HpcLite Runner"

        Write-Log -Message "Tous les processus HpcLite concernés sont arrêtés." -Level "OK"
    }
}

<#
.SYNOPSIS
    Redémarre ce qui fonctionnait avant le déploiement. (J13)
.DESCRIPTION
    Un composant arrêté avant le déploiement reste arrêté.
    Ordre HpcLite : Scheduler, puis Agent. Les Runners ne sont jamais
    redémarrés par le script : l'Agent les recrée.
#>
function Start-PreviouslyRunningApplications {
    param(
        [Parameter(Mandatory = $true)] [object] $Paths,
        [Parameter(Mandatory = $true)] [object] $PreviousState
    )

    if ($STP) {
        if ($PreviousState.TaskflowWasRunning) {
            Write-Step "Redémarrage de Taskflow"

            Start-SingleComponent -ExecutablePath $Paths.TaskflowExecutable -ComponentName "Taskflow" -ServiceName $TaskflowServiceName -Arguments $TaskflowStartArguments
        }
        else {
            Write-Log -Message "Taskflow était arrêté avant le déploiement. Il reste arrêté." -Level "ATTENTION"
        }
    }

    if ($STX) {
        if ($PreviousState.ApiWasRunning) {
            Write-Step "Redémarrage de l'API STX"

            Start-IisApplicationPoolSafe -ApplicationPoolName $StxApplicationPoolName
        }
        else {
            Write-Log -Message "Le pool IIS STX était arrêté avant le déploiement. Il reste arrêté." -Level "ATTENTION"
        }
    }

    # [POINT-DE-TEST:pendant-redemarrage]

    if ($STJ) {
        Write-Step "Redémarrage de HpcLite"

        if ($PreviousState.SchedulerWasRunning) {
            Start-SingleComponent -ExecutablePath $Paths.SchedulerExecutable -ComponentName "HpcLite Scheduler" -ServiceName $HpcLiteSchedulerServiceName -Arguments $HpcLiteSchedulerStartArguments
        }
        else {
            Write-Log -Message "Le Scheduler était arrêté avant le déploiement. Il reste arrêté." -Level "ATTENTION"
        }

        if ($PreviousState.AgentWasRunning) {
            Start-SingleComponent -ExecutablePath $Paths.AgentExecutable -ComponentName "HpcLite Agent" -ServiceName $HpcLiteAgentServiceName -Arguments $HpcLiteAgentStartArguments
        }
        else {
            Write-Log -Message "L'Agent était arrêté avant le déploiement. Il reste arrêté." -Level "ATTENTION"
        }

        Write-Log -Message "Les Runners ne sont pas redémarrés directement par le script."
        Write-Log -Message "L'Agent pourra créer de nouveaux Runners selon les jobs présents en base."
    }
}

# ============================================================
# SAUVEGARDE, INSTALLATION ET ROLLBACK (J14, J15, J16)
# ============================================================

<#
.SYNOPSIS
    Déplace le dossier actuel d'un composant dans la sauvegarde. (J14)
.DESCRIPTION
    Move-Item d'un dossier ne fonctionne qu'au sein d'un même volume :
    la sauvegarde est donc sur D:, comme la destination.
    Le déplacement est enregistré immédiatement pour le rollback, puis le
    nombre de fichiers sauvegardés est contrôlé.
#>
function Backup-Component {
    param(
        [Parameter(Mandatory = $true)] [string] $Trigram,
        [Parameter(Mandatory = $true)] [string] $Destination,
        [Parameter(Mandatory = $true)] [string] $Backup
    )

    Assert-ExistingDirectory -Path $Destination -Description "Destination du composant $Trigram"

    if (Test-Path -LiteralPath $Backup) {
        throw "Une sauvegarde existe déjà à cet emplacement, elle ne sera pas écrasée : $Backup"
    }

    $fileCount = Get-FileCount -Path $Destination

    New-Item -Path (Split-Path -Parent -Path $Backup) -ItemType Directory -Force | Out-Null

    Write-Log -Message "Sauvegarde de $Trigram."
    Write-Log -Message "Ancien dossier : $Destination"
    Write-Log -Message "Sauvegarde     : $Backup"

    Move-Item -LiteralPath $Destination -Destination $Backup -ErrorAction Stop

    # Enregistré immédiatement : si la suite échoue, le rollback sait quoi faire.
    [void] $script:ChangedComponents.Add(
        [pscustomobject] @{
            Trigram     = $Trigram
            Destination = $Destination
            Backup      = $Backup
        }
    )

    $backupCount = Get-FileCount -Path $Backup

    if ($backupCount -ne $fileCount) {
        throw "Sauvegarde de $Trigram incomplète : $backupCount fichiers sur $fileCount."
    }

    Write-Log -Message "Sauvegarde de $Trigram vérifiée : $backupCount fichiers." -Level "OK"
}

<#
.SYNOPSIS
    Installe les nouveaux fichiers d'un composant depuis le staging. (J15)
.DESCRIPTION
    Le dossier de staging (sur D:) est déplacé vers la destination, puis
    les fichiers propres au serveur ($PreservedRelativePaths<TRI>) sont
    recopiés depuis la sauvegarde.
#>
function Install-Component {
    param(
        [Parameter(Mandatory = $true)] [string] $Trigram,
        [Parameter(Mandatory = $true)] [string] $Source,
        [Parameter(Mandatory = $true)] [string] $Destination,
        [Parameter(Mandatory = $true)] [string] $Backup
    )

    Assert-ExistingDirectory -Path $Source -Description "Staging du composant $Trigram"

    $stagingCount = Get-FileCount -Path $Source

    Write-Log -Message "Installation des nouveaux fichiers de $Trigram."

    try {
        Move-Item -LiteralPath $Source -Destination $Destination -ErrorAction Stop
    }
    catch {
        throw @"
Impossible d'installer les nouveaux fichiers de $Trigram.

Source :
$Source

Destination :
$Destination

Détail :
$($_.Exception.Message)
"@
    }

    $preservedPaths = @((Get-Variable -Name "PreservedRelativePaths$Trigram" -ValueOnly))

    foreach ($relativePath in $preservedPaths) {
        if ([string]::IsNullOrWhiteSpace($relativePath)) { continue }

        $preservedSource = Join-Path $Backup $relativePath
        $preservedTarget = Join-Path $Destination $relativePath

        if (Test-Path -LiteralPath $preservedSource -PathType Leaf) {
            New-Item -Path (Split-Path -Parent $preservedTarget) -ItemType Directory -Force | Out-Null
            Copy-Item -LiteralPath $preservedSource -Destination $preservedTarget -Force -ErrorAction Stop
            Write-Log -Message "Fichier conservé depuis l'ancienne version : $relativePath"
        }
        else {
            Write-Log -Message "Fichier à conserver absent de l'ancienne version : $relativePath" -Level "ATTENTION"
        }
    }

    $installedCount = Get-FileCount -Path $Destination

    if ($installedCount -lt $stagingCount) {
        throw "Installation de $Trigram incomplète : $installedCount fichiers pour $stagingCount attendus."
    }

    Write-Log -Message "$Trigram a été installé correctement : $installedCount fichiers." -Level "OK"
}

<#
.SYNOPSIS
    Restaure les dossiers sauvegardés, dans l'ordre inverse. (J16)
.OUTPUTS
    $true si tout a été restauré (ou s'il n'y avait rien à restaurer),
    $false si au moins une restauration a échoué.
.DESCRIPTION
    Chaque composant restauré est retiré de la liste : un second appel ne
    refait rien. Une erreur sur un composant n'empêche pas les suivants.
#>
function Invoke-Rollback {
    if ($script:ChangedComponents.Count -eq 0) {
        Write-Log -Message "Aucun dossier n'a été remplacé. Aucun rollback nécessaire." -Level "ATTENTION"
        return $true
    }

    Write-Step "ROLLBACK : restauration des anciens fichiers"

    $allRestored = $true

    for ($index = $script:ChangedComponents.Count - 1; $index -ge 0; $index--) {
        $component = $script:ChangedComponents[$index]

        try {
            Write-Log -Message "Restauration de $($component.Trigram)."

            if (-not (Test-Path -LiteralPath $component.Backup -PathType Container)) {
                throw "Le dossier de sauvegarde est introuvable : $($component.Backup)"
            }

            if (Test-Path -LiteralPath $component.Destination) {
                Remove-Item -LiteralPath $component.Destination -Recurse -Force -ErrorAction Stop
            }

            Move-Item -LiteralPath $component.Backup -Destination $component.Destination -ErrorAction Stop

            $script:ChangedComponents.RemoveAt($index)

            Write-Log -Message "$($component.Trigram) a été restauré." -Level "OK"
        }
        catch {
            $allRestored = $false
            Write-Log -Message "Échec du rollback de $($component.Trigram) : $($_.Exception.Message)" -Level "ERREUR"
        }
    }

    return $allRestored
}

# ============================================================
# PROGRAMME PRINCIPAL
# ============================================================

try {
    Write-Host ""
    Write-Host "Déploiement Styx - version V0" -ForegroundColor Cyan
    Write-Host "Ce script va remplacer des applications par les fichiers de $SourceRoot."
    Write-Host ""

    # --------------------------------------------------------
    # J0 - Compatibilité du serveur
    # --------------------------------------------------------

    Write-Step "[J0] Compatibilité du serveur"

    Assert-Administrator
    Assert-ServerCompatibility

    # --------------------------------------------------------
    # J1 - Paramètres reçus
    # --------------------------------------------------------

    Write-Step "[J1] Paramètres reçus"

    Write-Log -Message "Destination demandée (-d) : $DestinationRoot"
    Write-Log -Message "STP demandé : $STP"
    Write-Log -Message "STX demandé : $STX"
    Write-Log -Message "STJ demandé : $STJ"

    Write-Log -Message "Dossier source (-SourceRoot) : $SourceRoot"

    Write-Log -Message "Validation seule (-ValidationOnly) : $ValidationOnly"
    Write-Log -Message "Sans confirmation (-Force) : $Force"
    Write-Log -Message "Conserver les fichiers temporaires : $KeepTemporaryFiles"

    # --------------------------------------------------------
    # [J3] Au moins une application demandée
    # --------------------------------------------------------

    if (-not ($STP -or $STX -or $STJ)) {
        throw @"
Aucune application n'a été sélectionnée.

Ajoutez au moins un des paramètres suivants :
-STP  pour Taskflow
-STX  pour l'API
-STJ  pour HpcLite

Exemple :
.\deploy.ps1 -d "D:\Applications" -STX
"@
    }

    # --------------------------------------------------------
    # [J2] Journal
    # --------------------------------------------------------
    # Le journal est créé dans <d>\deployment-logs : -d est donc validé
    # dès ce jalon (lecteur, chemin complet, existence).

    $DestinationRoot = Get-ValidatedDestinationRoot -Path $DestinationRoot

    Write-Step "[J2] Journal"

    $logDirectory = Join-Path $DestinationRoot "deployment-logs"

    try {
        New-Item -Path $logDirectory -ItemType Directory -Force -ErrorAction Stop | Out-Null

        $deploymentTimestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $deploymentId        = [Guid]::NewGuid().ToString("N")

        Set-LogFile -Path (Join-Path $logDirectory "deployment-$deploymentTimestamp-$($deploymentId.Substring(0, 8)).log")
    }
    catch {
        throw @"
Impossible de créer le journal du déploiement.

Dossier attendu :
$logDirectory

Détail :
$($_.Exception.Message)
"@
    }

    Write-Log -Message "Journal créé : $($script:LogFile)" -Level "OK"

    # [POINT-DE-TEST:apres-journal]

    # --------------------------------------------------------
    # J3 - Synthèse de la demande validée
    # --------------------------------------------------------

    Write-Step "[J3] Vérification de la demande"

    Write-Log -Message "Identifiant du déploiement : $deploymentId"
    Write-Log -Message "Dossier racine valide : $DestinationRoot" -Level "OK"
    Write-Log -Message "Applications demandées : $((@('STP', 'STX', 'STJ') | Where-Object { Get-Variable -Name $_ -ValueOnly }) -join ', ')" -Level "OK"

    # --------------------------------------------------------
    # J4 - Destinations
    # --------------------------------------------------------

    Write-Step "[J4] Vérification des dossiers de destination"

    $taskflowDestination  = Join-Path $DestinationRoot "taskflow"
    $apiDestination       = Join-Path $DestinationRoot "api"
    $hpcLiteDestination   = Join-Path $DestinationRoot "HpcLite"

    $agentDestination     = Join-Path $hpcLiteDestination $HpcLiteAgentFolder
    $runnerDestination    = Join-Path $hpcLiteDestination $HpcLiteRunnerFolder
    $schedulerDestination = Join-Path $hpcLiteDestination $HpcLiteSchedulerFolder

    $paths = [pscustomobject] @{
        TaskflowExecutable  = Join-Path $taskflowDestination  $TaskflowExecutableRelativePath
        AgentExecutable     = Join-Path $agentDestination     $HpcLiteAgentExecutableName
        RunnerExecutable    = Join-Path $runnerDestination    $HpcLiteRunnerExecutableName
        SchedulerExecutable = Join-Path $schedulerDestination $HpcLiteSchedulerExecutableName
    }

    # Seules les applications demandées sont contrôlées : -STX ne doit pas
    # échouer parce que taskflow est absent.
    if ($STP) {
        Assert-ExistingDirectory -Path $taskflowDestination -Description "Destination STP / Taskflow"
        Assert-ExistingFile -Path $paths.TaskflowExecutable -Description "Exécutable Taskflow"
        Write-Log -Message "Destination STP valide : $taskflowDestination" -Level "OK"
    }

    if ($STX) {
        Assert-ExistingDirectory -Path $apiDestination -Description "Destination STX / API"
        Write-Log -Message "Destination STX valide : $apiDestination" -Level "OK"
    }

    if ($STJ) {
        Assert-ExistingDirectory -Path $hpcLiteDestination   -Description "Destination STJ / HpcLite"
        Assert-ExistingDirectory -Path $agentDestination     -Description "Destination HpcLite Agent"
        Assert-ExistingDirectory -Path $runnerDestination    -Description "Destination HpcLite Runner"
        Assert-ExistingDirectory -Path $schedulerDestination -Description "Destination HpcLite Scheduler"

        Assert-ExistingFile -Path $paths.AgentExecutable     -Description "Exécutable HpcLite Agent"
        Assert-ExistingFile -Path $paths.RunnerExecutable    -Description "Exécutable HpcLite Runner"
        Assert-ExistingFile -Path $paths.SchedulerExecutable -Description "Exécutable HpcLite Scheduler"

        Write-Log -Message "Destination STJ valide : $hpcLiteDestination" -Level "OK"
    }

    # --------------------------------------------------------
    # J5 - Dossier source (nouveaux fichiers déjà extraits)
    # --------------------------------------------------------

    Write-Step "[J5] Dossier source"

    if (-not [IO.Path]::IsPathRooted($SourceRoot)) {
        throw "Le dossier source (-SourceRoot) doit être un chemin complet : $SourceRoot"
    }

    $SourceRoot = [IO.Path]::GetFullPath($SourceRoot).TrimEnd("\")

    Assert-ExistingDirectory -Path $SourceRoot -Description "Dossier source des nouveaux fichiers (-SourceRoot)"

    if ($SourceRoot.Equals($DestinationRoot.TrimEnd("\"), [StringComparison]::OrdinalIgnoreCase)) {
        throw "Le dossier source et la destination (-d) sont identiques : $SourceRoot"
    }

    Write-Log -Message "Dossier source trouvé : $SourceRoot" -Level "OK"

    # Le dossier de travail est sur la même racine que les destinations :
    # Move-Item ne sait pas déplacer un dossier d'un volume à un autre.
    $workingDirectory = Join-Path $DestinationRoot ".staging\$deploymentTimestamp-$deploymentId"
    $stagingDirectory = $workingDirectory

    New-Item -Path $stagingDirectory -ItemType Directory -Force | Out-Null

    Write-Log -Message "Dossier de travail : $workingDirectory"

    # --------------------------------------------------------
    # J7 - Contrôle du contenu source
    # --------------------------------------------------------

    Write-Step "[J7] Contrôle des nouveaux fichiers"

    $deploymentPlan = @()

    if ($STP) {
        $deploymentPlan += [pscustomobject] @{
            Trigram     = "STP"
            PackagePath = Join-Path $SourceRoot $SourceFolderSTP
            StagingPath = Join-Path $stagingDirectory "STP"
            Destination = $taskflowDestination
        }
    }

    if ($STX) {
        $deploymentPlan += [pscustomobject] @{
            Trigram     = "STX"
            PackagePath = Join-Path $SourceRoot $SourceFolderSTX
            StagingPath = Join-Path $stagingDirectory "STX"
            Destination = $apiDestination
        }
    }

    if ($STJ) {
        $deploymentPlan += [pscustomobject] @{
            Trigram     = "STJ"
            PackagePath = Join-Path $SourceRoot $SourceFolderSTJ
            StagingPath = Join-Path $stagingDirectory "STJ"
            Destination = $hpcLiteDestination
        }
    }

    # Seuls les contenus demandés sont contrôlés.
    foreach ($component in $deploymentPlan) {
        Assert-ExistingDirectory -Path $component.PackagePath -Description "Nouveaux fichiers $($component.Trigram) dans le dossier source"

        $fileCount = Get-FileCount -Path $component.PackagePath

        if ($fileCount -eq 0) {
            throw @"
Le dossier source $($component.Trigram) existe, mais il est vide.

Dossier contrôlé :
$($component.PackagePath)
"@
        }

        Write-Log -Message "Nouveaux fichiers $($component.Trigram) trouvés : $fileCount fichiers ($($component.PackagePath))." -Level "OK"
    }

    # --------------------------------------------------------
    # J8 - Staging
    # --------------------------------------------------------
    # Copie complète des nouveaux fichiers AVANT tout arrêt : on vérifie
    # qu'ils sont lisibles et complets pendant que les applications tournent.

    Write-Step "[J8] Préparation des nouveaux fichiers (staging)"

    foreach ($component in $deploymentPlan) {
        $copiedCount = Copy-DirectoryContent -Source $component.PackagePath -Destination $component.StagingPath
        Write-Log -Message "Staging $($component.Trigram) prêt : $copiedCount fichiers." -Level "OK"
    }

    # Les exécutables de la nouvelle version doivent exister.
    if ($STP) {
        Assert-ExistingFile -Path (Join-Path (Join-Path $stagingDirectory "STP") $TaskflowExecutableRelativePath) -Description "Nouvel exécutable Taskflow (nouveaux fichiers)"
    }

    if ($STJ) {
        $stjStaging = Join-Path $stagingDirectory "STJ"

        Assert-ExistingFile -Path (Join-Path (Join-Path $stjStaging $HpcLiteAgentFolder) $HpcLiteAgentExecutableName) -Description "Nouvel exécutable HpcLite Agent (nouveaux fichiers)"
        Assert-ExistingFile -Path (Join-Path (Join-Path $stjStaging $HpcLiteRunnerFolder) $HpcLiteRunnerExecutableName) -Description "Nouvel exécutable HpcLite Runner (nouveaux fichiers)"
        Assert-ExistingFile -Path (Join-Path (Join-Path $stjStaging $HpcLiteSchedulerFolder) $HpcLiteSchedulerExecutableName) -Description "Nouvel exécutable HpcLite Scheduler (nouveaux fichiers)"
    }

    Write-Log -Message "Nouveaux exécutables présents dans le staging." -Level "OK"

    # --------------------------------------------------------
    # J9 - Services Windows et processus
    # --------------------------------------------------------

    Write-Step "[J9] Services et processus en cours"

    $taskflowProcesses   = @()
    $agentProcesses      = @()
    $schedulerProcesses  = @()
    $runnerProcesses     = @()
    $taskflowWasRunning  = $false
    $agentWasRunning     = $false
    $schedulerWasRunning = $false

    if ($UseWindowsServices) {
        if ($STP) {
            Assert-ServiceConfiguration -ServiceName $TaskflowServiceName -ComponentName "Taskflow" -ExpectedExecutablePath $paths.TaskflowExecutable
        }

        if ($STJ) {
            Assert-ServiceConfiguration -ServiceName $HpcLiteAgentServiceName -ComponentName "HpcLite Agent" -ExpectedExecutablePath $paths.AgentExecutable
            Assert-ServiceConfiguration -ServiceName $HpcLiteSchedulerServiceName -ComponentName "HpcLite Scheduler" -ExpectedExecutablePath $paths.SchedulerExecutable
        }
    }
    else {
        Write-Log -Message "Mode test : services Windows ignorés, composants pilotés comme de simples processus." -Level "ATTENTION"
    }

    if ($STP) {
        $taskflowProcesses = @(Get-ProcessesByExecutablePath -ExecutablePath $paths.TaskflowExecutable)
        Assert-SingleProcessMaximum -Processes $taskflowProcesses -ComponentName "Taskflow"

        $taskflowWasRunning = Test-SingleComponentRunning -Processes $taskflowProcesses -ComponentName "Taskflow" -ServiceName $TaskflowServiceName

        Write-Log -Message "Taskflow : $($taskflowProcesses.Count) processus, démarré : $taskflowWasRunning."
    }

    if ($STJ) {
        $agentProcesses     = @(Get-ProcessesByExecutablePath -ExecutablePath $paths.AgentExecutable)
        $schedulerProcesses = @(Get-ProcessesByExecutablePath -ExecutablePath $paths.SchedulerExecutable)
        $runnerProcesses    = @(Get-ProcessesByExecutablePath -ExecutablePath $paths.RunnerExecutable)

        Assert-SingleProcessMaximum -Processes $agentProcesses     -ComponentName "HpcLite Agent"
        Assert-SingleProcessMaximum -Processes $schedulerProcesses -ComponentName "HpcLite Scheduler"

        # Volontairement aucun maximum pour les Runners.

        $agentWasRunning     = Test-SingleComponentRunning -Processes $agentProcesses -ComponentName "HpcLite Agent" -ServiceName $HpcLiteAgentServiceName
        $schedulerWasRunning = Test-SingleComponentRunning -Processes $schedulerProcesses -ComponentName "HpcLite Scheduler" -ServiceName $HpcLiteSchedulerServiceName

        Write-Log -Message "HpcLite Agent : $($agentProcesses.Count) processus, démarré : $agentWasRunning."
        Write-Log -Message "HpcLite Scheduler : $($schedulerProcesses.Count) processus, démarré : $schedulerWasRunning."
        Write-Log -Message "HpcLite Runner : $($runnerProcesses.Count) processus."
    }

    # --------------------------------------------------------
    # J10 - IIS
    # --------------------------------------------------------

    Write-Step "[J10] Pool IIS de l'API"

    $apiState = "NotSelected"

    if ($STX) {
        Assert-IisConfiguration -ApplicationPoolName $StxApplicationPoolName

        $apiState = Get-IisApplicationPoolState -ApplicationPoolName $StxApplicationPoolName

        if ($apiState -eq "Unknown") {
            throw "L'état du pool IIS '$StxApplicationPoolName' n'a pas pu être déterminé. Déploiement annulé."
        }

        Write-Log -Message "État actuel du pool IIS STX : $apiState"
    }
    else {
        Write-Log -Message "API non demandée : IIS n'est pas consulté."
    }

    # --------------------------------------------------------
    # J11 - État initial
    # --------------------------------------------------------

    Write-Step "[J11] Mémorisation de l'état initial"

    $previousState = [pscustomobject] @{
        TaskflowWasRunning  = $taskflowWasRunning
        ApiWasRunning       = $apiState -eq "Started"
        AgentWasRunning     = $agentWasRunning
        SchedulerWasRunning = $schedulerWasRunning
        RunnerCountBefore   = $runnerProcesses.Count
    }

    # Manifeste de l'état initial, à côté du journal. Jamais de secret dedans.
    $stateFile = [IO.Path]::ChangeExtension($script:LogFile, ".state.json")
    $previousState | ConvertTo-Json | Set-Content -LiteralPath $stateFile -Encoding UTF8

    Write-Log -Message "État initial enregistré : $stateFile" -Level "OK"

    if ($ValidationOnly) {
        Write-Log -Message "MODE VALIDATION : toutes les vérifications sont terminées." -Level "OK"
        Write-Log -Message "Aucune application n'a été arrêtée et aucun fichier n'a été remplacé." -Level "OK"
        exit 0
    }

    # --------------------------------------------------------
    # J12 - Confirmation
    # --------------------------------------------------------

    if (-not $Force) {
        Write-Host ""

        try {
            $confirmation = Read-Host "Tapez DEPLOYER pour arrêter les applications et continuer"
        }
        catch {
            # Session non interactive (planificateur, -NonInteractive...).
            Write-Log -Message "Confirmation impossible : la session n'est pas interactive. Utilisez -Force pour une exécution automatisée." -Level "ATTENTION"
            Write-Log -Message "Déploiement annulé. Aucune application n'a été arrêtée." -Level "ATTENTION"
            exit 2
        }

        if ($confirmation -cne "DEPLOYER") {
            Write-Log -Message "Déploiement annulé par l'utilisateur. Aucune application n'a été arrêtée." -Level "ATTENTION"
            exit 2
        }
    }

    Write-Log -Message "Les applications vont maintenant être arrêtées." -Level "ATTENTION"

    # --------------------------------------------------------
    # J12 à J15 - Arrêt, sauvegarde, installation, redémarrage
    # --------------------------------------------------------

    $backupRoot = Join-Path $DestinationRoot ".rollback\$deploymentTimestamp-$deploymentId"

    try {
        Write-Step "[J12] Arrêt des applications"

        Stop-SelectedApplications -Paths $paths

        # [POINT-DE-TEST:apres-arret]

        Write-Step "[J14] Sauvegarde et installation"

        New-Item -Path $backupRoot -ItemType Directory -Force | Out-Null

        foreach ($component in $deploymentPlan) {
            $backupPath = Join-Path $backupRoot $component.Trigram

            Backup-Component -Trigram $component.Trigram -Destination $component.Destination -Backup $backupPath

            # [POINT-DE-TEST:apres-sauvegarde]

            Install-Component -Trigram $component.Trigram -Source $component.StagingPath -Destination $component.Destination -Backup $backupPath

            # [POINT-DE-TEST:apres-installation-composant]
        }

        Write-Step "[J13] Redémarrage des applications"

        Start-PreviouslyRunningApplications -Paths $paths -PreviousState $previousState

    }
    catch {
        $deploymentError = $_

        Write-Log -Message "Le déploiement a échoué après l'arrêt des applications." -Level "ERREUR"
        Write-Log -Message $deploymentError.Exception.Message -Level "ERREUR"

        # On arrête les éventuels nouveaux processus avant de remettre les
        # anciens fichiers.
        try {
            Write-Log -Message "Arrêt des applications avant le rollback." -Level "ATTENTION"
            Stop-SelectedApplications -Paths $paths
        }
        catch {
            Write-Log -Message "Certaines applications n'ont pas pu être arrêtées avant le rollback : $($_.Exception.Message)" -Level "ERREUR"
        }

        $rollbackComplete = Invoke-Rollback

        if (-not $rollbackComplete) {
            Write-Log -Message "ROLLBACK INCOMPLET : intervention manuelle nécessaire. Sauvegardes : $backupRoot" -Level "ERREUR"
        }

        # On tente de remettre les applications dans leur état initial.
        try {
            Write-Step "Redémarrage après rollback"
            Start-PreviouslyRunningApplications -Paths $paths -PreviousState $previousState
        }
        catch {
            Write-Log -Message "Les fichiers sont en place, mais le redémarrage a échoué : $($_.Exception.Message)" -Level "ERREUR"
        }

        throw $deploymentError
    }

    # --------------------------------------------------------
    # J15 - Succès
    # --------------------------------------------------------

    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Green
    Write-Host "DÉPLOIEMENT TERMINÉ AVEC SUCCÈS" -ForegroundColor Green
    Write-Host ("=" * 60) -ForegroundColor Green

    Write-Log -Message "Déploiement terminé avec succès." -Level "OK"
    Write-Log -Message "Sauvegarde disponible dans : $backupRoot"
    Write-Log -Message "Journal disponible dans : $($script:LogFile)"

    if ($STJ -and $previousState.RunnerCountBefore -gt 0) {
        Write-Log -Message "$($previousState.RunnerCountBefore) Runner(s) ont été arrêtés brutalement." -Level "ATTENTION"
        Write-Log -Message "Ils n'ont pas été redémarrés directement par le script." -Level "ATTENTION"
    }

    exit 0
}
catch {
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Red
    Write-Host "LE DÉPLOIEMENT A ÉCHOUÉ" -ForegroundColor Red
    Write-Host ("=" * 60) -ForegroundColor Red

    Write-Log -Message $_.Exception.Message -Level "ERREUR"

    Write-Host ""
    Write-Host "Aucun autre déploiement ne doit être lancé avant d'avoir" -ForegroundColor Yellow
    Write-Host "compris et corrigé l'erreur ci-dessus." -ForegroundColor Yellow

    if (-not [string]::IsNullOrWhiteSpace($script:LogFile)) {
        Write-Host ""
        Write-Host "Journal à consulter :" -ForegroundColor Yellow
        Write-Host $script:LogFile -ForegroundColor Yellow
    }

    exit 1
}
finally {
    if (-not [string]::IsNullOrWhiteSpace($workingDirectory) -and (Test-Path -LiteralPath $workingDirectory)) {
        if ($KeepTemporaryFiles) {
            Write-Log -Message "Les fichiers temporaires sont conservés dans : $workingDirectory" -Level "ATTENTION"
        }
        else {
            Remove-Item -LiteralPath $workingDirectory -Recurse -Force -ErrorAction SilentlyContinue

            # Supprime aussi <d>\.staging s'il est vide. Le dossier source
            # (-SourceRoot) n'est jamais modifié.
            $deployRoot = Split-Path -Parent -Path $workingDirectory

            if ((Test-Path -LiteralPath $deployRoot) -and @(Get-ChildItem -LiteralPath $deployRoot -Force).Count -eq 0) {
                Remove-Item -LiteralPath $deployRoot -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
