#requires -Version 5.1

<#
.SYNOPSIS
    Configuration et fonctions communes aux scripts de build Styx.

.DESCRIPTION
    Utilisé par build.ps1, package.ps1, push-git.ps1 et push-artifactory.ps1.
    Toute la configuration (chemins, projets, options .NET, Artifactory)
    est ici, en un seul endroit.
#>

Set-StrictMode -Version Latest

# ============================================================
# >>> DEBUT CONFIGURATION
# ============================================================

# Chemins relatifs à la racine du dépôt Git.
$script:SrcRelativePath      = "01_POC\src"
$script:BackendRelativePath  = "01_POC\src\backend"
$script:SolutionRelativePath = "01_POC\src\backend\styxapipoc.sln"

# Projets publiés, et sous-dossier de chacun dans le package
# (structure attendue par download_deploy.ps1).
$script:PublishedProjects = @(
    [pscustomobject] @{ Name = "API";               Folder = "api";               Project = "Styx.WebApi\Styx.Front.WebApi.csproj" }
    [pscustomobject] @{ Name = "HpcLite Scheduler"; Folder = "hpclite\scheduler"; Project = "Styx.Application.HpcLite\Scheduler\Styx.Application.HpcLite.Scheduler.csproj" }
    [pscustomobject] @{ Name = "HpcLite Agent";     Folder = "hpclite\agent";     Project = "Styx.Application.HpcLite\Agent\Styx.Application.HpcLite.Agent.csproj" }
    [pscustomobject] @{ Name = "HpcLite Runner";    Folder = "hpclite\runner";    Project = "Styx.Application.HpcLite\Runner\Styx.Application.HpcLite.Runner.csproj" }
    [pscustomobject] @{ Name = "Taskflow";          Folder = "taskflow";          Project = "Styx.Application.TaskFlow\Styx.Application.TaskFlow.Runner\Socgen.TaskFlow.Runner.csproj" }
)

# Options .NET.
$script:DotnetConfiguration = "Release"
$script:DotnetRuntime       = "win-x64"
$script:DotnetSelfContained = $true
$script:DotnetRestoreArgs   = @("--ignore-failed-sources", "-p:NuGetAudit=false")
$script:DotnetBuildArgs     = @("-p:NuGetAudit=false")

# Package NuGet.
$script:DefaultPackageId      = "Styx.Publish"
$script:PackageVersionMajor   = 1
$script:PackageArchiveName    = "styx_publish.zip"     # placé dans content\ du .nupkg
$script:PackageTargetFramework = "net8.0"

# Dossiers de travail (un sous-dossier unique par exécution).
$script:WorkRoot              = Join-Path $env:TEMP "styx_build"
$script:DefaultPackageOutput  = Join-Path $env:TEMP "styx_packages"

# Share réseau (package.ps1 -SyncShare uniquement).
$script:SharePath        = "\\srvrbxassufp01\hpc\00_MOTEUR\FEATURE-TEAM\publish\styx"
$script:ShareExtraFiles  = @("start_all.ps1", "env.ps1")   # dans le dossier des scripts

# Artifactory (push).
$script:ArtifactoryBase  = "https://dsp-artifacts.fr.world.socgen"
$script:ArtifactoryRepo  = "nuget-releases-private-1820be41-3d86-47d4-af9e-3af96ef6ee23"
$script:ArtifactoryApiKeyVariable = "ARTIFACTORY_API_KEY"

# ============================================================
# <<< FIN CONFIGURATION
# ============================================================

# ------------------------------------------------------------
# Affichage
# ------------------------------------------------------------

<#
.SYNOPSIS
    Prépare la sortie : UTF-8 quand la sortie est redirigée
    (fenêtre Output de Visual Studio, CI), pour garder les accents.
#>
function Initialize-StyxOutput {
    if ([Console]::IsOutputRedirected) {
        try { [Console]::OutputEncoding = New-Object Text.UTF8Encoding $false } catch { }
    }
}

function Write-StyxStep {
    param([Parameter(Mandatory = $true)] [string] $Title)

    Write-Host ""
    Write-Host ("=" * 62) -ForegroundColor Cyan
    Write-Host $Title -ForegroundColor Cyan
    Write-Host ("=" * 62) -ForegroundColor Cyan
}

function Write-StyxInfo {
    param([Parameter(Mandatory = $true)] [string] $Message)
    Write-Host $Message
}

function Write-StyxSuccess {
    param([Parameter(Mandatory = $true)] [string] $Message)

    Write-Host ""
    Write-Host ("=" * 62) -ForegroundColor Green
    Write-Host $Message -ForegroundColor Green
    Write-Host ("=" * 62) -ForegroundColor Green
}

