<#
.SYNOPSIS
    Jalon 15 - Installation des fichiers - scénario t_15_06_installation_mode_test_ok

.DESCRIPTION
    OBJECTIF

        En mode test, le déploiement complet (arrêt, sauvegarde, installation,
        redémarrage) fonctionne sans environnement réel.

    PRÉCONDITIONS

        - Console Windows PowerShell 5.1 ouverte en tant qu'administrateur.
        - Lecteur D: disponible ; _commun\test-config.psd1 renseigné.
        - Mode test (processus factices). Le package contient des exécutables
          lançables.

    ÉTAPES

        1. Créer un environnement factice ; démarrer Taskflow, Agent,
           Scheduler et 2 Runners factices.
        2. Exécuter : download_deploy.ps1 -d <racine factice> -STP -STJ
           -PackageFile <package> -Force

    RÉSULTAT ATTENDU

        Succès : download_deploy.ps1 doit se terminer avec le code 0.
        Code 0. Nouvelle version installée ; Taskflow, Agent, Scheduler
        relancés ; aucun Runner relancé par le script.

    NETTOYAGE (automatique, même en cas d'erreur)

        Clear-TestEnvironment défait tout ce que ce test a créé ou modifié :
        dossiers et processus factices, variables d'environnement, état des
        services et du pool IIS, marqueurs version.txt, sauvegardes créées.

.NOTES
    Lancement : depuis ce dossier, .\launch_test.ps1
    (ou tout le jalon : ..\..\run_jalon.ps1 -Jalon 15)

    Codes de sortie de CE lanceur :
      0  TEST RÉUSSI   le comportement observé est celui attendu
      1  TEST ÉCHOUÉ   au moins une vérification a échoué
      2  NON EXÉCUTÉ   prérequis absent ou erreur de préparation

    download_deploy.ps1 (ce dossier) = script de production complet.
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
        -Jalon 15 `
        -Objectif "En mode test, le déploiement complet (arrêt, sauvegarde, installation, redémarrage) fonctionne sans environnement réel." `
        -ResultatAttendu "Succès" `
        -CodeAttendu 0

    # --- Préparation ---
    $fake = New-FakeEnvironment
    $package = New-TestPackage -ExecutablesLancables
    $scriptUnderTest = New-ScriptUnderTest -ModeExecutable
    Start-FakeProcess -ExecutablePath $fake.TaskflowExe | Out-Null
    Start-FakeProcess -ExecutablePath $fake.AgentExe | Out-Null
    Start-FakeProcess -ExecutablePath $fake.SchedulerExe | Out-Null
    Start-FakeProcess -ExecutablePath $fake.RunnerExe -Count 2 | Out-Null

    # --- Exécution ---
    $result = Invoke-ScriptUnderTest -ScriptPath $scriptUnderTest -Arguments @("-d", $fake.Root, "-STP", "-STJ", "-PackageFile", $package, "-Force")

    # --- Vérifications ---
    Assert-ExitCode -Result $result -Expected 0
    Assert-OutputMatch -Result $result -Pattern 'DÉPLOIEMENT TERMINÉ AVEC SUCCÈS' -Description "succès annoncé"
    Assert-Condition -Condition ((Get-VersionMarker -Directory $fake.TaskflowDir) -eq "nouvelle-version") -Description "taskflow : nouvelle version"
    Assert-Condition -Condition ((Get-VersionMarker -Directory $fake.HpcLiteDir) -eq "nouvelle-version") -Description "HpcLite : nouvelle version"
    Assert-Condition -Condition ((Get-ProcessCountByPath -ExecutablePath $fake.TaskflowExe) -eq 1) -Description "Taskflow relancé"
    Assert-Condition -Condition ((Get-ProcessCountByPath -ExecutablePath $fake.AgentExe) -eq 1) -Description "Agent relancé"
    Assert-Condition -Condition ((Get-ProcessCountByPath -ExecutablePath $fake.SchedulerExe) -eq 1) -Description "Scheduler relancé"
    Assert-Condition -Condition ((Get-ProcessCountByPath -ExecutablePath $fake.RunnerExe) -eq 0) -Description "aucun Runner relancé par le script"
    Assert-OutputMatch -Result $result -Pattern '2 Runner\(s\) ont été arrêtés brutalement' -Description "Runners arrêtés signalés"
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
