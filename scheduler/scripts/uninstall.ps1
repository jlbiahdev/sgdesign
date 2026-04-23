#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Désinstalle HpcLite Scheduler et/ou Agent.

.PARAMETER Target
    Quels services désinstaller : "scheduler", "agent" ou "all". Défaut : "all"

.PARAMETER RemoveFiles
    Si présent, supprime aussi les fichiers déployés.

.PARAMETER SchedulerPath
    Chemin du Scheduler déployé. Défaut : C:\apps\HpcLite.Scheduler

.PARAMETER AgentPath
    Chemin de l'Agent déployé. Défaut : C:\apps\HpcLite.Agent

.PARAMETER RunnerPath
    Chemin du Runner déployé. Défaut : C:\apps\HpcLite.Runner

.EXAMPLE
    .\uninstall.ps1
    .\uninstall.ps1 -Target agent -RemoveFiles
#>
param(
    [ValidateSet("scheduler","agent","all")]
    [string]$Target        = "all",
    [switch]$RemoveFiles,
    [string]$SchedulerPath = "C:\apps\HpcLite.Scheduler",
    [string]$AgentPath     = "C:\apps\HpcLite.Agent",
    [string]$RunnerPath    = "C:\apps\HpcLite.Runner"
)

function Remove-Service([string]$name, [string]$path) {
    $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
    if (-not $svc) {
        Write-Host "  '$name' non installé — ignoré." -ForegroundColor DarkGray
        return
    }

    Write-Host "`nDésinstallation de '$name'..." -ForegroundColor Cyan

    if ($svc.Status -eq "Running") {
        Write-Host "  Arrêt..."
        Stop-Service -Name $name -Force
        Start-Sleep -Seconds 3
    }

    sc.exe delete $name
    Write-Host "  Service supprimé." -ForegroundColor Green

    if ($RemoveFiles -and (Test-Path $path)) {
        Write-Host "  Suppression des fichiers : $path"
        Remove-Item -Recurse -Force $path
        Write-Host "  Fichiers supprimés." -ForegroundColor Green
    }
}

if ($Target -in @("scheduler","all")) {
    Remove-Service "HpcLite Scheduler" $SchedulerPath
}

if ($Target -in @("agent","all")) {
    Remove-Service "HpcLite Agent" $AgentPath
    if ($RemoveFiles -and (Test-Path $RunnerPath)) {
        Write-Host "  Suppression des fichiers Runner : $RunnerPath"
        Remove-Item -Recurse -Force $RunnerPath
    }
}

Write-Host "`nTerminé.`n"
