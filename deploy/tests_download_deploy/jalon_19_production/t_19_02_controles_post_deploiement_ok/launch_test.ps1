<#
.SYNOPSIS
    Jalon 19 - Validation en conditions réelles - scénario t_19_02_controles_post_deploiement_ok

.DESCRIPTION
    OBJECTIF

        Après le premier déploiement réel : contrôles en LECTURE SEULE de
        l'état du serveur.

    PRÉCONDITIONS

        - Console Windows PowerShell 5.1 ouverte en tant qu'administrateur.
        - Lecteur D: disponible ; _common\test-config.psd1 renseigné.
        - Services Windows de test (ServiceTaskflow, ServiceAgent,
          ServiceScheduler de test-config.psd1) installés et pointant vers
          D:\Styx-Test.
        - Pool IIS de test existant (PoolIis).
        - À lancer sur le serveur cible, juste APRÈS le déploiement réel.
        - Ce test n'exécute pas download_deploy.ps1 et ne modifie rien.

    ÉTAPES

        1. Vérifier : services Taskflow, Agent, Scheduler démarrés, une seule
           instance chacun.
        2. Vérifier : pool IIS démarré.
        3. Vérifier : le dernier journal de RacineProduction annonce le
           succès.
        4. Compléter par les contrôles fonctionnels manuels (README, jalon
           19).

    RÉSULTAT ATTENDU

        Succès : download_deploy.ps1 doit se terminer avec le code 0.
        Tous les contrôles sont verts. Code obtenu : (script non exécuté).

    NETTOYAGE (automatique, même en cas d'erreur)

        Clear-TestEnvironment défait tout ce que ce test a créé ou modifié :
        dossiers et processus factices, variables d'environnement, état des
        services et du pool IIS, marqueurs version.txt, sauvegardes créées.

.NOTES
    Lancement : depuis ce dossier, .\launch_test.ps1
    (ou tout le jalon : ..\..\run_jalon.ps1 -Jalon 19)

    Codes de sortie de CE lanceur :
      0  TEST RÉUSSI   le comportement observé est celui attendu
      1  TEST ÉCHOUÉ   au moins une vérification a échoué
      2  NON EXÉCUTÉ   prérequis absent ou erreur de préparation

    download_deploy.ps1 (ce dossier) = script de production complet.
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
        -Jalon 19 `
        -Objectif "Après le premier déploiement réel : contrôles en LECTURE SEULE de l'état du serveur." `
        -ResultatAttendu "Succès" `
        -CodeAttendu 0 `
        -ServicesReels `
        -PoolIis

    # --- Préparation ---
    $config = Get-TestConfig
    $prodRoot = $config.RacineProduction

    # --- Vérifications (lecture seule) ---
    foreach ($serviceName in @($config.ServiceTaskflow, $config.ServiceAgent, $config.ServiceScheduler)) {
        Assert-Condition -Condition ((Get-ServiceStatus -Name $serviceName) -eq "Running") -Description "service '$serviceName' démarré"
    }

    $executables = @{
        "Taskflow"          = Join-Path $prodRoot "taskflow\$($config.ExecutableTaskflow)"
        "HpcLite Agent"     = Join-Path $prodRoot "HpcLite\agent\$($config.ExecutableAgent)"
        "HpcLite Scheduler" = Join-Path $prodRoot "HpcLite\scheduler\$($config.ExecutableScheduler)"
    }

    foreach ($name in $executables.Keys) {
        Assert-Condition -Condition ((Get-ProcessCountByPath -ExecutablePath $executables[$name]) -eq 1) -Description "$name : exactement une instance"
    }

    Assert-Condition -Condition ((Get-PoolState) -eq "Started") -Description "pool IIS démarré"

    $lastLog = Get-ChildItem -LiteralPath (Join-Path $prodRoot "deployment-logs") -Filter "deployment-*.log" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    Assert-Condition -Condition ($null -ne $lastLog -and ([IO.File]::ReadAllText($lastLog.FullName) -match 'Déploiement terminé avec succès')) -Description "le dernier journal annonce le succès"
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
