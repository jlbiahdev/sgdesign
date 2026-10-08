<#
.SYNOPSIS
    Jalon 12 - Arrêt des applications - scénario t_12_04_confirmation_non_interactive_ko

.DESCRIPTION
    OBJECTIF

        Sans -Force, en session non interactive, le script annule avant tout
        arrêt.

    PRÉCONDITIONS

        - Console Windows PowerShell 5.1 ouverte en tant qu'administrateur.
        - Lecteur D: disponible ; _common\test-config.psd1 renseigné.
        - Mode test (processus factices) : aucune vraie application n'est
          touchée.

    ÉTAPES

        1. Créer un environnement factice et un package de test.
        2. Démarrer un Taskflow factice.
        3. Exécuter SANS -Force (session non interactive) :
           download_deploy.ps1 -d <racine factice> -STP -PackageFile <package>

    RÉSULTAT ATTENDU

        Annulation : download_deploy.ps1 doit se terminer avec le code 2.
        Code 2 (annulation). Le Taskflow factice tourne toujours.

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
        -Jalon 12 `
        -Objectif "Sans -Force, en session non interactive, le script annule avant tout arrêt." `
        -ResultatAttendu "Annulation" `
        -CodeAttendu 2

    # --- Préparation ---
    $fake = New-FakeEnvironment
    $package = New-TestPackage
    $scriptUnderTest = New-ScriptUnderTest -ModeExecutable
    Start-FakeProcess -ExecutablePath $fake.TaskflowExe | Out-Null

    # --- Exécution ---
    $result = Invoke-ScriptUnderTest -ScriptPath $scriptUnderTest -Arguments @("-d", $fake.Root, "-STP", "-PackageFile", $package)

    # --- Vérifications ---
    Assert-ExitCode -Result $result -Expected 2
    Assert-OutputMatch -Result $result -Pattern 'Confirmation impossible' -Description "confirmation impossible signalée"
    Assert-OutputMatch -Result $result -Pattern 'Utilisez -Force' -Description "le message propose -Force"
    Assert-Condition -Condition ((Get-ProcessCountByPath -ExecutablePath $fake.TaskflowExe) -eq 1) -Description "Taskflow tourne toujours"
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
