<#
.SYNOPSIS
    Jalon 4 - Validation des destinations - scénario t_4_07_stj_agent_absent_ko

.DESCRIPTION
    OBJECTIF

        Avec -STJ, l'absence de HpcLite\agent est refusée.

    PRÉCONDITIONS

        - Console Windows PowerShell 5.1 ouverte en tant qu'administrateur.
        - Lecteur D: disponible ; _commun\test-config.psd1 renseigné.

    ÉTAPES

        1. Créer un environnement factice sans : agent.
        2. Exécuter : download_deploy.ps1 -d <racine factice sans agent> -STJ

    RÉSULTAT ATTENDU

        Échec contrôlé : download_deploy.ps1 doit se terminer avec le code 1.
        Code 1. « Destination HpcLite Agent introuvable ».

    NETTOYAGE (automatique, même en cas d'erreur)

        Clear-TestEnvironment défait tout ce que ce test a créé ou modifié :
        dossiers et processus factices, variables d'environnement, état des
        services et du pool IIS, marqueurs version.txt, sauvegardes créées.

.NOTES
    Lancement : depuis ce dossier, .\launch_test.ps1
    (ou tout le jalon : ..\..\run_jalon.ps1 -Jalon 4)

    Codes de sortie de CE lanceur :
      0  TEST RÉUSSI   le comportement observé est celui attendu
      1  TEST ÉCHOUÉ   au moins une vérification a échoué
      2  NON EXÉCUTÉ   prérequis absent ou erreur de préparation

    download_deploy.ps1 (ce dossier) = version INCRÉMENTALE du jalon 4 :
    uniquement le code des jalons 0 à 4, terminé par « TEST TERMINÉ ».
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
        -Jalon 4 `
        -Objectif "Avec -STJ, l'absence de HpcLite\agent est refusée." `
        -ResultatAttendu "Échec contrôlé" `
        -CodeAttendu 1

    # --- Préparation ---
    # Environnement factice <RacineTestsAuto>\<scénario>, supprimé à la fin du test.
    $fake = New-FakeEnvironment -Omettre @("agent")
    $scriptUnderTest = New-ScriptUnderTest

    # --- Exécution ---
    $result = Invoke-ScriptUnderTest -ScriptPath $scriptUnderTest -Arguments @("-d", $fake.Root, "-STJ")

    # --- Vérifications ---
    Assert-ExitCode -Result $result -Expected 1
    Assert-OutputMatch -Result $result -Pattern 'Destination HpcLite Agent introuvable' -Description "dossier agent manquant signalé"
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
