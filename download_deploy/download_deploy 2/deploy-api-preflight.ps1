#requires -Version 5.1

<#
.SYNOPSIS
    Contrôle préalable du déploiement de l'API sur ce serveur.
    Aucune application n'est arrêtée, aucun fichier n'est remplacé.

.DESCRIPTION
    Aucun paramètre. Ce script lance simplement :
        .\download_deploy.ps1 -STX -ValidationOnly
    Toute la logique est dans download_deploy.ps1 (même dossier).

    Télécharge le package Styx, puis effectue tous les contrôles du déploiement
    (D:\Applications\api, le pool IIS...), puis s'arrête AVANT tout arrêt d'application.
    À lancer avant deploy-api.ps1 pour vérifier que le déploiement passera.

    Variables d'environnement (niveau Machine) nécessaires :
        ARTIFACTORY_USERNAME, ARTIFACTORY_TOKEN, STYX_PACKAGE_URL

.NOTES
    Code de sortie : celui de download_deploy.ps1 (0 contrôles réussis, 1 erreur).
#>

$deployScript = Join-Path $PSScriptRoot "download_deploy.ps1"

if (-not (Test-Path -LiteralPath $deployScript -PathType Leaf)) {
    Write-Host "download_deploy.ps1 est introuvable à côté de ce script : $deployScript" -ForegroundColor Red
    exit 1
}

& $deployScript -STX -ValidationOnly
exit $LASTEXITCODE
