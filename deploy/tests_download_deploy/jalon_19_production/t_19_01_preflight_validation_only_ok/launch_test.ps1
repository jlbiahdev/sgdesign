<#
.SYNOPSIS
    Jalon 19 - Validation en conditions réelles - scénario t_19_01_preflight_validation_only_ok

.DESCRIPTION
    OBJECTIF

        Pré-vol sur le serveur cible : le script de production, avec
        -ValidationOnly, valide tout sans rien arrêter.

    PRÉCONDITIONS

        - Console Windows PowerShell 5.1 ouverte en tant qu'administrateur.
        - Lecteur D: disponible ; _commun\test-config.psd1 renseigné.
        - Services Windows « TaskFlow Runner », « HpcLite Agent », « HpcLite
          Scheduler » installés.
        - Pool IIS de test existant (PoolIis).
        - À lancer sur le serveur CIBLE, juste avant le premier déploiement
          réel.
        - Variables Machine ARTIFACTORY_USERNAME, ARTIFACTORY_TOKEN,
          STYX_PACKAGE_URL définies (ou session).
        - RacineProduction renseignée dans test-config.psd1.
        - Aucune adaptation : le script est exécuté tel qu'il sera livré.

    ÉTAPES

        1. Exécuter : download_deploy.ps1 -d <RacineProduction> -STP -STX -STJ
           -ValidationOnly
        2. Vérifier qu'aucune application n'a changé d'état.

    RÉSULTAT ATTENDU

        Succès : download_deploy.ps1 doit se terminer avec le code 0.
        Code 0. « MODE VALIDATION » ; état des services et du pool inchangé ;
        aucun token affiché.

    NETTOYAGE (automatique, même en cas d'erreur)

        Clear-TestEnvironment défait tout ce que ce test a créé ou modifié :
        dossiers et processus factices, variables d'environnement, état des
        services et du pool IIS, marqueurs version.txt, sauvegardes créées.

.NOTES
    Lancement : depuis ce dossier, .\launch_test.ps1
    (ou tout le jalon : ..\..\run_jalon.ps1 -Jalon 19)

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
        -Jalon 19 `
        -Objectif "Pré-vol sur le serveur cible : le script de production, avec -ValidationOnly, valide tout sans rien arrêter." `
        -ResultatAttendu "Succès" `
        -CodeAttendu 0 `
        -ServicesReels `
        -PoolIis

    # --- Préparation ---
    $config = Get-TestConfig
    # Script de production tel quel : ni pool ni services de test.
    $scriptUnderTest = New-ScriptUnderTest -SansAdaptation
    $stateBefore = Format-ApplicationState -State (Get-ApplicationState)

    # --- Exécution ---
    $result = Invoke-ScriptUnderTest -ScriptPath $scriptUnderTest -Arguments @("-d", $config.RacineProduction, "-STP", "-STX", "-STJ", "-ValidationOnly")

    # --- Vérifications ---
    Assert-ExitCode -Result $result -Expected 0
    Assert-OutputMatch -Result $result -Pattern 'MODE VALIDATION' -Description "pré-vol terminé"
    Assert-Condition -Condition ((Format-ApplicationState -State (Get-ApplicationState)) -eq $stateBefore) -Description "aucune application n'a changé d'état"
    Assert-NoSecret -Result $result -Root $config.RacineProduction
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
