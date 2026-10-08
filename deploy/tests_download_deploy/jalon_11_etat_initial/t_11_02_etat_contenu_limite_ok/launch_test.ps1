<#
.SYNOPSIS
    Jalon 11 - Mémorisation de l'état initial - scénario t_11_02_etat_contenu_limite_ok

.DESCRIPTION
    OBJECTIF

        state.json ne contient que les cinq informations prévues (aucun
        secret, aucun chemin sensible).

    PRÉCONDITIONS

        - Console Windows PowerShell 5.1 ouverte en tant qu'administrateur.
        - Lecteur D: disponible ; _common\test-config.psd1 renseigné.
        - Mode test (processus factices).

    ÉTAPES

        1. Définir des identifiants factices en session.
        2. Exécuter : download_deploy.ps1 -d <racine factice> -STP
           -PackageFile <package>
        3. Lire state.json.

    RÉSULTAT ATTENDU

        Succès : download_deploy.ps1 doit se terminer avec le code 0.
        Code 0. Exactement les propriétés TaskflowWasRunning, ApiWasRunning,
        AgentWasRunning, SchedulerWasRunning, RunnerCountBefore ; aucun token.

    NETTOYAGE (automatique, même en cas d'erreur)

        Clear-TestEnvironment défait tout ce que ce test a créé ou modifié :
        dossiers et processus factices, variables d'environnement, état des
        services et du pool IIS, marqueurs version.txt, sauvegardes créées.

.NOTES
    Lancement : depuis ce dossier, .\launch_test.ps1
    (ou tout le jalon : ..\..\run_jalon.ps1 -Jalon 11)

    Codes de sortie de CE lanceur :
      0  TEST RÉUSSI   le comportement observé est celui attendu
      1  TEST ÉCHOUÉ   au moins une vérification a échoué
      2  NON EXÉCUTÉ   prérequis absent ou erreur de préparation

    download_deploy.ps1 (ce dossier) = version INCRÉMENTALE du jalon 11 :
    uniquement le code des jalons 0 à 11, terminé par « TEST TERMINÉ ».
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
        -Jalon 11 `
        -Objectif "state.json ne contient que les cinq informations prévues (aucun secret, aucun chemin sensible)." `
        -ResultatAttendu "Succès" `
        -CodeAttendu 0

    # --- Préparation ---
    $fake = New-FakeEnvironment
    $package = New-TestPackage
    $scriptUnderTest = New-ScriptUnderTest -ModeExecutable
    $fakeCredentials = Get-FakeCredentials
    Set-TestEnvironmentVariables -Session @{ ARTIFACTORY_USERNAME = $fakeCredentials.Username; ARTIFACTORY_TOKEN = $fakeCredentials.Token }

    # --- Exécution ---
    $result = Invoke-ScriptUnderTest -ScriptPath $scriptUnderTest -Arguments @("-d", $fake.Root, "-STP", "-PackageFile", $package)

    # --- Vérifications ---
    Assert-ExitCode -Result $result -Expected 0
    $log = Get-LatestLog -Root $fake.Root
    $stateFile = if ($null -ne $log) { [IO.Path]::ChangeExtension($log.FullName, ".state.json") } else { "" }
    Assert-Condition -Condition ($stateFile -ne "" -and (Test-Path -LiteralPath $stateFile)) -Description "fichier state.json créé à côté du journal"
    $savedState = if ($stateFile -ne "" -and (Test-Path -LiteralPath $stateFile)) { Get-Content -LiteralPath $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }

    if ($null -ne $savedState) {
        $properties = @($savedState.PSObject.Properties.Name | Sort-Object)
        $expected = @("AgentWasRunning", "ApiWasRunning", "RunnerCountBefore", "SchedulerWasRunning", "TaskflowWasRunning")
        Assert-Condition -Condition (($properties -join ",") -eq ($expected -join ",")) -Description "exactement les cinq propriétés prévues (obtenues : $($properties -join ', '))"
    }

    Assert-NoSecret -Result $result -Root $fake.Root
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
