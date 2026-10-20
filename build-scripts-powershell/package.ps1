#requires -Version 5.1

<#
.SYNOPSIS
    Produit le package NuGet Styx (Styx.Publish.<version>.nupkg).

.DESCRIPTION
    1. Lance build.ps1 (sauf -SkipBuild).
    2. Publie les 5 applications en self-contained win-x64 :
           api\  hpclite\scheduler\  hpclite\agent\  hpclite\runner\  taskflow\
    3. Les met dans styx_publish.zip (séparateurs « / », conforme).
    4. Crée le .nupkg avec ce zip dans content\ (structure attendue par
       download_deploy.ps1).
    5. Optionnel : synchronise le share réseau (-SyncShare).
    6. Optionnel : pousse le package vers Artifactory (-Push), en appelant
       push-artifactory.ps1 avec EXACTEMENT le fichier qui vient d'être créé.

    Chaque exécution travaille dans son propre dossier temporaire, supprimé à
    la fin (sauf -KeepWorkDirectory). Le .nupkg est conservé dans
    -OutputDirectory.

.PARAMETER PackageId
    Identifiant NuGet. Par défaut : Styx.Publish.

.PARAMETER PackageVersion
    Version imposée. Par défaut : 1.<AAMMJJ>.<HHMMSS>.

.PARAMETER OutputDirectory
    Dossier où le .nupkg est déposé. Par défaut : %TEMP%\styx_packages.

.PARAMETER SkipBuild
    Ne lance pas build.ps1 avant la publication.

.PARAMETER SyncShare
    Copie aussi les applications publiées (et start_all.ps1, env.ps1) sur
    le share réseau, en miroir.

.PARAMETER Push
    Pousse le package vers Artifactory une fois créé (ARTIFACTORY_API_KEY).

.PARAMETER KeepWorkDirectory
    Conserve le dossier de travail (publication, zip) pour diagnostic.

.EXAMPLE
    .\package.ps1

.EXAMPLE
    .\package.ps1 -Push

.NOTES
    Code de sortie : 0 succès, 1 erreur.
#>

[CmdletBinding()]
param(
    [string] $PackageId,
    [string] $PackageVersion,
    [string] $OutputDirectory,
    [switch] $SkipBuild,
    [switch] $SyncShare,
    [switch] $Push,
    [switch] $KeepWorkDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "StyxBuild.psm1") -Force
Initialize-StyxOutput

$workDir = $null
$succeeded = $false

try {
    Write-StyxStep "STYX - Création du package"

    Assert-StyxCommand -Name "dotnet"
    $config = Get-StyxConfiguration -ScriptDirectory $PSScriptRoot

    if ([string]::IsNullOrWhiteSpace($PackageId))       { $PackageId = $config.DefaultPackageId }
    if ([string]::IsNullOrWhiteSpace($PackageVersion))  { $PackageVersion = New-StyxPackageVersion }
    if ([string]::IsNullOrWhiteSpace($OutputDirectory)) { $OutputDirectory = $config.DefaultPackageOutput }

    $OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)

    if ($SyncShare) {
        foreach ($file in $config.ShareExtraFiles) {
            if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
                throw "Fichier à copier sur le share introuvable : $file"
            }
        }
    }

    Write-StyxConfiguration -Config $config
    Write-StyxInfo "Package       : $PackageId $PackageVersion"
    Write-StyxInfo "Sortie        : $OutputDirectory"
    Write-StyxInfo "Share         : $(if ($SyncShare) { $config.SharePath } else { 'non (-SyncShare pour l''activer)' })"
    Write-StyxInfo "Artifactory   : $(if ($Push) { 'oui' } else { 'non (-Push pour l''activer)' })"

    # --- Build ---
    if ($SkipBuild) {
        Write-StyxInfo "Build ignoré (-SkipBuild)."
    }
    else {
        & (Join-Path $PSScriptRoot "build.ps1")
        if ($LASTEXITCODE -ne 0) { throw "Le build a échoué : package annulé." }
    }

    $workDir    = New-StyxWorkDirectory -Config $config
    $publishDir = Join-Path $workDir "publish"
    $nugetDir   = Join-Path $workDir "nuget"
    $packDir    = Join-Path $workDir "pack"

    Write-StyxInfo "Dossier de travail : $workDir"

    # --- Publication des applications ---
    foreach ($p in $config.Projects) {
        Write-StyxStep "Publication $($p.Name) (self-contained $($config.Runtime))"

        $target = Join-Path $publishDir $p.Folder

        Invoke-StyxNative -FilePath "dotnet" -Description "dotnet restore ($($p.Name))" -Arguments (
            @("restore", $p.Project, "-r", $config.Runtime) + $config.RestoreArgs)

        Invoke-StyxNative -FilePath "dotnet" -Description "dotnet publish ($($p.Name))" -Arguments (
            @("publish", $p.Project,
              "-c", $config.Configuration,
              "--no-restore",
              "-r", $config.Runtime,
              "--self-contained", $config.SelfContained.ToString().ToLowerInvariant(),
              "-o", $target) + $config.BuildArgs)
    }

    # --- Zip applicatif ---
    Write-StyxStep "Création de $($config.PackageArchiveName)"

    New-Item -Path $nugetDir -ItemType Directory -Force | Out-Null
    $zipFile = Join-Path $nugetDir $config.PackageArchiveName
    New-StyxZip -SourceDirectory $publishDir -ZipFile $zipFile
    Write-StyxInfo "Zip : $zipFile ($([math]::Round((Get-Item -LiteralPath $zipFile).Length / 1MB)) Mo)"

    # --- Package NuGet ---
    Write-StyxStep "Création du package NuGet"

    $packProject = Join-Path $nugetDir "Styx.Publish.Pack.csproj"
    $escapedId      = [Security.SecurityElement]::Escape($PackageId)
    $escapedVersion = [Security.SecurityElement]::Escape($PackageVersion)

    $projectXml = @"
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>$($config.PackageTargetFramework)</TargetFramework>
    <IsPackable>true</IsPackable>
    <PackageId>$escapedId</PackageId>
    <PackageVersion>$escapedVersion</PackageVersion>
    <Version>1.0.0</Version>
    <AssemblyVersion>1.0.0.0</AssemblyVersion>
    <FileVersion>1.0.0.0</FileVersion>
    <InformationalVersion>$escapedVersion</InformationalVersion>
    <Authors>STYX</Authors>
    <Company>STYX</Company>
    <Description>Package de publication complet de l'application STYX.</Description>
    <PackageRequireLicenseAcceptance>false</PackageRequireLicenseAcceptance>
    <IncludeBuildOutput>false</IncludeBuildOutput>
    <SuppressDependenciesWhenPacking>true</SuppressDependenciesWhenPacking>
  </PropertyGroup>
  <ItemGroup>
    <None Include="$($config.PackageArchiveName)" Pack="true" PackagePath="content\" />
  </ItemGroup>
