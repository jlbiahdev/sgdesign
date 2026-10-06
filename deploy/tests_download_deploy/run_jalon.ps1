#requires -Version 5.1

<#
.SYNOPSIS
    Exécute tous les scénarios d'un jalon et affiche un bilan.

.DESCRIPTION
    Pour le jalon demandé, lance chaque t_*\launch_test.ps1 dans un
    processus Windows PowerShell 5.1 séparé, dans l'ordre alphabétique,
    puis affiche un tableau récapitulatif :

        RÉUSSI       le scénario a produit le résultat attendu (code 0)
        ÉCHOUÉ       le résultat attendu n'a pas été obtenu   (code 1)
        NON EXÉCUTÉ  prérequis absent ou erreur de préparation (code 2)

    Le bilan est aussi enregistré dans resultats\jalon_<N>_<date>.csv,
    à reporter dans le tableau de suivi du README.

    Jalons 12 et plus : ils arrêtent de vraies applications sur la
    machine de test. Une confirmation « OUI » est demandée.

.PARAMETER Jalon
    Numéro du jalon (0 à 19).

.PARAMETER Filtre
    Optionnel : ne lance que les scénarios dont le nom contient ce texte.
    Exemple : -Filtre "_ko"

.EXAMPLE
    .\run_jalon.ps1 -Jalon 0

.EXAMPLE
    .\run_jalon.ps1 -Jalon 4 -Filtre "stj"

.NOTES
    Codes de sortie : 0 si tous les scénarios lancés ont réussi, 1 sinon.
    Le scénario t_0_08_administrateur_ko exige une console NON
    administrateur : il apparaîtra « NON EXÉCUTÉ » ici, c'est normal.
    Lancez-le à part (voir README).
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateRange(0, 19)]
    [int] $Jalon,

    [string] $Filtre = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$jalonDirectory = @(Get-ChildItem -LiteralPath $PSScriptRoot -Directory -Filter "jalon_$($Jalon)_*")

if ($jalonDirectory.Count -ne 1) {
    throw "Dossier du jalon $Jalon introuvable (ou ambigu) dans $PSScriptRoot."
}

$scenarios = @(
    Get-ChildItem -LiteralPath $jalonDirectory[0].FullName -Directory -Filter "t_*" |
        Where-Object { $_.Name -like "*$Filtre*" } |
        Sort-Object Name
)

if ($scenarios.Count -eq 0) {
    throw "Aucun scénario à lancer."
}

Write-Host ""
Write-Host "Jalon $Jalon : $($jalonDirectory[0].Name)" -ForegroundColor Cyan
Write-Host "Scénarios : $($scenarios.Count)" -ForegroundColor Cyan

if ($Jalon -ge 12) {
    Write-Host ""
    Write-Host "ATTENTION : ce jalon arrête et redémarre de vraies applications" -ForegroundColor Yellow
    Write-Host "et remplace des fichiers dans l'environnement réel de test." -ForegroundColor Yellow
    Write-Host "Ne JAMAIS l'exécuter sur un serveur de production." -ForegroundColor Yellow

    $answer = Read-Host "Tapez OUI pour continuer"

    if ($answer -cne "OUI") {
        Write-Host "Annulé." -ForegroundColor Yellow
        exit 1
    }
}

$powershell = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
$results = @()

foreach ($scenario in $scenarios) {
    $launcher = Join-Path $scenario.FullName "launch_test.ps1"

    $start = Get-Date
    & $powershell -NoProfile -ExecutionPolicy Bypass -File $launcher
    $code = $LASTEXITCODE
    $duration = [int] ((Get-Date) - $start).TotalSeconds

    $verdict = switch ($code) {
        0       { "RÉUSSI" }
        1       { "ÉCHOUÉ" }
        2       { "NON EXÉCUTÉ" }
        default { "CODE $code" }
    }

    $results += [pscustomobject] @{
        Scenario = $scenario.Name
        Verdict  = $verdict
        Code     = $code
        Duree_s  = $duration
    }
}

Write-Host ""
Write-Host ("=" * 70) -ForegroundColor Cyan
Write-Host "BILAN DU JALON $Jalon" -ForegroundColor Cyan
Write-Host ("=" * 70) -ForegroundColor Cyan

foreach ($result in $results) {
    $color = switch ($result.Code) { 0 { "Green" } 1 { "Red" } default { "Yellow" } }
    Write-Host ("{0,-12} {1,-55} {2,4}s" -f $result.Verdict, $result.Scenario, $result.Duree_s) -ForegroundColor $color
}

$passed  = @($results | Where-Object Code -eq 0).Count
$failed  = @($results | Where-Object Code -eq 1).Count
$skipped = $results.Count - $passed - $failed

Write-Host ("-" * 70) -ForegroundColor Cyan
Write-Host "Réussis : $passed   Échoués : $failed   Non exécutés : $skipped" -ForegroundColor Cyan

$resultsDirectory = Join-Path $PSScriptRoot "resultats"
New-Item -Path $resultsDirectory -ItemType Directory -Force | Out-Null

$csv = Join-Path $resultsDirectory ("jalon_{0}_{1}.csv" -f $Jalon, (Get-Date -Format "yyyyMMdd-HHmmss"))
$results | Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8 -Delimiter ";"

Write-Host "Bilan enregistré : $csv" -ForegroundColor Cyan

if ($failed -gt 0 -or $skipped -gt 0) { exit 1 }
exit 0