function Write-StyxFailure {
    param([Parameter(Mandatory = $true)] [string] $Message)

    Write-Host ""
    Write-Host ("=" * 62) -ForegroundColor Red
    Write-Host "ERREUR : $Message" -ForegroundColor Red
    Write-Host ("=" * 62) -ForegroundColor Red
}

# ------------------------------------------------------------
# Commandes externes
# ------------------------------------------------------------

<#
.SYNOPSIS
    Exécute une commande externe (dotnet, git, robocopy...) en affichant sa
    sortie, et lève une erreur si son code de sortie n'est pas accepté.
#>
function Invoke-StyxNative {
    param(
        [Parameter(Mandatory = $true)] [string] $FilePath,
        [string[]] $Arguments = @(),
        [string] $Description = $FilePath,
        [int] $MaxSuccessExitCode = 0
    )

    Write-Host "> $FilePath $($Arguments -join ' ')" -ForegroundColor DarkGray

    & $FilePath @Arguments
    $code = $LASTEXITCODE

    # Un code négatif (plantage, échec de démarrage) est aussi un échec.
    if ($code -lt 0 -or $code -gt $MaxSuccessExitCode) {
        throw "$Description a échoué (code $code)."
    }
}

<#
.SYNOPSIS
    Exécute une commande externe et renvoie sa sortie standard, sans rien
    afficher et sans lever d'erreur (stderr ignoré). Pour les interrogations
    (git rev-parse, git status...).
#>
function Invoke-StyxNativeQuery {
    param(
        [Parameter(Mandatory = $true)] [string] $FilePath,
        [string[]] $Arguments = @()
    )

    # En Windows PowerShell 5.1, rediriger stderr d'une commande externe avec
    # ErrorActionPreference = Stop lève une erreur au premier message : on
    # repasse localement en Continue.
    $ErrorActionPreference = "Continue"

    $output = & $FilePath @Arguments 2>$null

    return [pscustomobject] @{
        ExitCode = $LASTEXITCODE
        Output   = @($output | ForEach-Object { [string] $_ })
    }
}

function Assert-StyxCommand {
    param([Parameter(Mandatory = $true)] [string] $Name)

    if ($null -eq (Get-Command -Name $Name -CommandType Application -ErrorAction SilentlyContinue)) {
        throw "'$Name' est introuvable dans le PATH."
    }
}

# ------------------------------------------------------------
# Dépôt et configuration
# ------------------------------------------------------------

<#
.SYNOPSIS
    Racine du dépôt Git qui contient le dossier des scripts.
#>
function Get-StyxRepositoryRoot {
    param([Parameter(Mandatory = $true)] [string] $ScriptDirectory)

    Assert-StyxCommand -Name "git"

    $result = Invoke-StyxNativeQuery -FilePath "git" -Arguments @("-C", $ScriptDirectory, "rev-parse", "--show-toplevel")

    if ($result.ExitCode -ne 0 -or $result.Output.Count -eq 0 -or [string]::IsNullOrWhiteSpace($result.Output[0])) {
        throw "Impossible de détecter la racine du dépôt Git depuis $ScriptDirectory."
    }

    # git renvoie des « / » : on normalise en chemin Windows.
    return [IO.Path]::GetFullPath($result.Output[0].Trim())
}

<#
.SYNOPSIS
    Configuration complète, chemins résolus, et contrôle de leur existence.
#>
function Get-StyxConfiguration {
    param([Parameter(Mandatory = $true)] [string] $ScriptDirectory)

    $root    = Get-StyxRepositoryRoot -ScriptDirectory $ScriptDirectory
    $backend = Join-Path $root $script:BackendRelativePath

    $projects = foreach ($p in $script:PublishedProjects) {
        [pscustomobject] @{
            Name    = $p.Name
            Folder  = $p.Folder
            Project = Join-Path $backend $p.Project
        }
    }

    $config = [pscustomobject] @{
        RepositoryRoot   = $root
        SrcRoot          = Join-Path $root $script:SrcRelativePath
        BackendRoot      = $backend
        SolutionFile     = Join-Path $root $script:SolutionRelativePath
        ScriptDirectory  = $ScriptDirectory
        Projects         = @($projects)
        Configuration    = $script:DotnetConfiguration
        Runtime          = $script:DotnetRuntime
        SelfContained    = $script:DotnetSelfContained
        RestoreArgs      = $script:DotnetRestoreArgs
        BuildArgs        = $script:DotnetBuildArgs
        DefaultPackageId = $script:DefaultPackageId
        PackageArchiveName     = $script:PackageArchiveName
        PackageTargetFramework = $script:PackageTargetFramework
        WorkRoot         = $script:WorkRoot
        DefaultPackageOutput = $script:DefaultPackageOutput
        SharePath        = $script:SharePath
        ShareExtraFiles  = @($script:ShareExtraFiles | ForEach-Object { Join-Path $ScriptDirectory $_ })
        ArtifactorySource = "$($script:ArtifactoryBase)/artifactory/api/nuget/v3/$($script:ArtifactoryRepo)"
        ArtifactoryRepo   = $script:ArtifactoryRepo
        ArtifactoryApiKeyVariable = $script:ArtifactoryApiKeyVariable
    }

    if (-not (Test-Path -LiteralPath $config.BackendRoot -PathType Container)) {
        throw "Dossier backend introuvable : $($config.BackendRoot)"
    }

    if (-not (Test-Path -LiteralPath $config.SolutionFile -PathType Leaf)) {
        throw "Solution introuvable : $($config.SolutionFile)"
    }

    foreach ($p in $config.Projects) {
        if (-not (Test-Path -LiteralPath $p.Project -PathType Leaf)) {
            throw "Projet $($p.Name) introuvable : $($p.Project)"
        }
    }

    return $config
}

