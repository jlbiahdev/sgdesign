<#
.SYNOPSIS
    Jalon 7 - Extraction du package - scénario t_7_02_package_valide_tous_ok

.DESCRIPTION
    OBJECTIF

        Avec les trois trigrammes, les trois contenus sont contrôlés.

    PRÉCONDITIONS

        - Console Windows PowerShell 5.1 ouverte en tant qu'administrateur.
        - Lecteur D: disponible ; _commun\test-config.psd1 renseigné.
        - IIS installé (appcmd.exe).

    ÉTAPES

        1. Créer un environnement factice.
        2. Créer un package de test complet.
        3. Exécuter : download_deploy.ps1 -d <racine factice> -STP -STX -STJ
           -PackageFile <package>

    RÉSULTAT ATTENDU

        Succès : download_deploy.ps1 doit se terminer avec le code 0.
        Code 0. Les trois contenus sont trouvés.

    NETTOYAGE (automatique, même en cas d'erreur)

        Clear-TestEnvironment défait tout ce que ce test a créé ou modifié :
        dossiers et processus factices, variables d'environnement, état des
        services et du pool IIS, marqueurs version.txt, sauvegardes créées.

.NOTES
    Lancement : depuis ce dossier, .\launch_test.ps1
    (ou tout le jalon : ..\..\run_jalon.ps1 -Jalon 7)

    Codes de sortie de CE lanceur :
      0  TEST RÉUSSI   le comportement observé est celui attendu
      1  TEST ÉCHOUÉ   au moins une vérification a échoué
      2  NON EXÉCUTÉ   prérequis absent ou erreur de préparation

    download_deploy.ps1 (ce dossier) = version INCRÉMENTALE du jalon 7 :
    uniquement le code des jalons 0 à 7, terminé par « TEST TERMINÉ ».
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
        -Jalon 7 `
        -Objectif "Avec les trois trigrammes, les trois contenus sont contrôlés." `
        -ResultatAttendu "Succès" `
        -CodeAttendu 0 `
        -AvecIis

    # --- Préparation ---
    $fake = New-FakeEnvironment
    $package = New-TestPackage
    $scriptUnderTest = New-ScriptUnderTest

    # --- Exécution ---
    $result = Invoke-ScriptUnderTest -ScriptPath $scriptUnderTest -Arguments @("-d", $fake.Root, "-STP", "-STX", "-STJ", "-PackageFile", $package)

    # --- Vérifications ---
    Assert-ExitCode -Result $result -Expected 0
    Assert-OutputMatch -Result $result -Pattern 'Contenu STP trouvé : 3 fichiers' -Description "contenu taskflow"
    Assert-OutputMatch -Result $result -Pattern 'Contenu STX trouvé : 3 fichiers' -Description "contenu api"
    Assert-OutputMatch -Result $result -Pattern 'Contenu STJ trouvé : 4 fichiers' -Description "contenu hpclite"
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
