#requires -Version 5.1

<#
.SYNOPSIS
    Déploie HpcLite (Agent, Runner, Scheduler) sur ce serveur.

.DESCRIPTION
    Aucun paramètre. Ce script lance simplement :
        .\deploy.ps1 -STJ
    Toute la logique est dans deploy.ps1 (même dossier).

    Nouveaux fichiers attendus dans : D:\.deploy\hpclite\{agent, runner, scheduler}
    Application installée dans      : D:\Applications\HpcLite\{agent, runner, scheduler}

.NOTES
    Code de sortie : celui de deploy.ps1 (0 succès, 1 erreur).
#>

$deployScript = Join-Path $PSScriptRoot "deploy.ps1"

if (-not (Test-Path -LiteralPath $deployScript -PathType Leaf)) {
    Write-Host "deploy.ps1 est introuvable à côté de ce script : $deployScript" -ForegroundColor Red
    exit 1
}

& $deployScript -STJ
exit $LASTEXITCODE
