<#
.SYNOPSIS
    Jalon 11 - Mémorisation de l'état initial - scénario t_11_04_etat_services_reels_ok

.DESCRIPTION
    OBJECTIF

        Sur l'environnement réel, l'état enregistré correspond à l'état réel
        des services et du pool.

    PRÉCONDITIONS

        - Console Windows PowerShell 5.1 ouverte en tant qu'administrateur.
        - Lecteur D: disponible ; _commun\test-config.psd1 renseigné.
        - Environnement réel de test complet et distinct de la production
          (vérifié automatiquement).
        - Environnement réel de test complet (RacineReelle) : vrais binaires,
          trois services Windows pointant sur RacineReelle, pool IIS de test.
        - L'état des services et du pool est mémorisé au début et restauré à
          la fin du test.

    ÉTAPES

        1. Exécuter : download_deploy.ps1 -d <RacineReelle> -STP -STX -STJ
           -PackageFile <package>
        2. Comparer state.json à l'état réel des services et du pool.

    RÉSULTAT ATTENDU

        Succès : download_deploy.ps1 doit se terminer avec le code 0.
        Code 0. Chaque XxxWasRunning vaut true si et seulement si le service
        (ou le pool) est démarré.

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

    download_deploy.ps1 (ce dossier) = script de production avec
    $script:JalonCible = 11 : il s'arrête volontairement après le jalon 11.
    Ne jamais le modifier pour faire réussir ce test : les adaptations
    nécessaires sont faites par le lanceur dans une copie temporaire.
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
        -Objectif "Sur l'environnement réel, l'état enregistré correspond à l'état réel des services et du pool." `
        -ResultatAttendu "Succès" `
        -CodeAttendu 0 `
        -EnvironnementReel

    # --- Préparation ---
    $config = Get-TestConfig
    $package = New-TestPackage
    $scriptUnderTest = New-ScriptUnderTest
    $appState = Get-ApplicationState

    # --- Exécution ---
    $result = Invoke-ScriptUnderTest -ScriptPath $scriptUnderTest -Arguments @("-d", $config.RacineReelle, "-STP", "-STX", "-STJ", "-PackageFile", $package)

    # --- Vérifications ---
    Assert-ExitCode -Result $result -Expected 0
    $fake = [pscustomobject] @{ Root = $config.RacineReelle }
    $log = Get-LatestLog -Root $fake.Root
    $stateFile = if ($null -ne $log) { [IO.Path]::ChangeExtension($log.FullName, ".state.json") } else { "" }
    Assert-Condition -Condition ($stateFile -ne "" -and (Test-Path -LiteralPath $stateFile)) -Description "fichier state.json créé à côté du journal"
    $savedState = if ($stateFile -ne "" -and (Test-Path -LiteralPath $stateFile)) { Get-Content -LiteralPath $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }

    if ($null -ne $savedState) {
        Assert-Condition -Condition ($savedState.TaskflowWasRunning -eq ($appState.Taskflow -eq "Running")) -Description "TaskflowWasRunning conforme ($($appState.Taskflow))"
        Assert-Condition -Condition ($savedState.AgentWasRunning -eq ($appState.Agent -eq "Running")) -Description "AgentWasRunning conforme ($($appState.Agent))"
        Assert-Condition -Condition ($savedState.SchedulerWasRunning -eq ($appState.Scheduler -eq "Running")) -Description "SchedulerWasRunning conforme ($($appState.Scheduler))"
        Assert-Condition -Condition ($savedState.ApiWasRunning -eq ($appState.Pool -eq "Started")) -Description "ApiWasRunning conforme ($($appState.Pool))"
    }

    Assert-ApplicationStateUnchanged
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
