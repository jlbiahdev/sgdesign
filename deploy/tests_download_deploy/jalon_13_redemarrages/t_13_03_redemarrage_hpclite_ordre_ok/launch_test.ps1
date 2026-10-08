<#
.SYNOPSIS
    Jalon 13 - Redémarrage des applications - scénario t_13_03_redemarrage_hpclite_ordre_ok

.DESCRIPTION
    OBJECTIF

        HpcLite redémarre dans l'ordre : Scheduler, puis Agent.

    PRÉCONDITIONS

        - Console Windows PowerShell 5.1 ouverte en tant qu'administrateur.
        - Lecteur D: disponible ; _common\test-config.psd1 renseigné.
        - Environnement réel de test complet et distinct de la production
          (vérifié automatiquement).
        - Environnement réel de test complet (RacineReelle) : vrais binaires,
          trois services Windows pointant sur RacineReelle, pool IIS de test.
        - L'état des services et du pool est mémorisé au début et restauré à
          la fin du test.

    ÉTAPES

        1. Créer un package de test (il n'est PAS installé : le jalon 13
           arrête puis redémarre seulement).
        2. Démarrer Scheduler et Agent.
        3. Exécuter : download_deploy.ps1 -d <RacineReelle> -STJ -PackageFile
           <package> -Force

    RÉSULTAT ATTENDU

        Succès : download_deploy.ps1 doit se terminer avec le code 0.
        Code 0. Scheduler puis Agent redémarrés ; tous deux Running.

    NETTOYAGE (automatique, même en cas d'erreur)

        Clear-TestEnvironment défait tout ce que ce test a créé ou modifié :
        dossiers et processus factices, variables d'environnement, état des
        services et du pool IIS, marqueurs version.txt, sauvegardes créées.

.NOTES
    Lancement : depuis ce dossier, .\launch_test.ps1
    (ou tout le jalon : ..\..\run_jalon.ps1 -Jalon 13)

    Codes de sortie de CE lanceur :
      0  TEST RÉUSSI   le comportement observé est celui attendu
      1  TEST ÉCHOUÉ   au moins une vérification a échoué
      2  NON EXÉCUTÉ   prérequis absent ou erreur de préparation

    download_deploy.ps1 (ce dossier) = version INCRÉMENTALE du jalon 13 :
    uniquement le code des jalons 0 à 13, terminé par « TEST TERMINÉ ».
    Code ajouté par ce jalon : ..\CHANGEMENTS.md
    Fichier généré par _tools\Build-JalonVersions.ps1 : ne pas le modifier.
    Les adaptations propres à ce test sont faites par le lanceur dans une
    copie temporaire.
#>

#requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Boîte à outils commune (préparation, exécution, vérifications, nettoyage).
Import-Module (Join-Path $PSScriptRoot "..\..\_common\TestHelpers.psm1") -Force

try {
    # En-tête et prérequis. Un prérequis absent lève « PREREQUIS : ... » :
    # le corps du test n'est pas exécuté et le verdict sera NON EXÉCUTÉ.
    Start-Test -ScenarioRoot $PSScriptRoot `
        -Jalon 13 `
        -Objectif "HpcLite redémarre dans l'ordre : Scheduler, puis Agent." `
        -ResultatAttendu "Succès" `
        -CodeAttendu 0 `
        -EnvironnementReel

    # --- Préparation ---
    $config = Get-TestConfig
    $package = New-TestPackage
    $scriptUnderTest = New-ScriptUnderTest
    Set-ServiceStatus -Name $config.ServiceScheduler -Status Running
    Set-ServiceStatus -Name $config.ServiceAgent -Status Running
    $stateBeforeRun = Get-ApplicationState

    # --- Exécution ---
    $result = Invoke-ScriptUnderTest -ScriptPath $scriptUnderTest -Arguments @("-d", $config.RacineReelle, "-STJ", "-PackageFile", $package, "-Force")

    # --- Vérifications ---
    Assert-ExitCode -Result $result -Expected 0
    Assert-OutputMatch -Result $result -Pattern 'JALON 13 ATTEINT' -Description "arrêt volontaire au jalon 13"
    $schedulerStart = $result.Output.IndexOf("Démarrage du service HpcLite Scheduler")
    $agentStart = $result.Output.IndexOf("Démarrage du service HpcLite Agent")
    Assert-Condition -Condition ($schedulerStart -ge 0 -and $agentStart -gt $schedulerStart) -Description "Scheduler redémarré avant l'Agent"
    Assert-Condition -Condition ((Get-ServiceStatus -Name $config.ServiceAgent) -eq "Running") -Description "Agent Running"
    Assert-Condition -Condition ((Get-ServiceStatus -Name $config.ServiceScheduler) -eq "Running") -Description "Scheduler Running"
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
