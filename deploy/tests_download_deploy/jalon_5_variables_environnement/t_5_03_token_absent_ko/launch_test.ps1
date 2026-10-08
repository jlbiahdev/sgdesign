<#
.SYNOPSIS
    Jalon 5 - Variables d'environnement et source du package - scénario t_5_03_token_absent_ko

.DESCRIPTION
    OBJECTIF

        Sans ARTIFACTORY_TOKEN, le script s'arrête.

    PRÉCONDITIONS

        - Console Windows PowerShell 5.1 ouverte en tant qu'administrateur.
        - Lecteur D: disponible ; _common\test-config.psd1 renseigné.
        - Les variables ARTIFACTORY_* et STYX_PACKAGE_URL de la session ET du
          niveau Machine sont modifiées pendant le test puis restaurées
          automatiquement.

    ÉTAPES

        1. Créer un environnement factice.
        2. Définir utilisateur et URL, sans token.
        3. Exécuter : download_deploy.ps1 -d <racine factice> -STP

    RÉSULTAT ATTENDU

        Échec contrôlé : download_deploy.ps1 doit se terminer avec le code 1.
        Code 1. « Le token Artifactory est absent ».

    NETTOYAGE (automatique, même en cas d'erreur)

        Clear-TestEnvironment défait tout ce que ce test a créé ou modifié :
        dossiers et processus factices, variables d'environnement, état des
        services et du pool IIS, marqueurs version.txt, sauvegardes créées.

.NOTES
    Lancement : depuis ce dossier, .\launch_test.ps1
    (ou tout le jalon : ..\..\run_jalon.ps1 -Jalon 5)

    Codes de sortie de CE lanceur :
      0  TEST RÉUSSI   le comportement observé est celui attendu
      1  TEST ÉCHOUÉ   au moins une vérification a échoué
      2  NON EXÉCUTÉ   prérequis absent ou erreur de préparation

    download_deploy.ps1 (ce dossier) = version INCRÉMENTALE du jalon 5 :
    uniquement le code des jalons 0 à 5, terminé par « TEST TERMINÉ ».
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
        -Jalon 5 `
        -Objectif "Sans ARTIFACTORY_TOKEN, le script s'arrête." `
        -ResultatAttendu "Échec contrôlé" `
        -CodeAttendu 1

    # --- Préparation ---
    $fake = New-FakeEnvironment
    $scriptUnderTest = New-ScriptUnderTest
    $fakeCredentials = Get-FakeCredentials

    # Point de départ maîtrisé : aucune variable Artifactory, ni en session
    # ni au niveau Machine (valeurs d'origine restaurées au nettoyage).
    Clear-ArtifactoryVariables
    Set-TestEnvironmentVariables -Session @{
        ARTIFACTORY_USERNAME = $fakeCredentials.Username
        STYX_PACKAGE_URL     = "https://artifactory.invalid/Styx.Publish.test.nupkg"
    }

    # --- Exécution ---
    $result = Invoke-ScriptUnderTest -ScriptPath $scriptUnderTest -Arguments @("-d", $fake.Root, "-STP")

    # --- Vérifications ---
    Assert-ExitCode -Result $result -Expected 1
    Assert-OutputMatch -Result $result -Pattern 'token Artifactory est absent' -Description "token manquant signalé"
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