function Write-StyxConfiguration {
    param([Parameter(Mandatory = $true)] [object] $Config)

    Write-StyxInfo "Dépôt Git     : $($Config.RepositoryRoot)"
    Write-StyxInfo "Solution      : $($Config.SolutionFile)"

    foreach ($p in $Config.Projects) {
        Write-StyxInfo ("{0,-18}: {1}" -f $p.Name, $p.Project)
    }
}

# ------------------------------------------------------------
# Version et dossiers de travail
# ------------------------------------------------------------

<#
.SYNOPSIS
    Version du package : <majeur>.<AAMMJJ>.<HHMMSS>, sans zéro de tête
    (NuGet les retire de toute façon : 09:05:12 -> 90512).
#>
function New-StyxPackageVersion {
    param([datetime] $Date = (Get-Date))

    return "{0}.{1}.{2}" -f $script:PackageVersionMajor, [int] $Date.ToString("yyMMdd"), [int] $Date.ToString("HHmmss")
}

<#
.SYNOPSIS
    Dossier de travail propre à cette exécution : deux exécutions en
    parallèle ne se marchent pas dessus.
#>
function New-StyxWorkDirectory {
    param([Parameter(Mandatory = $true)] [object] $Config)

    $name = "{0}-{1}" -f (Get-Date -Format "yyyyMMdd-HHmmss"), [guid]::NewGuid().ToString("N").Substring(0, 8)
    $path = Join-Path $Config.WorkRoot $name

    New-Item -Path $path -ItemType Directory -Force | Out-Null
    return $path
}

# ------------------------------------------------------------
# Zip
# ------------------------------------------------------------

<#
.SYNOPSIS
    Crée un zip conforme : séparateurs « / » dans les noms d'entrées.

.DESCRIPTION
    Compress-Archive (Windows PowerShell 5.1) écrit des « \ », non conformes
    à la norme zip. Les entrées sont donc écrites une par une.
#>
function New-StyxZip {
    param(
        [Parameter(Mandatory = $true)] [string] $SourceDirectory,
        [Parameter(Mandatory = $true)] [string] $ZipFile
    )

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $source = [IO.Path]::GetFullPath($SourceDirectory).TrimEnd("\", "/")

    if (Test-Path -LiteralPath $ZipFile) {
        Remove-Item -LiteralPath $ZipFile -Force
    }

    $zip = [IO.Compression.ZipFile]::Open($ZipFile, [IO.Compression.ZipArchiveMode]::Create)

    try {
        foreach ($file in Get-ChildItem -LiteralPath $source -Recurse -File -Force) {
            $relative = $file.FullName.Substring($source.Length + 1).Replace("\", "/")
            [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $file.FullName, $relative, [IO.Compression.CompressionLevel]::Optimal) | Out-Null
        }
    }
    finally {
        $zip.Dispose()
    }
}

# ------------------------------------------------------------
# Git
# ------------------------------------------------------------

<#
.SYNOPSIS
    Fichiers modifiés ou non suivis du dossier de travail (vide si propre).
#>
function Get-StyxUncommittedChanges {
    param([Parameter(Mandatory = $true)] [string] $RepositoryRoot)

    $result = Invoke-StyxNativeQuery -FilePath "git" -Arguments @("-C", $RepositoryRoot, "status", "--porcelain")

    if ($result.ExitCode -ne 0) {
        throw "git status a échoué (code $($result.ExitCode))."
    }

    return @($result.Output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

Export-ModuleMember -Function `
    Initialize-StyxOutput, Write-StyxStep, Write-StyxInfo, Write-StyxSuccess, Write-StyxFailure, `
    Invoke-StyxNative, Invoke-StyxNativeQuery, Assert-StyxCommand, `
    Get-StyxRepositoryRoot, Get-StyxConfiguration, Write-StyxConfiguration, `
    New-StyxPackageVersion, New-StyxWorkDirectory, New-StyxZip, Get-StyxUncommittedChanges
