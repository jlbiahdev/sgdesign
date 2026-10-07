#requires -Version 5.1

<#
.SYNOPSIS
    Télécharge un package Styx (NuGet) depuis Artifactory et déploie les
    applications sélectionnées sur le serveur local.

.DESCRIPTION
    Le script enchaîne les étapes ci-dessous. Chaque étape correspond à un
    jalon du plan de validation (voir README des tests) :

      J0   vérifie le serveur : droits administrateur, lecteur D:, curl.exe,
           IIS (appcmd.exe) si l'API est demandée ;
      J1   affiche la demande reçue (paramètres) ;
      J2   crée le journal dans <d>\deployment-logs ;
      J3   valide la demande : au moins un trigramme, -d complet, sur D:,
           existant ;
      J4   vérifie les dossiers et exécutables des applications demandées ;
      J5   identifie la source du package (fichier local, ou URL +
           identifiants Artifactory) ;
      J6   télécharge (ou copie) le package dans un dossier de travail sur D: ;
      J7   extrait le package et contrôle son contenu ;
      J8   prépare un « staging » : copie complète des nouveaux fichiers ;
      J9   vérifie les services Windows et compte les processus ;
      J10  lit l'état du pool IIS de l'API ;
      J11  mémorise l'état initial (state.json) ;
           -> -ValidationOnly s'arrête ici ; sinon confirmation « DEPLOYER » ;
      J12  arrête les applications sélectionnées ;
      J14  sauvegarde les dossiers actuels dans <d>\.rollback ;
      J15  installe les nouveaux fichiers ;
      J13  redémarre les applications qui fonctionnaient avant ;
      J16  en cas d'erreur après l'arrêt : rollback automatique puis
           redémarrage de l'état initial.

    Associations trigramme > dossier :
      -STP  Taskflow  > <d>\taskflow                      (service Windows)
      -STX  API (IIS) > <d>\api                           (pool IIS)
      -STJ  HpcLite   > <d>\HpcLite\{agent|runner|scheduler}
                        Agent et Scheduler : services Windows
                        Runners : processus lancés par l'Agent

    Taskflow, l'Agent et le Scheduler sont arrêtés et redémarrés par le
    gestionnaire de services Windows. Les Runners en cours sont arrêtés
    brutalement et ne sont pas relancés par le script : l'Agent en recrée
    selon les jobs présents en base. Les utilisateurs doivent avoir été
    prévenus avant le déploiement.

.PARAMETER DestinationRoot
    Alias : -d. Racine contenant taskflow, api et HpcLite.
    Doit être un chemin complet, sur le lecteur D:, et exister.
    Exemple : D:\Applications

.PARAMETER PackageUrl
    Adresse https complète du .nupkg dans Artifactory.
    À défaut, la variable d'environnement STYX_PACKAGE_URL est utilisée
    (session courante, puis niveau Machine).
    Incompatible avec -PackageFile.

.PARAMETER PackageFile
    Chemin d'un .nupkg déjà présent sur le serveur. Le téléchargement est
    alors sauté et aucun identifiant Artifactory n'est nécessaire.
    Utile hors ligne et pour les tests. Incompatible avec -PackageUrl.

.PARAMETER STP
    Déploie Taskflow.

.PARAMETER STX
    Déploie l'API (IIS).

.PARAMETER STJ
    Déploie HpcLite (Agent, Runner, Scheduler).

.PARAMETER ValidationOnly
    Exécute toutes les vérifications, le téléchargement, l'extraction et le
    staging, enregistre l'état initial, puis s'arrête avant toute action
    destructive. Aucune application n'est arrêtée.

.PARAMETER Force
    Supprime la confirmation interactive « DEPLOYER ». À réserver aux
    exécutions automatisées.

.PARAMETER KeepTemporaryFiles
    Conserve le dossier de travail (<d>\.deploy\...) pour diagnostic.

.EXAMPLE
    # Identifiants dans la session courante, URL en variable.
    $env:ARTIFACTORY_USERNAME = "usr-cd-..."
    $env:ARTIFACTORY_TOKEN    = "eyJ2..."
    $env:STYX_PACKAGE_URL     = "https://.../Styx.Publish.1.260807.162806.nupkg"

    .\download_deploy.ps1 -d "D:\Applications" -STP -STX -STJ

