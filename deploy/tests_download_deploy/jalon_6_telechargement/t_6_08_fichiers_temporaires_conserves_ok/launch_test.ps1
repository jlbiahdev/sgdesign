<#
.SYNOPSIS
    Jalon 6 - Téléchargement - scénario t_6_08_fichiers_temporaires_conserves_ok

.DESCRIPTION
    OBJECTIF

        Avec -KeepTemporaryFiles, le dossier de travail est conservé.

    PRÉCONDITIONS

        - Console Windows PowerShell 5.1 ouverte en tant qu'administrateur.
        - Lecteur D: disponible ; _commun\test-config.psd1 renseigné.

    ÉTAPES

        1. Créer un environnement factice et un package de test.
        2. Exécuter : download_deploy.ps1 -d <racine factice> -STP
           -PackageFile <package> -KeepTemporaryFiles

    RÉSULTAT ATTENDU

        Succès : download_deploy.ps1 doit se terminer avec le code 0.
        Code 0. <racine>\.deploy\<id>\Styx.Publish.nupkg existe toujours.

    NETTOYAGE (automatique, même en cas d'erreur)

        Clear-TestEnvironment défait tout ce que ce test a créé ou modifié :
        dossiers et processus factices, variables d'environnement, état des
        services et du pool IIS, marqueurs version.txt, sauvegardes créées.

.NOTES
    Lancement : depuis ce dossier, .\launch_test.ps1
    (ou tout le jalon : ..\..\run_jalon.ps1 -Jalon 6)

    Codes de sortie de CE lanceur :
      0  TEST RÉUSSI   le comportement observé est celui attendu
      1  TEST ÉCHOUÉ   au moins une vérification a échoué
      2  NON EXÉCUTÉ   prérequis absent ou erreur de préparation

    download_deploy.ps1 (ce dossier) = script de production avec
    $script:JalonCible = 6 : il s'arrête volontairement après le jalon 6.
    Ne jamais le modifier pour faire réussir ce test : les adaptations
    nécessaires sont faites par le lanceur dans une copie temporaire.
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
        -Jalon 6 `
        -Objectif "Avec -KeepTemporaryFiles, le dossier de travail est conservé." `
        -ResultatAttendu "Succès" `
        -CodeAttendu 0

    # --- Préparation ---
    $fake = New-FakeEnvironment
    $package = New-TestPackage
    $scriptUnderTest = New-ScriptUnderTest

    # --- Exécution ---
    $result = Invoke-ScriptUnderTest -ScriptPath $scriptUnderTest -Arguments @("-d", $fake.Root, "-STP", "-PackageFile", $package, "-KeepTemporaryFiles")

    # --- Vérifications ---
    Assert-ExitCode -Result $result -Expected 0
    $kept = @(Get-ChildItem -LiteralPath (Join-Path $fake.Root ".deploy") -Recurse -Filter "Styx.Publish.nupkg" -ErrorAction SilentlyContinue)
    Assert-Condition -Condition ($kept.Count -eq 1) -Description "package conservé dans <racine>\.deploy"
    Assert-OutputMatch -Result $result -Pattern 'fichiers temporaires sont conservés' -Description "conservation annoncée"
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
