#requires -Version 5.1

<#
.SYNOPSIS
    Déploie l'API Styx (IIS) sur ce serveur.

.DESCRIPTION
    Raccourci de : .\deploy.ps1 -STX <paramètres>
    Toute la logique est dans deploy.ps1 (même dossier). Ce script lui
    indique seulement l'application à déployer, et lui transmet les autres
    paramètres tels quels.

    Les nouveaux fichiers doivent être dans D:\.deploy\api.

.PARAMETER DestinationRoot
    Alias : -d. Racine des applications. Exemple : D:\Applications

.PARAMETER SourceRoot
    Dossier des nouveaux fichiers déjà extraits. Par défaut : D:\.deploy

.PARAMETER ValidationOnly
    Pré-vol : tout est vérifié, aucune application n'est arrêtée.

.PARAMETER Force
    Supprime la confirmation interactive « DEPLOYER ».

.PARAMETER KeepTemporaryFiles
    Conserve le dossier de travail (<d>\.staging\...) pour diagnostic.

.EXAMPLE
    .\deploy-api.ps1 -d D:\Applications -ValidationOnly

.EXAMPLE
    .\deploy-api.ps1 -d D:\Applications

.NOTES
    Code de sortie : celui de deploy.ps1 (0 succès, 1 erreur, 2 annulation).
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [Alias("d")]
    [string] $DestinationRoot,

    [Parameter()] [string] $SourceRoot,
    [Parameter()] [switch] $ValidationOnly,
    [Parameter()] [switch] $Force,
    [Parameter()] [switch] $KeepTemporaryFiles
)

$deployScript = Join-Path $PSScriptRoot "deploy.ps1"

if (-not (Test-Path -LiteralPath $deployScript -PathType Leaf)) {
    Write-Host "deploy.ps1 est introuvable à côté de ce script : $deployScript" -ForegroundColor Red
    exit 1
}

# Les paramètres reçus sont transmis tels quels, avec -STX en plus.
$parameters = @{} + $PSBoundParameters
$parameters["STX"] = $true

& $deployScript @parameters
exit $LASTEXITCODE
