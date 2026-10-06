<#
.SYNOPSIS
    Jalon 8 - Préparation du staging - scénario t_8_06_aucune_application_arretee_ok

.DESCRIPTION
    OBJECTIF

        Jusqu'au staging inclus, aucune application en cours n'est arrêtée.

    PRÉCONDITIONS

        - Console Windows PowerShell 5.1 ouverte en tant qu'administrateur.
        - Lecteur D: disponible ; _commun\test-config.psd1 renseigné.

    ÉTAPES

        1. Créer un environnement factice et démarrer des processus factices
           (Taskflow, Agent, Scheduler, 2 Runners).
        2. Exécuter : download_deploy.ps1 -d <racine factice> -STP -STJ
           -PackageFile <package>
        3. Recompter les processus.

    RÉSULTAT ATTENDU

        Succès : download_deploy.ps1 doit se terminer avec le code 0.
        Code 0. Tous les processus factices tournent toujours.

    NETTOYAGE (automatique, même en cas d'erreur)

        Clear-TestEnvironment défait tout ce que ce test a créé ou modifié :
        dossiers et processus factices, variables d'environnement, état des
        services et du pool IIS, marqueurs version.txt, sauvegardes créées.

.NOTES
    Lancement : depuis ce dossier, .\launch_test.ps1
    (ou tout le jalon : ..\..\run_jalon.ps1 -Jalon 8)

    Codes de sortie de CE lanceur :
      0  TEST RÉUSSI   le comportement observé est celui attendu
      1  TEST ÉCHOUÉ   au moins une vérification a échoué
      2  NON EXÉCUTÉ   prérequis absent ou erreur de préparation

    download_deploy.ps1 (ce dossier) = script de production avec
    $script:JalonCible = 8 : il s'arrête volontairement après le jalon 8.
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
        -Jalon 8 `
        -Objectif "Jusqu'au staging inclus, aucune application en cours n'est arrêtée." `
        -ResultatAttendu "Succès" `
        -CodeAttendu 0

    # --- Préparation ---
    $fake = New-FakeEnvironment
    $package = New-TestPackage
    $scriptUnderTest = New-ScriptUnderTest -ModeExecutable

    Start-FakeProcess -ExecutablePath $fake.TaskflowExe | Out-Null
    Start-FakeProcess -ExecutablePath $fake.AgentExe | Out-Null
    Start-FakeProcess -ExecutablePath $fake.SchedulerExe | Out-Null
    Start-FakeProcess -ExecutablePath $fake.RunnerExe -Count 2 | Out-Null

    # --- Exécution ---
    $result = Invoke-ScriptUnderTest -ScriptPath $scriptUnderTest -Arguments @("-d", $fake.Root, "-STP", "-STJ", "-PackageFile", $package)

    # --- Vérifications ---
    Assert-ExitCode -Result $result -Expected 0
    Assert-Condition -Condition ((Get-ProcessCountByPath -ExecutablePath $fake.TaskflowExe) -eq 1) -Description "Taskflow tourne toujours"
    Assert-Condition -Condition ((Get-ProcessCountByPath -ExecutablePath $fake.AgentExe) -eq 1) -Description "Agent tourne toujours"
    Assert-Condition -Condition ((Get-ProcessCountByPath -ExecutablePath $fake.SchedulerExe) -eq 1) -Description "Scheduler tourne toujours"
    Assert-Condition -Condition ((Get-ProcessCountByPath -ExecutablePath $fake.RunnerExe) -eq 2) -Description "les 2 Runners tournent toujours"
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
