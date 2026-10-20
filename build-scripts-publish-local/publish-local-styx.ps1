#requires -Version 5.1

<#
.SYNOPSIS
    Publie les applications Styx en local dans C:\Styx.

.DESCRIPTION
    Aucun paramètre. Ce script lance simplement :
        .\publish-local.ps1 -Destination C:\Styx
    Toute la logique est dans publish-local.ps1 (même dossier).

    Les dossiers C:\Styx\api, taskflow et HpcLite\{agent, runner, scheduler}
    sont vidés puis remplacés par la nouvelle version.

.NOTES
    Code de sortie : celui de publish-local.ps1 (0 succès, 1 erreur).
#>

$publishScript = Join-Path $PSScriptRoot "publish-local.ps1"

if (-not (Test-Path -LiteralPath $publishScript -PathType Leaf)) {
    Write-Host "publish-local.ps1 est introuvable à côté de ce script : $publishScript" -ForegroundColor Red
    exit 1
}

& $publishScript -Destination "C:\Styx"
exit $LASTEXITCODE