</Project>
"@

    [IO.File]::WriteAllText($packProject, $projectXml, (New-Object Text.UTF8Encoding $false))

    Invoke-StyxNative -FilePath "dotnet" -Description "dotnet pack" -Arguments (
        @("pack", $packProject, "-c", $config.Configuration, "-o", $packDir) + $config.BuildArgs)

    # Le nom du fichier suit la version NORMALISÉE par NuGet (zéros de tête
    # retirés) : on prend le seul .nupkg produit plutôt que de deviner son nom.
    $produced = @(Get-ChildItem -LiteralPath $packDir -Filter "*.nupkg" -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notlike "*.symbols.nupkg" })

    if ($produced.Count -ne 1) {
        throw "dotnet pack devait produire un seul .nupkg dans $packDir (trouvé : $($produced.Count))."
    }

    New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
    $packageFile = Join-Path $OutputDirectory $produced[0].Name

    if (Test-Path -LiteralPath $packageFile) {
        throw "Un package du même nom existe déjà : $packageFile"
    }

    Move-Item -LiteralPath $produced[0].FullName -Destination $packageFile
    Write-StyxInfo "Package : $packageFile"

    # --- Share (optionnel) ---
    if ($SyncShare) {
        Write-StyxStep "Synchronisation vers le share"
        Write-StyxInfo "Share : $($config.SharePath)"

        foreach ($p in $config.Projects) {
            $source      = Join-Path $publishDir $p.Folder
            $destination = Join-Path $config.SharePath $p.Folder

            # Robocopy : 0-7 = succès ou avertissement, 8 et plus = erreur.
            Invoke-StyxNative -FilePath "robocopy" -Description "robocopy ($($p.Name))" -MaxSuccessExitCode 7 -Arguments @(
                $source, $destination, "/MIR", "/R:2", "/W:2", "/NFL", "/NDL", "/NP")
        }

        foreach ($file in $config.ShareExtraFiles) {
            Copy-Item -LiteralPath $file -Destination $config.SharePath -Force
            Write-StyxInfo "Copié : $file"
        }
    }

    # --- Push Artifactory (optionnel) ---
    if ($Push) {
        & (Join-Path $PSScriptRoot "push-artifactory.ps1") -PackageFile $packageFile
        if ($LASTEXITCODE -ne 0) { throw "Le push vers Artifactory a échoué. Le package reste disponible : $packageFile" }
    }

    $succeeded = $true

    Write-StyxSuccess "Package créé avec succès : $packageFile"

    if (-not $Push) {
        Write-Host ""
        Write-StyxInfo "Pour le pousser vers Artifactory :"
        Write-StyxInfo "  .\push-artifactory.ps1 -PackageFile `"$packageFile`""
    }

    exit 0
}
catch {
    Write-StyxFailure $_.Exception.Message
    exit 1
}
finally {
    if ($null -ne $workDir -and (Test-Path -LiteralPath $workDir)) {
        if ($KeepWorkDirectory -or -not $succeeded) {
            Write-StyxInfo "Dossier de travail conservé : $workDir"
        }
        else {
            Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
