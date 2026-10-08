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
      - Ce fichier est généré à partir de _tools\download_deploy.template.ps1.
        Les dossiers de test contiennent des versions PARTIELLES : la version
        du jalon N ne contient que le code des jalons 0 à N et se termine par
        « TEST TERMINÉ ». Ne pas modifier ce fichier directement : modifier
        le modèle puis lancer _tools\Build-JalonVersions.ps1.
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

    # ---- Fin de la version du jalon 3 (générée par Build-JalonVersions.ps1) ----
    Write-Log -Message "JALON 3 ATTEINT : demande validée." -Level "ATTENTION"
    Write-Log -Message "TEST TERMINÉ : aucune application n'a été arrêtée." -Level "ATTENTION"
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
}
