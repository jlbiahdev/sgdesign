#requires -Version 5.1

<#
.SYNOPSIS
    Publie les applications Styx en self-contained dans un dossier local,
    avec la même arborescence que le serveur.

.DESCRIPTION
    Arborescence produite sous -Destination (comme D:\Applications) :

        api\
        taskflow\
        HpcLite\agent\
        HpcLite\runner\
        HpcLite\scheduler\

    1. Refuse si une application tourne depuis un de ces dossiers (exe
       verrouillé) : la liste des processus à arrêter est affichée.
    2. Publie toutes les applications dans un dossier de travail temporaire.
    3. Seulement si TOUTES les publications ont réussi : vide chaque dossier
       cible et y copie la nouvelle version. Une publication en échec ne
       laisse donc jamais un dossier vide ou à moitié rempli.

    ATTENTION : le contenu des dossiers cibles est entièrement remplacé,
    configuration comprise (appsettings*.json, web.config...).

.PARAMETER Destination
    Dossier racine local, par exemple C:\Styx. Créé s'il n'existe pas.

.PARAMETER Build
    Lance d'abord build.ps1 (restore, clean, rebuild de toute la solution).
    Sans ce paramètre, seuls les projets publiés sont compilés.

.EXAMPLE
    .\publish-local.ps1 -Destination C:\Styx

.NOTES
    Code de sortie : 0 succès, 1 erreur.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $Destination,

    [switch] $Build
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "StyxBuild.psm1") -Force
Initialize-StyxOutput

<#
.SYNOPSIS
    Processus dont l'exécutable se trouve sous un des dossiers donnés.
#>
function Get-ProcessesUnder {
    param([Parameter(Mandatory = $true)] [string[]] $Directories)

    $prefixes = $Directories | ForEach-Object { $_.TrimEnd("\") + "\" }

    return @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $path = $null
        try { $path = $_.Path } catch { }

        if ([string]::IsNullOrWhiteSpace($path)) { return $false }

        foreach ($prefix in $prefixes) {
            if ($path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { return $true }
        }

        return $false
    })
}

function Assert-NoProcessUnder {
    param([Parameter(Mandatory = $true)] [string[]] $Directories)

    $running = @(Get-ProcessesUnder -Directories $Directories)

    if ($running.Count -gt 0) {
        Write-Host ""
        Write-Host "Applications en cours d'exécution depuis le dossier cible :" -ForegroundColor Yellow
        $running | ForEach-Object { Write-Host ("  PID {0,-6} {1}" -f $_.Id, $_.Path) -ForegroundColor Yellow }

        throw "$($running.Count) processus tournent depuis le dossier cible. Les arrêter (services, consoles, IIS Express...) puis relancer. Rien n'a été modifié."
    }
}

$workDir = $null
$succeeded = $false

try {
    Write-StyxStep "STYX - Publication locale self-contained"

    Assert-StyxCommand -Name "dotnet"
    $config = Get-StyxConfiguration -ScriptDirectory $PSScriptRoot

    # Résolu par rapport à l'emplacement PowerShell courant.
    $root = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Destination).TrimEnd("\")

    # Garde-fou : jamais la racine d'un lecteur (on y viderait des dossiers).
    if ([string]::IsNullOrWhiteSpace($root) -or $root -match '^[A-Za-z]:$' -or $root -match '^\\\\[^\\]+\\[^\\]+$') {
        throw "Destination refusée : '$Destination'. Indiquer un dossier, pas la racine d'un lecteur ou d'un partage."
    }

    $targets = foreach ($p in $config.Projects) {
        [pscustomobject] @{
            Name    = $p.Name
            Project = $p.Project
            Target  = Join-Path $root $p.LocalFolder
        }
    }

    Write-StyxConfiguration -Config $config
    Write-StyxInfo "Destination   : $root"
    foreach ($t in $targets) { Write-StyxInfo ("  {0,-18} -> {1}" -f $t.Name, $t.Target) }

    # Contrôle au plus tôt, pour ne pas compiler pour rien.
    Assert-NoProcessUnder -Directories @($targets | ForEach-Object { $_.Target })

    # --- Build complet (optionnel) ---
    if ($Build) {
        & (Join-Path $PSScriptRoot "build.ps1")
        if ($LASTEXITCODE -ne 0) { throw "Le build a échoué : publication annulée." }
    }

    # --- Publication dans un dossier de travail ---
    $workDir = New-StyxWorkDirectory -Config $config
    Write-StyxInfo "Dossier de travail : $workDir"

    $selfContained = $config.SelfContained.ToString().ToLowerInvariant()
    $index = 0

    foreach ($t in $targets) {
        $index++
        $t | Add-Member -NotePropertyName Staging -NotePropertyValue (Join-Path $workDir ("{0}" -f $index))

        Write-StyxStep "Publication $($t.Name) (self-contained $($config.Runtime))"

        Invoke-StyxNative -FilePath "dotnet" -Description "dotnet restore ($($t.Name))" -Arguments (
            @("restore", $t.Project, "-r", $config.Runtime, "-p:SelfContained=$selfContained") + $config.RestoreArgs)

        Invoke-StyxNative -FilePath "dotnet" -Description "dotnet publish ($($t.Name))" -Arguments (
            @("publish", $t.Project,
              "-c", $config.Configuration,
              "--no-restore",
              "-r", $config.Runtime,
              "--self-contained", $selfContained,
              "-o", $t.Staging) + $config.BuildArgs)
    }

    # --- Remplacement des dossiers cibles ---
    Write-StyxStep "Installation dans $root"

    # Une application a pu être lancée pendant la compilation.
    Assert-NoProcessUnder -Directories @($targets | ForEach-Object { $_.Target })

    foreach ($t in $targets) {
        if (Test-Path -LiteralPath $t.Target) {
            Get-ChildItem -LiteralPath $t.Target -Force | Remove-Item -Recurse -Force
        }
        else {
            New-Item -Path $t.Target -ItemType Directory -Force | Out-Null
        }

        Copy-Item -Path (Join-Path $t.Staging "*") -Destination $t.Target -Recurse -Force

        $count = @(Get-ChildItem -LiteralPath $t.Target -Recurse -File).Count
        Write-StyxInfo ("{0,-18} : {1} fichier(s) dans {2}" -f $t.Name, $count, $t.Target)
    }

    $succeeded = $true
    Write-StyxSuccess "Publication locale terminée : $root"
    exit 0
}
catch {
    Write-StyxFailure $_.Exception.Message
    exit 1
}
finally {
    if ($null -ne $workDir -and (Test-Path -LiteralPath $workDir)) {
        if ($succeeded) {
            Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        else {
            Write-StyxInfo "Dossier de travail conservé : $workDir"
        }
    }
}
