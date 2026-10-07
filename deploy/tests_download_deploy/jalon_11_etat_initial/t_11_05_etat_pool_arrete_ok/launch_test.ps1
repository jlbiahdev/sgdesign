<#
.SYNOPSIS
    Jalon 11 - Mémorisation de l'état initial - scénario t_11_05_etat_pool_arrete_ok

.DESCRIPTION
    OBJECTIF

        Un pool arrêté est enregistré ApiWasRunning = false.

    PRÉCONDITIONS

        - Console Windows PowerShell 5.1 ouverte en tant qu'administrateur.
        - Lecteur D: disponible ; _commun\test-config.psd1 renseigné.
        - Pool IIS de test existant (PoolIis).
        - IIS installé ; pool IIS de test existant. Son état est restauré à la
          fin.

    ÉTAPES

        1. Arrêter le pool de test.
        2. Exécuter : download_deploy.ps1 -d <racine factice> -STX
           -PackageFile <package>
        3. Lire state.json.

    RÉSULTAT ATTENDU

        Succès : download_deploy.ps1 doit se terminer avec le code 0.
        Code 0. ApiWasRunning = false.

    NETTOYAGE (automatique, même en cas d'erreur)

        Clear-TestEnvironment défait tout ce que ce test a créé ou modifié :
        dossiers et processus factices, variables d'environnement, état des
        services et du pool IIS, marqueurs version.txt, sauvegardes créées.

.NOTES
    Lancement : depuis ce dossier, .\launch_test.ps1
    (ou tout le jalon : ..\..\run_jalon.ps1 -Jalon 11)

    Codes de sortie de CE lanceur :
      0  TEST RÉUSSI   le comportement observé est celui attendu
      1  TEST ÉCHOUÉ   au moins une vérification a échoué
      2  NON EXÉCUTÉ   prérequis absent ou erreur de préparation

    download_deploy.ps1 (ce dossier) = version INCRÉMENTALE du jalon 11 :
    uniquement le code des jalons 0 à 11, terminé par « TEST TERMINÉ ».
    Code ajouté par ce jalon : ..\CHANGEMENTS.md
    Fichier généré par _outils\Build-JalonVersions.ps1 : ne pas le modifier.
    Les adaptations propres à ce test sont faites par le lanceur dans une
    copie temporaire.
#>

#requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Boîte à outils commune (préparation, exécution, vérifications, nettoyage).
Import-Module (Join-Path $PSScriptRoot "..\..\_commun\TestHelpers.psm1") -Force

try {
    # En-tête et prérequis. Un prérequis absent lève « PREREQUIS : ... » :
    # le corps du test n'est pas exécuté et le verdict sera NON EXÉCUTÉ.
    Start-Test -ScenarioRoot $PSScriptRoot `
        -Jalon 11 `
        -Objectif "Un pool arrêté est enregistré ApiWasRunning = false." `
        -ResultatAttendu "Succès" `
        -CodeAttendu 0 `
        -PoolIis

    # --- Préparation ---
    $fake = New-FakeEnvironment
    $package = New-TestPackage
    $scriptUnderTest = New-ScriptUnderTest
    Register-PoolRestore -State (Get-PoolState)
    Set-PoolState -State Stopped

    # --- Exécution ---
    $result = Invoke-ScriptUnderTest -ScriptPath $scriptUnderTest -Arguments @("-d", $fake.Root, "-STX", "-PackageFile", $package)

    # --- Vérifications ---
    Assert-ExitCode -Result $result -Expected 0
    $log = Get-LatestLog -Root $fake.Root
    $stateFile = if ($null -ne $log) { [IO.Path]::ChangeExtension($log.FullName, ".state.json") } else { "" }
    Assert-Condition -Condition ($stateFile -ne "" -and (Test-Path -LiteralPath $stateFile)) -Description "fichier state.json créé à côté du journal"
    $savedState = if ($stateFile -ne "" -and (Test-Path -LiteralPath $stateFile)) { Get-Content -LiteralPath $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }

    if ($null -ne $savedState) {
        Assert-Condition -Condition ($savedState.ApiWasRunning -eq $false) -Description "ApiWasRunning = false"
    }
}
catch {
    # Erreur du lanceur lui-même (prérequis, préparation) : test non exécuté.
    Register-TestError -ErrorRecord $_
}
finally {
    # Toujours exécuté : remet la machine dans son état initial.
    Clear-TestEnvironment
}

# Verdict : 0 = réussi, 1 = échoué, 2 = non exécuté.
exit (Complete-Test)
