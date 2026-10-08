<#
.SYNOPSIS
    Jalon 18 - Test des combinaisons - scénario t_18_02_stp_stj_ok

.DESCRIPTION
    OBJECTIF

        Déploiement combiné -STP -STJ : seuls les composants sélectionnés sont
        remplacés.

    PRÉCONDITIONS

        - Console Windows PowerShell 5.1 ouverte en tant qu'administrateur.
        - Lecteur D: disponible ; _common\test-config.psd1 renseigné.
        - Environnement réel de test complet et distinct de la production
          (vérifié automatiquement).
        - Environnement réel de test complet (RacineReelle) : vrais binaires,
          trois services Windows pointant sur RacineReelle, pool IIS de test.
        - L'état des services et du pool est mémorisé au début et restauré à
          la fin du test.
        - Vrai package Styx disponible (PackageReel dans test-config.psd1).
        - ATTENTION : ce test REMPLACE réellement les fichiers de
          l'environnement de test.

    ÉTAPES

        1. Poser version.txt = ancienne-version dans taskflow, api et HpcLite.
        2. Créer une copie marquée du vrai package (version.txt =
           nouvelle-version).
        3. Exécuter : download_deploy.ps1 -d <RacineReelle> -STP -STJ
           -PackageFile <package marqué> -Force

    RÉSULTAT ATTENDU

        Succès : download_deploy.ps1 doit se terminer avec le code 0.
        Code 0. Composants sélectionnés en nouvelle version, autres intacts,
        état initial retrouvé.

    NETTOYAGE (automatique, même en cas d'erreur)

        Clear-TestEnvironment défait tout ce que ce test a créé ou modifié :
        dossiers et processus factices, variables d'environnement, état des
        services et du pool IIS, marqueurs version.txt, sauvegardes créées.

.NOTES
    Lancement : depuis ce dossier, .\launch_test.ps1
    (ou tout le jalon : ..\..\run_jalon.ps1 -Jalon 18)

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
        -Jalon 18 `
        -Objectif "Déploiement combiné -STP -STJ : seuls les composants sélectionnés sont remplacés." `
        -ResultatAttendu "Succès" `
        -CodeAttendu 0 `
        -EnvironnementReel

    # --- Préparation ---
    $config = Get-TestConfig
    Set-RealVersionMarkers
    $package = New-PackageFromReal
    $scriptUnderTest = New-ScriptUnderTest

    # --- Exécution ---
    $result = Invoke-ScriptUnderTest -ScriptPath $scriptUnderTest -Arguments @("-d", $config.RacineReelle, "-STP", "-STJ", "-PackageFile", $package, "-Force")

    # --- Vérifications ---
    Assert-ExitCode -Result $result -Expected 0
    Assert-OutputMatch -Result $result -Pattern 'DÉPLOIEMENT TERMINÉ AVEC SUCCÈS' -Description "succès annoncé"
    Assert-Condition -Condition ((Get-VersionMarker -Directory (Join-Path $config.RacineReelle "taskflow")) -eq "nouvelle-version") -Description "taskflow (sélectionné) : nouvelle version"
    Assert-Condition -Condition ((Get-VersionMarker -Directory (Join-Path $config.RacineReelle "api")) -eq "ancienne-version") -Description "api (non sélectionné) : intact"
    Assert-Condition -Condition ((Get-VersionMarker -Directory (Join-Path $config.RacineReelle "HpcLite")) -eq "nouvelle-version") -Description "HpcLite (sélectionné) : nouvelle version"
    Assert-ApplicationStateUnchanged
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
