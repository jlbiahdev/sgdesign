#requires -Version 5.1

<#
.SYNOPSIS
    Pousse un package .nupkg Styx vers Artifactory.

.DESCRIPTION
    Le fichier à pousser est OBLIGATOIRE : aucun « dernier package trouvé »,
    pour ne jamais pousser un ancien package par erreur.

    Une version déjà présente sur Artifactory est une ERREUR (pas de
    --skip-duplicate) : deux builds ne doivent pas produire la même version.

    La clé d'API est lue dans la variable d'environnement ARTIFACTORY_API_KEY
    (session, utilisateur ou machine). Elle n'est jamais écrite dans un
    fichier ni affichée.

.PARAMETER PackageFile
    Chemin du .nupkg, tel qu'affiché par package.ps1.

.EXAMPLE
    $env:ARTIFACTORY_API_KEY = "..."
    .\push-artifactory.ps1 -PackageFile "C:\Users\...\Temp\styx_packages\Styx.Publish.1.261020.143512.nupkg"

.NOTES
    Code de sortie : 0 succès, 1 erreur.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $PackageFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "StyxBuild.psm1") -Force
Initialize-StyxOutput

try {
    Write-StyxStep "STYX - Push NuGet vers Artifactory"

    Assert-StyxCommand -Name "dotnet"
    $config = Get-StyxConfiguration -ScriptDirectory $PSScriptRoot

    if (-not (Test-Path -LiteralPath $PackageFile -PathType Leaf)) {
        throw "Package introuvable : $PackageFile"
    }

    $package = Get-Item -LiteralPath $PackageFile

    if ($package.Extension -ne ".nupkg") {
        throw "Le fichier n'est pas un package NuGet (.nupkg) : $($package.FullName)"
    }

    # Clé d'API : session, puis utilisateur, puis machine.
    $variable = $config.ArtifactoryApiKeyVariable
    $apiKey = $null

    foreach ($target in @("Process", "User", "Machine")) {
        $value = [Environment]::GetEnvironmentVariable($variable, $target)
        if (-not [string]::IsNullOrWhiteSpace($value)) { $apiKey = $value; break }
    }

    if ($null -eq $apiKey) {
        throw "Variable d'environnement $variable non définie. Exemple : `$env:$variable = `"<clé>`""
    }

    Write-StyxInfo "Package : $($package.FullName)"
    Write-StyxInfo "Repo    : $($config.ArtifactoryRepo)"
    Write-StyxInfo "Source  : $($config.ArtifactorySource)"
    Write-Host ""

    # La clé n'est pas affichée : on n'utilise pas Invoke-StyxNative, qui
    # écrit la ligne de commande.
    Write-Host "> dotnet nuget push `"$($package.FullName)`" --source `"$($config.ArtifactorySource)`" --api-key ***" -ForegroundColor DarkGray

    & dotnet nuget push $package.FullName --source $config.ArtifactorySource --api-key $apiKey

    if ($LASTEXITCODE -ne 0) {
        throw "Échec du push vers Artifactory (code $LASTEXITCODE). Si le message indique un conflit (409), cette version existe déjà sur Artifactory : relancer package.ps1 pour produire une nouvelle version."
    }

    Write-StyxSuccess "Package poussé avec succès : $($package.Name)"
    exit 0
}
catch {
    Write-StyxFailure $_.Exception.Message
    exit 1
}
