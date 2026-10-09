#requires -Version 5.1

<#
.SYNOPSIS
    Déploie l'API Styx (IIS) sur ce serveur.

.DESCRIPTION
    Aucun paramètre. Ce script lance simplement :
        .\deploy.ps1 -STX
    Toute la logique est dans deploy.ps1 (même dossier).

    Nouveaux fichiers attendus dans : D:\.deploy\api
    Application installée dans      : D:\Applications\api

.NOTES
    Code de sortie : celui de deploy.ps1 (0 succès, 1 erreur, 2 annulation).
#>

$deployScript = Join-Path $PSScriptRoot "deploy.ps1"

if (-not (Test-Path -LiteralPath $deployScript -PathType Leaf)) {
    Write-Host "deploy.ps1 est introuvable à côté de ce script : $deployScript" -ForegroundColor Red
    exit 1
}

& $deployScript -STX
exit $LASTEXITCODE
