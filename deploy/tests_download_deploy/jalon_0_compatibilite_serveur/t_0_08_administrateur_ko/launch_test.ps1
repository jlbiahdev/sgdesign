<#
.SYNOPSIS
    Jalon 0 - Compatibilité du serveur - scénario t_0_08_administrateur_ko

.DESCRIPTION
    OBJECTIF

        Le script refuse une console sans droits administrateur.

    PRÉCONDITIONS

        - Lecteur D: disponible ; _commun\test-config.psd1 renseigné.
        - Console PowerShell NON administrateur.
        - Lancer CE test depuis une console PowerShell NON administrateur
          (lancement manuel : run_jalon.ps1 le signalera « non exécuté »).

    ÉTAPES

        1. Depuis une console NON administrateur, exécuter :
           download_deploy.ps1 -d <RacineTestsAuto> -STP

    RÉSULTAT ATTENDU

        Échec contrôlé : download_deploy.ps1 doit se terminer avec le code 1.
        Code 1. Message « Ce script doit être exécuté en tant
        qu'administrateur ».

    NETTOYAGE (automatique, même en cas d'erreur)

        Clear-TestEnvironment défait tout ce que ce test a créé ou modifié :
        dossiers et processus factices, variables d'environnement, état des
        services et du pool IIS, marqueurs version.txt, sauvegardes créées.

.NOTES
    Lancement : depuis ce dossier, .\launch_test.ps1
    (ou tout le jalon : ..\..\run_jalon.ps1 -Jalon 0)

    Codes de sortie de CE lanceur :
      0  TEST RÉUSSI   le comportement observé est celui attendu
      1  TEST ÉCHOUÉ   au moins une vérification a échoué
      2  NON EXÉCUTÉ   prérequis absent ou erreur de préparation

    download_deploy.ps1 (ce dossier) = version INCRÉMENTALE du jalon 0 :
    uniquement le code des jalons 0 à 0, terminé par « TEST TERMINÉ ».
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
        -Jalon 0 `
        -Objectif "Le script refuse une console sans droits administrateur." `
        -ResultatAttendu "Échec contrôlé" `
        -CodeAttendu 1 `
        -NonAdministrateur

    # --- Préparation ---
    $scriptUnderTest = New-ScriptUnderTest

    # --- Exécution ---
    $result = Invoke-ScriptUnderTest -ScriptPath $scriptUnderTest -Arguments @("-d", (Get-TestConfig).RacineTestsAuto, "-STP")

    # --- Vérifications ---
    Assert-ExitCode -Result $result -Expected 1
    Assert-OutputMatch -Result $result -Pattern 'en tant qu.administrateur' -Description "le refus explique qu'il faut les droits administrateur"
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
