#requires -Version 5.1

<#
.SYNOPSIS
    Compile toute la solution Styx (restore, clean, rebuild).

.DESCRIPTION
    1. Contrôle la présence de la solution et des projets publiés.
    2. dotnet restore de la solution.
    3. dotnet clean puis rebuild complet en Release.

    Utilisé seul, ou appelé par package.ps1 et push-git.ps1.
    Les tests unitaires s'ajouteront ici (dotnet test) quand ils existeront.

.EXAMPLE
    .\build.ps1

.NOTES
    Code de sortie : 0 succès, 1 erreur.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "StyxBuild.psm1") -Force
Initialize-StyxOutput

try {
    Write-StyxStep "STYX - Build de la solution"

    Assert-StyxCommand -Name "dotnet"
    $config = Get-StyxConfiguration -ScriptDirectory $PSScriptRoot
    Write-StyxConfiguration -Config $config

    Write-StyxStep "Restore de la solution"
    Invoke-StyxNative -FilePath "dotnet" -Description "dotnet restore" -Arguments (
        @("restore", $config.SolutionFile) + $config.RestoreArgs)

    Write-StyxStep "Clean + rebuild de la solution"
    Invoke-StyxNative -FilePath "dotnet" -Description "dotnet clean" -Arguments (
        @("clean", $config.SolutionFile, "-c", $config.Configuration) + $config.BuildArgs)

    Invoke-StyxNative -FilePath "dotnet" -Description "dotnet build" -Arguments (
        @("build", $config.SolutionFile, "-c", $config.Configuration, "-t:Rebuild", "--no-restore") + $config.BuildArgs)

    # Tests unitaires : à ajouter ici quand ils existeront, par exemple
    # Invoke-StyxNative -FilePath "dotnet" -Description "dotnet test" -Arguments @("test", $config.SolutionFile, "-c", $config.Configuration, "--no-build")

    Write-StyxSuccess "Build terminé avec succès."
    exit 0
}
catch {
    Write-StyxFailure $_.Exception.Message
    exit 1
}
