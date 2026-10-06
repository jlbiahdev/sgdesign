<#
.SYNOPSIS
    Jalon 2 - Journalisation - scénario t_2_04_log_erreur_ok

.DESCRIPTION
    OBJECTIF

        Une erreur survenant après la création du journal y est écrite au
        niveau ERREUR.

    PRÉCONDITIONS

        - Console Windows PowerShell 5.1 ouverte en tant qu'administrateur.
        - Lecteur D: disponible ; _commun\test-config.psd1 renseigné.

    ÉTAPES

        1. Créer un environnement factice (dossier racine valide sur D:).
        2. Préparer une copie du script avec une erreur volontaire juste après
           la création du journal (point de test « apres-journal »).
        3. Exécuter : download_deploy.ps1 -d <racine factice> -STP
        4. Lire le journal créé dans <racine factice>\deployment-logs.

    RÉSULTAT ATTENDU

        Échec contrôlé : download_deploy.ps1 doit se terminer avec le code 1.
        Code 1. Le journal contient « [ERREUR] ERREUR DE TEST VOLONTAIRE ».

    NETTOYAGE (automatique, même en cas d'erreur)

        Clear-TestEnvironment défait tout ce que ce test a créé ou modifié :
        dossiers et processus factices, variables d'environnement, état des
        services et du pool IIS, marqueurs version.txt, sauvegardes créées.

.NOTES
    Lancement : depuis ce dossier, .\launch_test.ps1
    (ou tout le jalon : ..\..\run_jalon.ps1 -Jalon 2)

    Codes de sortie de CE lanceur :
      0  TEST RÉUSSI   le comportement observé est celui attendu
      1  TEST ÉCHOUÉ   au moins une vérification a échoué
      2  NON EXÉCUTÉ   prérequis absent ou erreur de préparation

    download_deploy.ps1 (ce dossier) = script de production avec
    $script:JalonCible = 2 : il s'arrête volontairement après le jalon 2.
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
        -Jalon 2 `
        -Objectif "Une erreur survenant après la création du journal y est écrite au niveau ERREUR." `
        -ResultatAttendu "Échec contrôlé" `
        -CodeAttendu 1

    # --- Préparation ---
    $fake = New-FakeEnvironment
    $scriptUnderTest = New-ScriptUnderTest -InjecterErreur "apres-journal"

    # --- Exécution ---
    $result = Invoke-ScriptUnderTest -ScriptPath $scriptUnderTest -Arguments @("-d", $fake.Root, "-STP")

    # --- Vérifications ---
    Assert-ExitCode -Result $result -Expected 1
    Assert-LogMatch -Root $fake.Root -Pattern '\[ERREUR\] ERREUR DE TEST VOLONTAIRE' -Description "l'erreur est journalisée au niveau ERREUR"
    Assert-OutputMatch -Result $result -Pattern 'LE DÉPLOIEMENT A ÉCHOUÉ' -Description "l'échec est annoncé"
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
