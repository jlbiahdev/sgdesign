<#
.SYNOPSIS
    Jalon 14 - Sauvegarde des fichiers - scénario t_14_03_sauvegardes_precedentes_non_ecrasees_ok

.DESCRIPTION
    OBJECTIF

        Une sauvegarde d'un déploiement précédent n'est ni écrasée ni
        supprimée.

    PRÉCONDITIONS

        - Console Windows PowerShell 5.1 ouverte en tant qu'administrateur.
        - Lecteur D: disponible ; _commun\test-config.psd1 renseigné.
        - Environnement réel de test complet et distinct de la production
          (vérifié automatiquement).
        - Environnement réel de test complet (RacineReelle) : vrais binaires,
          trois services Windows pointant sur RacineReelle, pool IIS de test.
        - L'état des services et du pool est mémorisé au début et restauré à
          la fin du test.

    ÉTAPES

        1. Poser version.txt = ancienne-version dans taskflow, api et HpcLite.
        2. Créer un package de test (non installé : le jalon 14 sauvegarde
           puis restaure).
        3. Créer une fausse sauvegarde précédente dans
           <RacineReelle>\.rollback.
        4. Exécuter : download_deploy.ps1 -d <RacineReelle> -STX -PackageFile
           <package> -Force

    RÉSULTAT ATTENDU

        Succès : download_deploy.ps1 doit se terminer avec le code 0.
        Code 0. La sauvegarde précédente est intacte.

    NETTOYAGE (automatique, même en cas d'erreur)

        Clear-TestEnvironment défait tout ce que ce test a créé ou modifié :
        dossiers et processus factices, variables d'environnement, état des
        services et du pool IIS, marqueurs version.txt, sauvegardes créées.

.NOTES
    Lancement : depuis ce dossier, .\launch_test.ps1
    (ou tout le jalon : ..\..\run_jalon.ps1 -Jalon 14)

    Codes de sortie de CE lanceur :
      0  TEST RÉUSSI   le comportement observé est celui attendu
      1  TEST ÉCHOUÉ   au moins une vérification a échoué
      2  NON EXÉCUTÉ   prérequis absent ou erreur de préparation

    download_deploy.ps1 (ce dossier) = version INCRÉMENTALE du jalon 14 :
    uniquement le code des jalons 0 à 14, terminé par « TEST TERMINÉ ».
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
        -Jalon 14 `
        -Objectif "Une sauvegarde d'un déploiement précédent n'est ni écrasée ni supprimée." `
        -ResultatAttendu "Succès" `
        -CodeAttendu 0 `
        -EnvironnementReel

    # --- Préparation ---
    $config = Get-TestConfig
    Set-RealVersionMarkers
    $package = New-TestPackage
    $scriptUnderTest = New-ScriptUnderTest
    $oldBackup = Join-Path $config.RacineReelle ".rollback\00000000-000000-sauvegarde-precedente-test"
    New-Item -Path (Join-Path $oldBackup "STX") -ItemType Directory -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $oldBackup "STX\temoin.txt") -Value "sauvegarde-precedente" -Encoding ASCII
    Register-PathToRemove -Path $oldBackup

    # --- Exécution ---
    $result = Invoke-ScriptUnderTest -ScriptPath $scriptUnderTest -Arguments @("-d", $config.RacineReelle, "-STX", "-PackageFile", $package, "-Force")

    # --- Vérifications ---
    Assert-ExitCode -Result $result -Expected 0
    Assert-OutputMatch -Result $result -Pattern 'JALON 14 ATTEINT' -Description "arrêt volontaire au jalon 14"
    Assert-Condition -Condition ((Test-Path -LiteralPath (Join-Path $oldBackup "STX\temoin.txt")) -and ([IO.File]::ReadAllText((Join-Path $oldBackup "STX\temoin.txt")).Trim() -eq "sauvegarde-precedente")) -Description "sauvegarde précédente intacte"
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