.EXAMPLE
    # URL passée en paramètre, API seule.
    .\download_deploy.ps1 -d "D:\Applications" `
        -PackageUrl "https://.../Styx.Publish.1.260807.162806.nupkg" -STX

.EXAMPLE
    # Package déjà présent sur le serveur.
    .\download_deploy.ps1 -d "D:\Applications" `
        -PackageFile "D:\Packages\Styx.Publish.1.260807.162806.nupkg" -STJ

.EXAMPLE
    # Pré-vol complet sans rien arrêter.
    .\download_deploy.ps1 -d "D:\Applications" -STP -STX -STJ -ValidationOnly

.NOTES
    Exécution : en tant qu'administrateur, avec Windows PowerShell 5.1.

    PowerShell utilise un seul tiret : -STP -STX -STJ.

    Les identifiants Artifactory ne doivent jamais être écrits dans ce
    fichier. Le token n'est jamais affiché, journalisé, ni passé en ligne
    de commande à curl.exe.

    Codes de sortie :
      0  déploiement, validation ou jalon de test terminé avec succès
      1  erreur détectée par le script (avec rollback si nécessaire)
      2  annulation volontaire (confirmation refusée ou impossible)

    Encodage : enregistrer ce fichier en « UTF-8 avec BOM ». Sans BOM,
    Windows PowerShell 5.1 le lit en ANSI et les accents sont corrompus.

    Tests :
      - Ce fichier est généré à partir de _outils\download_deploy.template.ps1.
        Les dossiers de test contiennent des versions PARTIELLES : la version
        du jalon N ne contient que le code des jalons 0 à N et se termine par
        « TEST TERMINÉ ». Ne pas modifier ce fichier directement : modifier
        le modèle puis lancer _outils\Build-JalonVersions.ps1.
      - Les commentaires « # [POINT-DE-TEST:nom] » sont de simples
        commentaires. Les lanceurs de test les remplacent, dans une COPIE
        temporaire du script, par une erreur volontaire (tests de rollback).
        Ils n'ont aucun effet en production.
#>

