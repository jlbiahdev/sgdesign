<#
.SYNOPSIS
    Jalon 16 - Rollback - scénario t_16_07_demarrage_instable_rollback_ko

.DESCRIPTION
    OBJECTIF

        Une application qui démarre puis s'arrête quelques secondes plus tard
        est détectée (contrôle de stabilité) : rollback et relance de
        l'ancienne version.

    PRÉCONDITIONS

        - Console Windows PowerShell 5.1 ouverte en tant qu'administrateur.
        - Lecteur D: disponible ; _common\test-config.psd1 renseigné.
        - Mode test (processus factices). Le Taskflow du package démarre puis
          s'arrête après 1 s.
        - test-config.psd1 : StabiliteDemarrageSecondes (3 s par défaut).

    ÉTAPES

        1. Créer un environnement factice ; démarrer Taskflow factice.
        2. Créer un package dont l'exécutable Taskflow s'arrête seul après 1
           s.
        3. Exécuter : download_deploy.ps1 -d <racine factice> -STP
           -PackageFile <package> -Force

    RÉSULTAT ATTENDU

        Échec contrôlé : download_deploy.ps1 doit se terminer avec le code 1.
        Code 1. « a démarré puis s'est arrêté » ; taskflow = ancienne-version
        ; Taskflow (ancienne version) relancé.

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

    download_deploy.ps1 (ce dossier) = script de production complet.
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
        -Jalon 16 `
        -Objectif "Une application qui démarre puis s'arrête quelques secondes plus tard est détectée (contrôle de stabilité) : rollback et relance de l'ancienne version." `
        -ResultatAttendu "Échec contrôlé" `
        -CodeAttendu 1

    # --- Préparation ---
    $fake = New-FakeEnvironment
    $package = New-TestPackage -ExecutablesInstables @("taskflow")
    $scriptUnderTest = New-ScriptUnderTest -ModeExecutable
    Start-FakeProcess -ExecutablePath $fake.TaskflowExe | Out-Null

    # --- Exécution ---
    $result = Invoke-ScriptUnderTest -ScriptPath $scriptUnderTest -Arguments @("-d", $fake.Root, "-STP", "-PackageFile", $package, "-Force")

    # --- Vérifications ---
    Assert-ExitCode -Result $result -Expected 1
    Assert-OutputMatch -Result $result -Pattern "a démarré puis s'est arrêté" -Description "arrêt après démarrage détecté"
    Assert-OutputMatch -Result $result -Pattern 'STP a été restauré' -Description "taskflow restauré"
    Assert-Condition -Condition ((Get-VersionMarker -Directory $fake.TaskflowDir) -eq "ancienne-version") -Description "taskflow : ancienne version"
    Assert-Condition -Condition ((Get-ProcessCountByPath -ExecutablePath $fake.TaskflowExe) -eq 1) -Description "Taskflow (ancienne version) relancé et stable"
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
