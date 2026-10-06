<#
.SYNOPSIS
    Jalon 11 - Mémorisation de l'état initial - scénario t_11_03_validation_only_ok

.DESCRIPTION
    OBJECTIF

        -ValidationOnly fait toutes les vérifications puis s'arrête sans rien
        arrêter ni remplacer.

    PRÉCONDITIONS

        - Console Windows PowerShell 5.1 ouverte en tant qu'administrateur.
        - Lecteur D: disponible ; _commun\test-config.psd1 renseigné.
        - Mode test (processus factices).

    ÉTAPES

        1. Créer un environnement factice ; démarrer un Taskflow factice.
        2. Exécuter : download_deploy.ps1 -d <racine factice> -STP
           -PackageFile <package> -ValidationOnly

    RÉSULTAT ATTENDU

        Succès : download_deploy.ps1 doit se terminer avec le code 0.
        Code 0. « MODE VALIDATION » ; le Taskflow factice tourne toujours ;
        version.txt inchangé.

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

    download_deploy.ps1 (ce dossier) = script de production avec
    $script:JalonCible = 11 : il s'arrête volontairement après le jalon 11.
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
        -Jalon 11 `
        -Objectif "-ValidationOnly fait toutes les vérifications puis s'arrête sans rien arrêter ni remplacer." `
        -ResultatAttendu "Succès" `
        -CodeAttendu 0

    # --- Préparation ---
    $fake = New-FakeEnvironment
    $package = New-TestPackage
    $scriptUnderTest = New-ScriptUnderTest -ModeExecutable
    Start-FakeProcess -ExecutablePath $fake.TaskflowExe | Out-Null

    # --- Exécution ---
    $result = Invoke-ScriptUnderTest -ScriptPath $scriptUnderTest -Arguments @("-d", $fake.Root, "-STP", "-PackageFile", $package, "-ValidationOnly")

    # --- Vérifications ---
    Assert-ExitCode -Result $result -Expected 0
    Assert-OutputMatch -Result $result -Pattern 'MODE VALIDATION' -Description "mode validation annoncé"
    Assert-OutputNotMatch -Result $result -Pattern 'JALON 11 ATTEINT' -Description "arrêt dû à -ValidationOnly, pas au jalon"
    Assert-Condition -Condition ((Get-ProcessCountByPath -ExecutablePath $fake.TaskflowExe) -eq 1) -Description "Taskflow tourne toujours"
    Assert-Condition -Condition ((Get-VersionMarker -Directory $fake.TaskflowDir) -eq "ancienne-version") -Description "fichiers taskflow inchangés"
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