[CmdletBinding(DefaultParameterSetName = "FromUrl")]
param(
    [Parameter(Mandatory = $true)]
    [Alias("d")]
    [string] $DestinationRoot,

    [Parameter(ParameterSetName = "FromUrl")]
    [string] $PackageUrl,

    [Parameter(Mandatory = $true, ParameterSetName = "FromFile")]
    [string] $PackageFile,

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
$StxApplicationPoolName = "STYX"

# Exécutable Taskflow, relatif à <d>\taskflow. Une seule instance autorisée.
$TaskflowExecutableRelativePath = "Taskflow.exe"

# Dossiers HpcLite, relatifs à <d>\HpcLite.
$HpcLiteAgentFolder = "agent"
$HpcLiteRunnerFolder = "runner"
$HpcLiteSchedulerFolder = "scheduler"

# Exécutables HpcLite, relatifs à leur dossier.
$HpcLiteAgentExecutableName = "HpcLite.Agent.exe"
$HpcLiteRunnerExecutableName = "HpcLite.Runner.exe"
$HpcLiteSchedulerExecutableName = "HpcLite.Scheduler.exe"

# $true  : production. Taskflow, l'Agent et le Scheduler sont pilotés par
#          le gestionnaire de services (Stop-Service / Start-Service).
#          Tuer le processus d'un service déclencherait ses options de
#          récupération : il pourrait redémarrer pendant le déploiement.
# $false : réservé aux tests avec des exécutables factices ; arrêt brutal
#          et redémarrage par Start-Process.
$UseWindowsServices = $true

# Noms des services Windows (colonne « Nom du service » de services.msc).
# Attention : « TaskFlow Runner » est le service de Taskflow (STP), à ne
# pas confondre avec les Runners HpcLite.
$TaskflowServiceName = "TaskFlow Runner"
$HpcLiteAgentServiceName = "HpcLite Agent"
$HpcLiteSchedulerServiceName = "HpcLite Scheduler"

# Arguments de démarrage, utilisés seulement si $UseWindowsServices = $false.
$TaskflowStartArguments = @()
$HpcLiteAgentStartArguments = @()
$HpcLiteSchedulerStartArguments = @()

# Délais maximum (secondes) pour constater un arrêt ou un démarrage.
$ProcessTimeoutSeconds = 30
$ServiceTimeoutSeconds = 60
$IisTimeoutSeconds = 60

# Outils Windows utilisés.
# curl.exe est appelé explicitement : dans Windows PowerShell 5.1,
# « curl » est un alias d'Invoke-WebRequest.
$AppCmdPath = Join-Path $env:WINDIR "System32\inetsrv\appcmd.exe"
$CurlPath = Join-Path $env:WINDIR "System32\curl.exe"

# <<< FIN CONFIGURATION

# ============================================================
# VARIABLES INTERNES
# ============================================================

# Chemin du journal ; $null tant que le dossier racine n'est pas validé.
$script:LogFile = $null

# Lignes écrites avant la création du journal : elles y sont recopiées
# dès sa création, pour que le fichier contienne tout l'historique.
$script:PendingLogLines = [System.Collections.Generic.List[string]]::new()

# Initialisée ici pour que le bloc finally fonctionne même si l'erreur
# survient très tôt (Set-StrictMode interdit les variables non définies).
$workingDirectory = $null

# Source du package choisie par l'utilisateur.
$usePackageFile = $PSCmdlet.ParameterSetName -eq "FromFile"

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
    - curl.exe, sauf si le package est fourni localement (-PackageFile) ;
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

    if ($usePackageFile) {
        Write-Log -Message "Package local fourni : curl.exe n'est pas nécessaire."
    }
    else {
        Assert-ExistingFile -Path $CurlPath -Description "Outil de téléchargement curl.exe (Windows 10 / Server 2019 et ultérieurs)"
        Write-Log -Message "curl.exe disponible : $CurlPath" -Level "OK"
    }

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
# VARIABLES D'ENVIRONNEMENT (J5)
# ============================================================

<#
.SYNOPSIS
    Lit une variable d'environnement : session courante, puis Machine.
.DESCRIPTION
    Le niveau Machine est relu directement : une console ouverte avant la
    création de la variable ne la voit pas dans $env:.
    Renvoie $null si absente, sinon un objet { Value ; Source }.
    La valeur n'est jamais journalisée par l'appelant.
#>
function Get-ConfigurationValue {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name
    )

    $value  = [Environment]::GetEnvironmentVariable($Name, "Process")
    $source = "session"

    if ([string]::IsNullOrWhiteSpace($value)) {
        $value  = [Environment]::GetEnvironmentVariable($Name, "Machine")
        $source = "machine"
    }

    if ([string]::IsNullOrWhiteSpace($value)) {
        return $null
    }

    return [pscustomobject] @{
        Value  = $value
        Source = $source
    }
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
# TÉLÉCHARGEMENT, EXTRACTION ET STAGING (J6, J7, J8)
# ============================================================

<#
.SYNOPSIS
    Télécharge le package avec curl.exe. (J6)
.DESCRIPTION
    Équivalent de : curl -u utilisateur:token -L -o <fichier> <url>
    mais les identifiants sont transmis à curl par son entrée standard
    (--config -) et non en argument : la ligne de commande d'un processus
    est visible des autres utilisateurs (Gestionnaire des tâches).
#>
function Save-ArtifactoryPackage {
    param(
        [Parameter(Mandatory = $true)] [string] $Url,
        [Parameter(Mandatory = $true)] [string] $Username,
        [Parameter(Mandatory = $true)] [string] $Token,
        [Parameter(Mandatory = $true)] [string] $OutputFile
    )

    Assert-ExistingFile -Path $CurlPath -Description "Outil de téléchargement curl.exe"

    Write-Log -Message "Téléchargement du package depuis Artifactory (curl.exe)."
    Write-Log -Message "Adresse : $Url"

    # Format du fichier de configuration curl : user = "utilisateur:token"
    $escapedUser  = $Username.Replace('\', '\\').Replace('"', '\"')
    $escapedToken = $Token.Replace('\', '\\').Replace('"', '\"')
    $curlConfig   = "user = `"${escapedUser}:${escapedToken}`""

    $curlArguments = @(
        "--config", "-",            # identifiants lus sur l'entrée standard
        "--location",               # -L : suit les redirections Artifactory
        "--fail",                   # code de sortie 22 si HTTP >= 400
        "--silent", "--show-error",
        "--connect-timeout", "30",
        "--output", $OutputFile,
        "--write-out", '%{http_code}',
        $Url
    )

    # Avec Windows PowerShell 5.1, la sortie d'erreur d'un programme externe
    # redirigée par 2>&1 devient une erreur PowerShell, bloquante avec
    # $ErrorActionPreference = "Stop". On l'assouplit le temps de l'appel.
    $previousErrorActionPreference = $ErrorActionPreference

    try {
        $ErrorActionPreference = "Continue"
        $curlOutput   = @($curlConfig | & $CurlPath @curlArguments 2>&1)
        $curlExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference

        # On efface le secret dès que possible.
        $curlConfig   = $null
        $escapedToken = $null
    }

    $curlErrors = @($curlOutput | Where-Object { $_ -is [Management.Automation.ErrorRecord] })
    $httpCode   = (@($curlOutput | Where-Object { $_ -isnot [Management.Automation.ErrorRecord] }) -join "").Trim()

    if ($curlExitCode -ne 0) {
        Remove-Item -LiteralPath $OutputFile -Force -ErrorAction SilentlyContinue

        $hint = switch ($httpCode) {
            "401"   { "Identifiants refusés : vérifiez ARTIFACTORY_USERNAME et ARTIFACTORY_TOKEN." }
            "403"   { "Accès refusé : le compte n'a pas les droits sur ce dépôt." }
            "404"   { "Package introuvable : vérifiez l'adresse (version, nom du fichier)." }
            default { "Vérifiez l'adresse, le réseau et un éventuel proxy (code curl $curlExitCode)." }
        }

        # Les messages de curl ne contiennent pas le token.
        throw @"
Le téléchargement du package a échoué.

Code HTTP : $httpCode
$hint

Détail curl :
$(($curlErrors | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine)
"@
    }

    Write-Log -Message "Réponse HTTP : $httpCode"
    Assert-PackageFile -Path $OutputFile -Description "Package téléchargé"
}

<#
.SYNOPSIS
    Vérifie qu'un package existe, n'est pas vide, et journalise taille et
    empreinte SHA-256.
#>
function Assert-PackageFile {
    param(
        [Parameter(Mandatory = $true)] [string] $Path,
        [Parameter(Mandatory = $true)] [string] $Description
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Description : aucun fichier n'a été créé."
    }

    $file = Get-Item -LiteralPath $Path

    if ($file.Length -eq 0) {
        throw "$Description : le fichier est vide."
    }

    $hash = Get-FileHash -LiteralPath $Path -Algorithm SHA256

    Write-Log -Message "$Description : $($file.Length) octets." -Level "OK"
    Write-Log -Message "Empreinte SHA-256 : $($hash.Hash)"
}

<#
.SYNOPSIS
    Extrait un .nupkg (archive ZIP) dans un dossier. (J7)
.DESCRIPTION
    Extraction .NET plutôt qu'Expand-Archive :
    - NuGet encode certains caractères des noms (espace -> %20) : décodés ;
    - toute entrée qui sortirait du dossier cible est refusée (« zip slip »).
#>
function Expand-NuGetPackage {
    param(
        [Parameter(Mandatory = $true)] [string] $PackageFile,
        [Parameter(Mandatory = $true)] [string] $Destination
    )

    Write-Log -Message "Vérification et extraction du package."

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $destinationFull = [IO.Path]::GetFullPath($Destination).TrimEnd("\") + "\"

    try {
        $zip = [IO.Compression.ZipFile]::OpenRead($PackageFile)
    }
    catch {
        throw @"
Le package n'est pas une archive NuGet/ZIP valide.

Détail :
$($_.Exception.Message)
"@
    }

    $extractedCount = 0

    try {
        foreach ($entry in $zip.Entries) {
            $entryName = [Uri]::UnescapeDataString($entry.FullName)

            # Les entrées terminées par "/" sont des dossiers.
            if ($entryName.EndsWith("/") -or $entryName.EndsWith("\")) {
                continue
            }

            $relativePath = $entryName.Replace("/", "\")
            $targetPath   = [IO.Path]::GetFullPath((Join-Path $Destination $relativePath))

            if (-not $targetPath.StartsWith($destinationFull, [StringComparison]::OrdinalIgnoreCase)) {
                throw "Entrée suspecte dans le package (chemin hors du dossier d'extraction) : $entryName"
            }

            New-Item -Path (Split-Path -Parent -Path $targetPath) -ItemType Directory -Force | Out-Null

            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $targetPath, $true)
            $extractedCount++
        }
    }
    finally {
        $zip.Dispose()
    }

    Write-Log -Message "Package extrait correctement : $extractedCount fichiers." -Level "OK"
}

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
# PROGRAMME PRINCIPAL
# ============================================================

try {
    Write-Host ""
    Write-Host "Déploiement Styx - version V0" -ForegroundColor Cyan
    Write-Host "Ce script va télécharger et remplacer des applications."
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

    if ($usePackageFile) {
        Write-Log -Message "Source du package : fichier local ($PackageFile)"
    }
    elseif (-not [string]::IsNullOrWhiteSpace($PackageUrl)) {
        Write-Log -Message "Source du package : URL passée en paramètre"
    }
    else {
        Write-Log -Message "Source du package : variable STYX_PACKAGE_URL"
    }

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
.\download_deploy.ps1 -d "D:\Applications" -STX
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
    # J5 - Source du package et variables d'environnement
    # --------------------------------------------------------

    Write-Step "[J5] Source du package"

    $usernameSetting = $null
    $tokenSetting    = $null

    if ($usePackageFile) {
        if (-not [IO.Path]::IsPathRooted($PackageFile)) {
            throw "Le chemin du package (-PackageFile) doit être complet : $PackageFile"
        }

        $PackageFile = [IO.Path]::GetFullPath($PackageFile)

        Assert-ExistingFile -Path $PackageFile -Description "Package local (-PackageFile)"

        Write-Log -Message "Package local trouvé : $PackageFile" -Level "OK"
        Write-Log -Message "Aucun identifiant Artifactory n'est nécessaire."
    }
    else {
        $usernameSetting = Get-ConfigurationValue -Name "ARTIFACTORY_USERNAME"
        $tokenSetting    = Get-ConfigurationValue -Name "ARTIFACTORY_TOKEN"

        if ($null -eq $usernameSetting) {
            throw @"
Le nom d'utilisateur Artifactory est absent.

Définissez la variable ARTIFACTORY_USERNAME (niveau Machine en production,
ou `$env:ARTIFACTORY_USERNAME pour la session courante).
"@
        }

        if ($null -eq $tokenSetting) {
            throw @"
Le token Artifactory est absent.

Définissez la variable ARTIFACTORY_TOKEN (niveau Machine en production,
ou `$env:ARTIFACTORY_TOKEN pour la session courante).
"@
        }

        Write-Log -Message "Utilisateur Artifactory trouvé (variables $($usernameSetting.Source))." -Level "OK"
        Write-Log -Message "Token Artifactory trouvé (variables $($tokenSetting.Source))." -Level "OK"

        if ([string]::IsNullOrWhiteSpace($PackageUrl)) {
            $urlSetting = Get-ConfigurationValue -Name "STYX_PACKAGE_URL"

            if ($null -eq $urlSetting) {
                throw @"
L'adresse du package est absente.

Trois possibilités :

1. passer l'adresse dans la commande :
   -PackageUrl "https://.../Styx.Publish.1.2.3.nupkg"

2. définir la variable d'environnement STYX_PACKAGE_URL ;

3. fournir un package local : -PackageFile "D:\...\Styx.Publish.1.2.3.nupkg"
"@
            }

            $PackageUrl = $urlSetting.Value
            Write-Log -Message "Adresse du package trouvée (variables $($urlSetting.Source))." -Level "OK"
        }

        if (-not $PackageUrl.StartsWith("https://", [StringComparison]::OrdinalIgnoreCase)) {
            throw @"
L'adresse du package doit commencer par https://

Adresse reçue :
$PackageUrl
"@
        }

        Write-Log -Message "Adresse du package valide : $PackageUrl" -Level "OK"
    }

    # --------------------------------------------------------
    # J6 - Téléchargement (ou copie du package local)
    # --------------------------------------------------------
    # Le dossier de travail est sur D:, comme les destinations : Move-Item
    # ne sait pas déplacer un dossier d'un volume à un autre.

    Write-Step "[J6] Récupération du package"

    $workingDirectory    = Join-Path $DestinationRoot ".deploy\$deploymentTimestamp-$deploymentId"
    $extractionDirectory = Join-Path $workingDirectory "extracted"
    $stagingDirectory    = Join-Path $workingDirectory "staging"
    $workingPackageFile  = Join-Path $workingDirectory "Styx.Publish.nupkg"

    New-Item -Path $extractionDirectory -ItemType Directory -Force | Out-Null
    New-Item -Path $stagingDirectory    -ItemType Directory -Force | Out-Null

    Write-Log -Message "Dossier de travail : $workingDirectory"

    if ($usePackageFile) {
        Copy-Item -LiteralPath $PackageFile -Destination $workingPackageFile -Force -ErrorAction Stop
        Assert-PackageFile -Path $workingPackageFile -Description "Package local copié"
    }
    else {
        Save-ArtifactoryPackage `
            -Url $PackageUrl `
            -Username $usernameSetting.Value `
            -Token $tokenSetting.Value `
            -OutputFile $workingPackageFile

        $tokenSetting = $null
    }

    # --------------------------------------------------------
    # J7 - Extraction et contrôle du contenu
    # --------------------------------------------------------

    Write-Step "[J7] Extraction et contrôle du package"

    Expand-NuGetPackage -PackageFile $workingPackageFile -Destination $extractionDirectory

    $deploymentPlan = @()

    if ($STP) {
        $deploymentPlan += [pscustomobject] @{
            Trigram     = "STP"
            PackagePath = Join-Path $extractionDirectory "content\taskflow"
            StagingPath = Join-Path $stagingDirectory "STP"
            Destination = $taskflowDestination
        }
    }

    if ($STX) {
        $deploymentPlan += [pscustomobject] @{
            Trigram     = "STX"
            PackagePath = Join-Path $extractionDirectory "content\api"
            StagingPath = Join-Path $stagingDirectory "STX"
            Destination = $apiDestination
        }
    }

    if ($STJ) {
        $deploymentPlan += [pscustomobject] @{
            Trigram     = "STJ"
            PackagePath = Join-Path $extractionDirectory "content\hpclite"
            StagingPath = Join-Path $stagingDirectory "STJ"
            Destination = $hpcLiteDestination
        }
    }

    # Seuls les contenus demandés sont contrôlés.
    foreach ($component in $deploymentPlan) {
        Assert-ExistingDirectory -Path $component.PackagePath -Description "Contenu $($component.Trigram) dans le package"

        $fileCount = Get-FileCount -Path $component.PackagePath

        if ($fileCount -eq 0) {
            throw @"
Le dossier $($component.Trigram) existe dans le package, mais il est vide.

Dossier contrôlé :
$($component.PackagePath)
"@
        }

        Write-Log -Message "Contenu $($component.Trigram) trouvé : $fileCount fichiers." -Level "OK"
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
        Assert-ExistingFile -Path (Join-Path (Join-Path $stagingDirectory "STP") $TaskflowExecutableRelativePath) -Description "Nouvel exécutable Taskflow dans le package"
    }

    if ($STJ) {
        $stjStaging = Join-Path $stagingDirectory "STJ"

        Assert-ExistingFile -Path (Join-Path (Join-Path $stjStaging $HpcLiteAgentFolder) $HpcLiteAgentExecutableName) -Description "Nouvel exécutable HpcLite Agent dans le package"
        Assert-ExistingFile -Path (Join-Path (Join-Path $stjStaging $HpcLiteRunnerFolder) $HpcLiteRunnerExecutableName) -Description "Nouvel exécutable HpcLite Runner dans le package"
        Assert-ExistingFile -Path (Join-Path (Join-Path $stjStaging $HpcLiteSchedulerFolder) $HpcLiteSchedulerExecutableName) -Description "Nouvel exécutable HpcLite Scheduler dans le package"
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

    try {
        Write-Step "[J12] Arrêt des applications"

        Stop-SelectedApplications -Paths $paths

        # [POINT-DE-TEST:apres-arret]

        Write-Step "[J13] Redémarrage des applications"

        Start-PreviouslyRunningApplications -Paths $paths -PreviousState $previousState

        # ---- Fin de la version du jalon 13 (générée par Build-JalonVersions.ps1) ----
        Write-Log -Message "JALON 13 ATTEINT : applications arrêtées puis redémarrées sans changement de fichiers." -Level "ATTENTION"
        Write-Log -Message "TEST TERMINÉ : les applications ont retrouvé leur état initial." -Level "ATTENTION"
        exit 0
    }
    catch {
        $deploymentError = $_

        Write-Log -Message "Le déploiement a échoué après l'arrêt des applications." -Level "ERREUR"
        Write-Log -Message $deploymentError.Exception.Message -Level "ERREUR"

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

            # Supprime aussi <d>\.deploy s'il est vide.
            $deployRoot = Split-Path -Parent -Path $workingDirectory

            if ((Test-Path -LiteralPath $deployRoot) -and @(Get-ChildItem -LiteralPath $deployRoot -Force).Count -eq 0) {
                Remove-Item -LiteralPath $deployRoot -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
