<#
.SYNOPSIS
    Jalon 16 - Rollback - scénario t_16_06_rollback_mode_test_ko

.DESCRIPTION
    OBJECTIF

        En mode test, une erreur après installation déclenche le rollback et
        relance les processus.

    PRÉCONDITIONS

        - Console Windows PowerShell 5.1 ouverte en tant qu'administrateur.
        - Lecteur D: disponible ; _commun\test-config.psd1 renseigné.
        - Mode test (processus factices). Le package contient des exécutables
          lançables.

    ÉTAPES

        1. Créer un environnement factice ; démarrer Taskflow, Agent et
           Scheduler factices.
        2. Préparer une copie du script avec une erreur volontaire après
           l'installation du premier composant.
        3. Exécuter : download_deploy.ps1 -d <racine factice> -STP -STJ
           -PackageFile <package> -Force

    RÉSULTAT ATTENDU

        Échec contrôlé : download_deploy.ps1 doit se terminer avec le code 1.
        Code 1. taskflow et HpcLite = ancienne-version ; Taskflow, Agent,
        Scheduler relancés.

    NETTOYAGE (automatique, même en cas d'erreur)

        Clear-TestEnvironment défait tout ce que ce test a créé ou modifié :
        dossiers et processus factices, variables d'environnement, état des
        services et du pool IIS, marqueurs version.txt, sauvegardes créées.

.NOTES
    Lancement : depuis ce dossier, .\launch_test.ps1
    (ou tout le jalon : ..\..\run_jalon.ps1 -Jalon 16)

    Codes de sortie de CE lanceur :
      0  TEST RÉUSSI   le comportement observé est celui attendu
      1  TEST ÉCHOUÉ   au moins une vérification a échoué
      2  NON EXÉCUTÉ   prérequis absent ou erreur de préparation

    download_deploy.ps1 (ce dossier) = script de production, sans point d'arrêt.
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
        -Jalon 16 `
        -Objectif "En mode test, une erreur après installation déclenche le rollback et relance les processus." `
        -ResultatAttendu "Échec contrôlé" `
        -CodeAttendu 1

    # --- Préparation ---
    $fake = New-FakeEnvironment
    $package = New-TestPackage -ExecutablesLancables
    $scriptUnderTest = New-ScriptUnderTest -ModeExecutable -InjecterErreur "apres-installation-composant"
    Start-FakeProcess -ExecutablePath $fake.TaskflowExe | Out-Null
    Start-FakeProcess -ExecutablePath $fake.AgentExe | Out-Null
    Start-FakeProcess -ExecutablePath $fake.SchedulerExe | Out-Null

    # --- Exécution ---
    $result = Invoke-ScriptUnderTest -ScriptPath $scriptUnderTest -Arguments @("-d", $fake.Root, "-STP", "-STJ", "-PackageFile", $package, "-Force")

    # --- Vérifications ---
    Assert-ExitCode -Result $result -Expected 1
    Assert-OutputMatch -Result $result -Pattern 'STP a été restauré' -Description "taskflow restauré"
    Assert-Condition -Condition ((Get-VersionMarker -Directory $fake.TaskflowDir) -eq "ancienne-version") -Description "taskflow : ancienne version"
    Assert-Condition -Condition ((Get-VersionMarker -Directory $fake.HpcLiteDir) -eq "ancienne-version") -Description "HpcLite : ancienne version (jamais remplacé)"
    Assert-Condition -Condition ((Get-ProcessCountByPath -ExecutablePath $fake.TaskflowExe) -eq 1) -Description "Taskflow relancé"
    Assert-Condition -Condition ((Get-ProcessCountByPath -ExecutablePath $fake.AgentExe) -eq 1) -Description "Agent relancé"
    Assert-Condition -Condition ((Get-ProcessCountByPath -ExecutablePath $fake.SchedulerExe) -eq 1) -Description "Scheduler relancé"
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
