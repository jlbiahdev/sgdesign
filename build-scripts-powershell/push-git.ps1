#requires -Version 5.1

<#
.SYNOPSIS
    Vérifie que la solution compile, puis pousse la branche courante (git push).

.DESCRIPTION
    1. Refuse si le dossier de travail contient des modifications non
       commitées : le build doit porter exactement sur ce qui est poussé.
    2. Refuse si la branche n'a pas de branche distante (upstream).
    3. S'arrête sans rien faire s'il n'y a aucun commit à pousser.
    4. Lance build.ps1 (sauf -SkipBuild).
    5. git push.

    C'est le script du bouton Visual Studio « STYX [POC] - Build + Push ».

.PARAMETER SkipBuild
    Pousse sans lancer build.ps1.

.EXAMPLE
    .\push-git.ps1

.NOTES
    Code de sortie : 0 succès (ou rien à pousser), 1 erreur.
#>

[CmdletBinding()]
param(
    [switch] $SkipBuild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "StyxBuild.psm1") -Force
Initialize-StyxOutput

try {
    Write-StyxStep "STYX - Vérification puis push Git"

    $root = Get-StyxRepositoryRoot -ScriptDirectory $PSScriptRoot
    Write-StyxInfo "Dépôt Git : $root"

    # --- Branche courante ---
    $branch = (Invoke-StyxNativeQuery -FilePath "git" -Arguments @("-C", $root, "rev-parse", "--abbrev-ref", "HEAD")).Output | Select-Object -First 1

    if ([string]::IsNullOrWhiteSpace($branch) -or $branch -eq "HEAD") {
        throw "Aucune branche courante (HEAD détaché). Se placer sur une branche avant de pousser."
    }

    Write-StyxInfo "Branche   : $branch"

    # --- Dossier de travail propre ---
    $changes = @(Get-StyxUncommittedChanges -RepositoryRoot $root)

    if ($changes.Count -gt 0) {
        Write-Host ""
        Write-Host "Modifications non commitées :" -ForegroundColor Yellow
        $changes | Select-Object -First 20 | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
        if ($changes.Count -gt 20) { Write-Host "  ... et $($changes.Count - 20) autre(s)" -ForegroundColor Yellow }

        throw "Le dossier de travail n'est pas propre ($($changes.Count) fichier(s)). Commiter ou mettre de côté (git stash -u) ces modifications, puis relancer : le build doit porter exactement sur ce qui est poussé."
    }

    # --- Branche distante ---
    $upstream = Invoke-StyxNativeQuery -FilePath "git" -Arguments @("-C", $root, "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}")

    if ($upstream.ExitCode -ne 0 -or $upstream.Output.Count -eq 0) {
        throw "La branche '$branch' n'a pas de branche distante. Premier push à faire à la main : git push -u origin $branch"
    }

    Write-StyxInfo "Distante  : $($upstream.Output[0])"

    # --- Commits à pousser ---
    $pending = Invoke-StyxNativeQuery -FilePath "git" -Arguments @("-C", $root, "log", "--oneline", "@{u}..HEAD")

    if ($pending.ExitCode -ne 0) {
        throw "Impossible de lister les commits à pousser (git log)."
    }

    if ($pending.Output.Count -eq 0) {
        Write-StyxSuccess "Rien à pousser : la branche '$branch' est à jour avec $($upstream.Output[0])."
        exit 0
    }

    Write-Host ""
    Write-StyxInfo "Commit(s) à pousser : $($pending.Output.Count)"
    $pending.Output | ForEach-Object { Write-StyxInfo "  $_" }

    # --- Build ---
    if ($SkipBuild) {
        Write-StyxInfo "Build ignoré (-SkipBuild)."
    }
    else {
        & (Join-Path $PSScriptRoot "build.ps1")
        if ($LASTEXITCODE -ne 0) { throw "Le build a échoué : push annulé." }
    }

    # --- Push ---
    Write-StyxStep "git push"
    Invoke-StyxNative -FilePath "git" -Description "git push" -Arguments @("-C", $root, "push")

    Write-StyxSuccess "Vérification OK et push terminé."
    exit 0
}
catch {
    Write-StyxFailure $_.Exception.Message
    exit 1
}
