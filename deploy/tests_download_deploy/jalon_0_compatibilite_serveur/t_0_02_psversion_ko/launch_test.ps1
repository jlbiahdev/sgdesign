<#
.SYNOPSIS
    Jalon 0 - Compatibilité du serveur - scénario t_0_02_psversion_ko

.DESCRIPTION
    OBJECTIF

        Le script refuse de démarrer si la version de PowerShell exigée n'est
        pas disponible.

    PRÉCONDITIONS

        - Console Windows PowerShell 5.1 ouverte en tant qu'administrateur.
        - Lecteur D: disponible ; _commun\test-config.psd1 renseigné.

    ÉTAPES

        1. Préparer une copie du script exigeant « #requires -Version 99.0 »
           (simulation d'un PowerShell trop ancien).
        2. Exécuter : download_deploy.ps1 -d <RacineTestsAuto> -STP

    RÉSULTAT ATTENDU

        Échec contrôlé : download_deploy.ps1 doit se terminer avec le code 1.
        PowerShell refuse le script avant toute exécution : code 1, message
        citant la version 99.0, aucune ligne du script affichée.

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
        -Objectif "Le script refuse de démarrer si la version de PowerShell exigée n'est pas disponible." `
        -ResultatAttendu "Échec contrôlé" `
        -CodeAttendu 1

    # --- Préparation ---
    # On ne peut pas installer un vieux PowerShell : on simule en exigeant une
    # version inexistante. C'est le mécanisme #requires qui est vérifié.
    $scriptUnderTest = New-ScriptUnderTest -RequiresVersion "99.0"

    # --- Exécution ---
    $result = Invoke-ScriptUnderTest -ScriptPath $scriptUnderTest -Arguments @("-d", (Get-TestConfig).RacineTestsAuto, "-STP")

    # --- Vérifications ---
    Assert-ExitCode -Result $result -Expected 1
    Assert-OutputMatch -Result $result -Pattern '99\.0' -Description "le refus cite la version exigée"
    Assert-OutputNotMatch -Result $result -Pattern 'Compatibilité du serveur' -Description "le script n'a pas démarré"
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
