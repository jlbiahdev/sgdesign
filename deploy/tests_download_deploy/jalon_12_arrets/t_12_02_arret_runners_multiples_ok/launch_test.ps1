<#
.SYNOPSIS
    Jalon 12 - Arrêt des applications - scénario t_12_02_arret_runners_multiples_ok

.DESCRIPTION
    OBJECTIF

        Agent, Scheduler et tous les Runners (mode test) sont arrêtés.

    PRÉCONDITIONS

        - Console Windows PowerShell 5.1 ouverte en tant qu'administrateur.
        - Lecteur D: disponible ; _commun\test-config.psd1 renseigné.
        - Mode test (processus factices) : aucune vraie application n'est
          touchée.

    ÉTAPES

        1. Créer un environnement factice et un package de test.
        2. Démarrer Agent, Scheduler et 3 Runners factices.
        3. Exécuter : download_deploy.ps1 -d <racine factice> -STJ
           -PackageFile <package> -Force

    RÉSULTAT ATTENDU

        Succès : download_deploy.ps1 doit se terminer avec le code 0.
        Code 0. Agent 0, Scheduler 0, Runner 0.

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

    download_deploy.ps1 (ce dossier) = version INCRÉMENTALE du jalon 12 :
    uniquement le code des jalons 0 à 12, terminé par « TEST TERMINÉ ».
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
        -Jalon 12 `
        -Objectif "Agent, Scheduler et tous les Runners (mode test) sont arrêtés." `
        -ResultatAttendu "Succès" `
        -CodeAttendu 0

    # --- Préparation ---
    $fake = New-FakeEnvironment
    $package = New-TestPackage
    $scriptUnderTest = New-ScriptUnderTest -ModeExecutable
    Start-FakeProcess -ExecutablePath $fake.AgentExe | Out-Null
    Start-FakeProcess -ExecutablePath $fake.SchedulerExe | Out-Null
    Start-FakeProcess -ExecutablePath $fake.RunnerExe -Count 3 | Out-Null

    # --- Exécution ---
    $result = Invoke-ScriptUnderTest -ScriptPath $scriptUnderTest -Arguments @("-d", $fake.Root, "-STJ", "-PackageFile", $package, "-Force")

    # --- Vérifications ---
    Assert-ExitCode -Result $result -Expected 0
    Assert-OutputMatch -Result $result -Pattern 'HpcLite Runner : 3 processus à arrêter' -Description "3 Runners à arrêter"
    Assert-Condition -Condition ((Get-ProcessCountByPath -ExecutablePath $fake.AgentExe) -eq 0) -Description "plus aucun Agent"
    Assert-Condition -Condition ((Get-ProcessCountByPath -ExecutablePath $fake.SchedulerExe) -eq 0) -Description "plus aucun Scheduler"
    Assert-Condition -Condition ((Get-ProcessCountByPath -ExecutablePath $fake.RunnerExe) -eq 0) -Description "plus aucun Runner"
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
