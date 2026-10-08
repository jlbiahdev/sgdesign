<#
.SYNOPSIS
    Jalon 6 - Téléchargement - scénario t_6_01_telechargement_ok

.DESCRIPTION
    OBJECTIF

        Le package réel est téléchargé avec curl.exe, contrôlé (taille,
        SHA-256), puis le dossier de travail est supprimé.

    PRÉCONDITIONS

        - Console Windows PowerShell 5.1 ouverte en tant qu'administrateur.
        - Lecteur D: disponible ; _common\test-config.psd1 renseigné.
        - Vrais identifiants Artifactory et UrlPackageReel (vérifiés
          automatiquement).
        - Accès réseau à Artifactory.
        - UrlPackageReel renseignée dans test-config.psd1.
        - Vrais identifiants dans ARTIFACTORY_USERNAME / ARTIFACTORY_TOKEN
          (session ou Machine).

    ÉTAPES

        1. Créer un environnement factice.
        2. Exécuter : download_deploy.ps1 -d <racine factice> -STP -PackageUrl
           <UrlPackageReel>

    RÉSULTAT ATTENDU

        Succès : download_deploy.ps1 doit se terminer avec le code 0.
        Code 0. HTTP 200, taille et empreinte SHA-256 journalisées,
        <racine>\.deploy supprimé.

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

    download_deploy.ps1 (ce dossier) = version INCRÉMENTALE du jalon 6 :
    uniquement le code des jalons 0 à 6, terminé par « TEST TERMINÉ ».
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
        -Jalon 6 `
        -Objectif "Le package réel est téléchargé avec curl.exe, contrôlé (taille, SHA-256), puis le dossier de travail est supprimé." `
        -ResultatAttendu "Succès" `
        -CodeAttendu 0 `
        -IdentifiantsReels

    # --- Préparation ---
    $config = Get-TestConfig
    $fake = New-FakeEnvironment
    $scriptUnderTest = New-ScriptUnderTest
    $fakeCredentials = Get-FakeCredentials

    # --- Exécution ---
    $result = Invoke-ScriptUnderTest -ScriptPath $scriptUnderTest -Arguments @("-d", $fake.Root, "-STP", "-PackageUrl", $config.UrlPackageReel)

    # --- Vérifications ---
    Assert-ExitCode -Result $result -Expected 0
    Assert-OutputMatch -Result $result -Pattern 'Réponse HTTP : 200' -Description "réponse HTTP 200"
    Assert-OutputMatch -Result $result -Pattern 'Package téléchargé : \d+ octets' -Description "taille journalisée"
    Assert-OutputMatch -Result $result -Pattern 'Empreinte SHA-256 : [0-9A-F]{64}' -Description "empreinte SHA-256 journalisée"
    Assert-Condition -Condition (-not (Test-Path -LiteralPath (Join-Path $fake.Root ".deploy"))) -Description "dossier de travail supprimé après le test"
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
