<#
.SYNOPSIS
    Jalon 7 - Extraction du package - scénario t_7_06_noms_encodes_decodes_ok

.DESCRIPTION
    OBJECTIF

        Les noms encodés par NuGet (%20) sont décodés à l'extraction.

    PRÉCONDITIONS

        - Console Windows PowerShell 5.1 ouverte en tant qu'administrateur.
        - Lecteur D: disponible ; _common\test-config.psd1 renseigné.
        - IIS installé (appcmd.exe).

    ÉTAPES

        1. Créer un environnement factice.
        2. Créer un package contenant content/api/mon%20fichier.txt.
        3. Exécuter : download_deploy.ps1 -d <racine factice> -STX
           -PackageFile <package> -KeepTemporaryFiles
        4. Chercher le fichier extrait.

    RÉSULTAT ATTENDU

        Succès : download_deploy.ps1 doit se terminer avec le code 0.
        Code 0. Le fichier extrait s'appelle « mon fichier.txt ».

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
        -Jalon 7 `
        -Objectif "Les noms encodés par NuGet (%20) sont décodés à l'extraction." `
        -ResultatAttendu "Succès" `
        -CodeAttendu 0 `
        -AvecIis

    # --- Préparation ---
    $fake = New-FakeEnvironment
    $package = New-TestPackage -EntreesSupplementaires @{ "content/api/mon%20fichier.txt" = "test" }
    $scriptUnderTest = New-ScriptUnderTest

    # --- Exécution ---
    $result = Invoke-ScriptUnderTest -ScriptPath $scriptUnderTest -Arguments @("-d", $fake.Root, "-STX", "-PackageFile", $package, "-KeepTemporaryFiles")

    # --- Vérifications ---
    Assert-ExitCode -Result $result -Expected 0
    $decoded = @(Get-ChildItem -LiteralPath (Join-Path $fake.Root ".deploy") -Recurse -Filter "mon fichier.txt" -ErrorAction SilentlyContinue)
    Assert-Condition -Condition ($decoded.Count -ge 1) -Description "« mon fichier.txt » extrait avec un espace"
    $encoded = @(Get-ChildItem -LiteralPath (Join-Path $fake.Root ".deploy") -Recurse -Filter "mon%20fichier.txt" -ErrorAction SilentlyContinue)
    Assert-Condition -Condition ($encoded.Count -eq 0) -Description "aucun fichier « mon%20fichier.txt »"
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
