<#
.SYNOPSIS
    Jalon 0 - Compatibilité du serveur - scénario t_0_04_iis_indisponible_ko

.DESCRIPTION
    OBJECTIF

        Avec -STX, le script refuse de continuer si appcmd.exe est
        introuvable.

    PRÉCONDITIONS

        - Console Windows PowerShell 5.1 ouverte en tant qu'administrateur.
        - Lecteur D: disponible ; _commun\test-config.psd1 renseigné.

    ÉTAPES

        1. Préparer une copie du script où AppCmdPath désigne un fichier
           inexistant (simulation d'un serveur sans IIS).
        2. Exécuter : download_deploy.ps1 -d <RacineTestsAuto> -STX

    RÉSULTAT ATTENDU

        Échec contrôlé : download_deploy.ps1 doit se terminer avec le code 1.
        Code 1. Message « Outil d'administration IIS appcmd.exe introuvable ».

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

    download_deploy.ps1 (ce dossier) = script de production avec
    $script:JalonCible = 0 : il s'arrête volontairement après le jalon 0.
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
        -Jalon 0 `
        -Objectif "Avec -STX, le script refuse de continuer si appcmd.exe est introuvable." `
        -ResultatAttendu "Échec contrôlé" `
        -CodeAttendu 1

    # --- Préparation ---
    # Simulation d'un serveur sans IIS : le chemin d'appcmd.exe pointe ailleurs.
    $scriptUnderTest = New-ScriptUnderTest -Configuration @{ AppCmdPath = "'C:\Styx-Introuvable\appcmd.exe'" }

    # --- Exécution ---
    $result = Invoke-ScriptUnderTest -ScriptPath $scriptUnderTest -Arguments @("-d", (Get-TestConfig).RacineTestsAuto, "-STX")

    # --- Vérifications ---
    Assert-ExitCode -Result $result -Expected 1
    Assert-OutputMatch -Result $result -Pattern 'appcmd\.exe introuvable' -Description "appcmd.exe signalé introuvable"
    Assert-OutputNotMatch -Result $result -Pattern 'JALON 0 ATTEINT' -Description "le jalon 0 n'est pas validé"
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
