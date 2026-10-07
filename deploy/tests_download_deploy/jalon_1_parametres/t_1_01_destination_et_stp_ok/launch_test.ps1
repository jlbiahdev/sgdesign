<#
.SYNOPSIS
    Jalon 1 - Lecture des paramètres - scénario t_1_01_destination_et_stp_ok

.DESCRIPTION
    OBJECTIF

        Le script reconnaît -d et -STP.

    PRÉCONDITIONS

        - Console Windows PowerShell 5.1 ouverte en tant qu'administrateur.
        - Lecteur D: disponible ; _commun\test-config.psd1 renseigné.

    ÉTAPES

        1. Exécuter : download_deploy.ps1 -d <RacineTestsAuto> -STP
        2. Le script s'arrête volontairement après l'affichage des paramètres.

    RÉSULTAT ATTENDU

        Succès : download_deploy.ps1 doit se terminer avec le code 0.
        Code 0. Chaque trigramme est affiché avec la bonne valeur (True /
        False).

    NETTOYAGE (automatique, même en cas d'erreur)

        Clear-TestEnvironment défait tout ce que ce test a créé ou modifié :
        dossiers et processus factices, variables d'environnement, état des
        services et du pool IIS, marqueurs version.txt, sauvegardes créées.

.NOTES
    Lancement : depuis ce dossier, .\launch_test.ps1
    (ou tout le jalon : ..\..\run_jalon.ps1 -Jalon 1)

    Codes de sortie de CE lanceur :
      0  TEST RÉUSSI   le comportement observé est celui attendu
      1  TEST ÉCHOUÉ   au moins une vérification a échoué
      2  NON EXÉCUTÉ   prérequis absent ou erreur de préparation

    download_deploy.ps1 (ce dossier) = version INCRÉMENTALE du jalon 1 :
    uniquement le code des jalons 0 à 1, terminé par « TEST TERMINÉ ».
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
        -Jalon 1 `
        -Objectif "Le script reconnaît -d et -STP." `
        -ResultatAttendu "Succès" `
        -CodeAttendu 0

    # --- Préparation ---
    $scriptUnderTest = New-ScriptUnderTest

    # --- Exécution ---
    $result = Invoke-ScriptUnderTest -ScriptPath $scriptUnderTest -Arguments @("-d", (Get-TestConfig).RacineTestsAuto, "-STP")

    # --- Vérifications ---
    Assert-ExitCode -Result $result -Expected 0
    Assert-OutputMatch -Result $result -Pattern 'STP demandé : True' -Description "STP demandé : True"
    Assert-OutputMatch -Result $result -Pattern 'STX demandé : False' -Description "STX demandé : False"
    Assert-OutputMatch -Result $result -Pattern 'STJ demandé : False' -Description "STJ demandé : False"
    Assert-OutputMatch -Result $result -Pattern 'JALON 1 ATTEINT' -Description "arrêt volontaire au jalon 1"
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
