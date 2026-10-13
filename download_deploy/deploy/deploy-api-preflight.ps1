#requires -Version 5.1

<#
.SYNOPSIS
    Contrôle préalable du déploiement de l'API sur ce serveur.
    Aucune application n'est arrêtée, aucun fichier n'est remplacé.

.DESCRIPTION
    Aucun paramètre. Ce script lance simplement :
        .\deploy.ps1 -STX -ValidationOnly
    Toute la logique est dans deploy.ps1 (même dossier).

    Effectue tous les contrôles du déploiement
    (D:\Applications\api, le pool IIS...), puis s'arrête AVANT tout arrêt d'application.
    À lancer avant deploy-api.ps1 pour vérifier que le déploiement passera.

    Nouveaux fichiers attendus dans : D:\.deploy\api

.NOTES
    Code de sortie : celui de deploy.ps1 (0 contrôles réussis, 1 erreur).
#>

$deployScript = Join-Path $PSScriptRoot "deploy.ps1"

if (-not (Test-Path -LiteralPath $deployScript -PathType Leaf)) {
    Write-Host "deploy.ps1 est introuvable à côté de ce script : $deployScript" -ForegroundColor Red
    exit 1
}

& $deployScript -STX -ValidationOnly
exit $LASTEXITCODE
