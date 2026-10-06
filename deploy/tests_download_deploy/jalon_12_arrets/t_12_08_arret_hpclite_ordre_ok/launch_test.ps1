<#
.SYNOPSIS
    Jalon 12 - Arrêt des applications - scénario t_12_08_arret_hpclite_ordre_ok

.DESCRIPTION
    OBJECTIF

        HpcLite est arrêté dans l'ordre : Agent, Scheduler, puis Runners.

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

        1. Créer un package de test (il n'est pas installé à ce jalon).
        2. Démarrer les services Scheduler et Agent.
        3. Exécuter : download_deploy.ps1 -d <RacineReelle> -STJ -PackageFile
           <package> -Force
        4. À la fin, le lanceur remet les services et le pool dans leur état
           initial.

    RÉSULTAT ATTENDU

        Succès : download_deploy.ps1 doit se terminer avec le code 0.
        Code 0. Ordre Agent, Scheduler, Runners ; les deux services Stopped.

    NETTOYAGE (automatique, même en cas d'erreur)

        Clear-TestEnvironment défait tout ce que ce test a créé ou modifié :
        dossiers et processus factices, variables d'environnement, état des
        services et du pool IIS, marqueurs version.txt, sauvegardes créées.

.NOTES
    Lancement : depuis ce dossier, .\launch_test.ps1
    (ou tout le jalon : ..\..\run_jalon.ps1 -Jalon 12)

    Codes de sortie de CE lanceur :
      0  TEST RÉUSSI   le comportement observé est celui attendu
      1  TEST ÉCHOUÉ   au moins une vérification a échoué
      2  NON EXÉCUTÉ   prérequis absent ou erreur de préparation

    download_deploy.ps1 (ce dossier) = script de production avec
    $script:JalonCible = 12 : il s'arrête volontairement après le jalon 12.
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
        -Jalon 12 `
        -Objectif "HpcLite est arrêté dans l'ordre : Agent, Scheduler, puis Runners." `
        -ResultatAttendu "Succès" `
        -CodeAttendu 0 `
        -EnvironnementReel

    # --- Préparation ---
    $config = Get-TestConfig
    $package = New-TestPackage
    $scriptUnderTest = New-ScriptUnderTest
    Set-ServiceStatus -Name $config.ServiceScheduler -Status Running
    Set-ServiceStatus -Name $config.ServiceAgent -Status Running

    # --- Exécution ---
    $result = Invoke-ScriptUnderTest -ScriptPath $scriptUnderTest -Arguments @("-d", $config.RacineReelle, "-STJ", "-PackageFile", $package, "-Force")

    # --- Vérifications ---
    Assert-ExitCode -Result $result -Expected 0
    $agentIndex = $result.Output.IndexOf("Arrêt du service HpcLite Agent")
    $schedulerIndex = $result.Output.IndexOf("Arrêt du service HpcLite Scheduler")
    $runnerIndex = $result.Output.IndexOf("HpcLite Runner :", [Math]::Max($schedulerIndex, 0))
    Assert-Condition -Condition ($agentIndex -ge 0 -and $schedulerIndex -gt $agentIndex) -Description "Agent arrêté avant le Scheduler"
    Assert-Condition -Condition ($runnerIndex -gt $schedulerIndex) -Description "Runners traités après le Scheduler"
    Assert-Condition -Condition ((Get-ServiceStatus -Name $config.ServiceAgent) -eq "Stopped") -Description "service Agent arrêté"
    Assert-Condition -Condition ((Get-ServiceStatus -Name $config.ServiceScheduler) -eq "Stopped") -Description "service Scheduler arrêté"
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
