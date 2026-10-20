#requires -Version 5.1

<#
.SYNOPSIS
    Configuration et fonctions communes aux scripts de build Styx.

.DESCRIPTION
    Utilisé par build.ps1 et publish-local.ps1.
    Toute la configuration (chemins, projets, options .NET) est ici, en un
    seul endroit.
#>

Set-StrictMode -Version Latest

# ============================================================
# >>> DEBUT CONFIGURATION
# ============================================================

# Chemins relatifs à la racine du dépôt Git.
$script:SrcRelativePath      = "01_POC\src"
$script:BackendRelativePath  = "01_POC\src\backend"
$script:SolutionRelativePath = "01_POC\src\backend\styxapipoc.sln"

# Projets publiés, avec leur sous-dossier sous la destination de
# publish-local.ps1 (même arborescence que sur les serveurs).
$script:PublishedProjects = @(
    [pscustomobject] @{ Name = "API";               LocalFolder = "api";               Project = "Styx.WebApi\Styx.Front.WebApi.csproj" }
    [pscustomobject] @{ Name = "HpcLite Scheduler"; LocalFolder = "HpcLite\scheduler"; Project = "Styx.Application.HpcLite\Scheduler\Styx.Application.HpcLite.Scheduler.csproj" }
    [pscustomobject] @{ Name = "HpcLite Agent";     LocalFolder = "HpcLite\agent";     Project = "Styx.Application.HpcLite\Agent\Styx.Application.HpcLite.Agent.csproj" }
    [pscustomobject] @{ Name = "HpcLite Runner";    LocalFolder = "HpcLite\runner";    Project = "Styx.Application.HpcLite\Runner\Styx.Application.HpcLite.Runner.csproj" }
    [pscustomobject] @{ Name = "Taskflow";          LocalFolder = "taskflow";          Project = "Styx.Application.TaskFlow\Styx.Application.TaskFlow.Runner\Socgen.TaskFlow.Runner.csproj" }
)

# Options .NET.
$script:DotnetConfiguration = "Release"
$script:DotnetRuntime       = "win-x64"
$script:DotnetSelfContained = $true
$script:DotnetRestoreArgs   = @("--ignore-failed-sources", "-p:NuGetAudit=false")
$script:DotnetBuildArgs     = @("-p:NuGetAudit=false")

# Dossiers de travail (un sous-dossier unique par exécution).
$script:WorkRoot = Join-Path $env:TEMP "styx_build"

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
            LocalFolder = $p.LocalFolder
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
        WorkRoot         = $script:WorkRoot
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
# Dossiers de travail
# ------------------------------------------------------------

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

Export-ModuleMember -Function `
    Initialize-StyxOutput, Write-StyxStep, Write-StyxInfo, Write-StyxSuccess, Write-StyxFailure, `
    Invoke-StyxNative, Invoke-StyxNativeQuery, Assert-StyxCommand, `
    Get-StyxRepositoryRoot, Get-StyxConfiguration, Write-StyxConfiguration, `
    New-StyxWorkDirectory
