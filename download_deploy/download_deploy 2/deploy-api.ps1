#requires -Version 5.1

<#
.SYNOPSIS
    Télécharge le package Styx et déploie l'API Styx (IIS) sur ce serveur.

.DESCRIPTION
    Aucun paramètre. Ce script lance simplement :
        .\download_deploy.ps1 -STX
    Toute la logique est dans download_deploy.ps1 (même dossier).

    Variables d'environnement (niveau Machine) nécessaires :
        ARTIFACTORY_USERNAME, ARTIFACTORY_TOKEN, STYX_PACKAGE_URL

    Application installée dans : D:\Applications\api

.NOTES
    Code de sortie : celui de download_deploy.ps1 (0 succès, 1 erreur).
#>

$deployScript = Join-Path $PSScriptRoot "download_deploy.ps1"

if (-not (Test-Path -LiteralPath $deployScript -PathType Leaf)) {
    Write-Host "download_deploy.ps1 est introuvable à côté de ce script : $deployScript" -ForegroundColor Red
    exit 1
}

& $deployScript -STX
exit $LASTEXITCODE
