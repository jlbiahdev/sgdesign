<#
.SYNOPSIS
    Jalon 19 - Validation en conditions réelles - scénario t_19_02_controles_post_deploiement_ok

.DESCRIPTION
    OBJECTIF

        Après le premier déploiement réel : contrôles en LECTURE SEULE de
        l'état du serveur de production.

    PRÉCONDITIONS

        - Console Windows PowerShell 5.1 ouverte en tant qu'administrateur.
        - Lecteur D: disponible ; _common\test-config.psd1 renseigné.
        - IIS installé (appcmd.exe).
        - À lancer sur le serveur cible, juste APRÈS le déploiement réel.
        - Ce test n'exécute pas download_deploy.ps1 et ne modifie rien.
        - Les noms contrôlés (services, pool, exécutables) sont ceux du
          download_deploy.ps1 de PRODUCTION, pas ceux de test-config.psd1.

    ÉTAPES

        1. Lire les noms de production dans download_deploy.ps1 (racine).
        2. Vérifier : services Taskflow, Agent, Scheduler de production
           démarrés, une seule instance chacun sous RacineProduction.
        3. Vérifier : pool IIS de production démarré.
        4. Vérifier : le dernier journal de RacineProduction annonce le
           succès.
        5. Compléter par les contrôles fonctionnels manuels (README, jalon
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
        -Objectif "Après le premier déploiement réel : contrôles en LECTURE SEULE de l'état du serveur de production." `
        -ResultatAttendu "Succès" `
        -CodeAttendu 0 `
        -AvecIis

    # --- Préparation ---
    # Noms de PRODUCTION, lus dans le script de production (pas test-config.psd1,
    # qui contient les services et le pool de TEST).
    $config = Get-TestConfig
    $prodRoot = $config.RacineProduction
    $prod = Get-ProductionSettings
    Write-Host "Services de production : $($prod.ServiceTaskflow), $($prod.ServiceAgent), $($prod.ServiceScheduler) ; pool : $($prod.PoolIis)" -ForegroundColor DarkGray

    # --- Vérifications (lecture seule) ---
    foreach ($serviceName in @($prod.ServiceTaskflow, $prod.ServiceAgent, $prod.ServiceScheduler)) {
        $status = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
        Assert-Condition -Condition ($null -ne $status -and $status.Status -eq "Running") -Description "service de production '$serviceName' démarré"
    }

    $executables = @{
        "Taskflow"          = Join-Path $prodRoot "taskflow\$($prod.ExecutableTaskflow)"
        "HpcLite Agent"     = Join-Path $prodRoot "HpcLite\$($prod.DossierAgent)\$($prod.ExecutableAgent)"
        "HpcLite Scheduler" = Join-Path $prodRoot "HpcLite\$($prod.DossierScheduler)\$($prod.ExecutableScheduler)"
    }

    foreach ($name in $executables.Keys) {
        Assert-Condition -Condition ((Get-ProcessCountByPath -ExecutablePath $executables[$name]) -eq 1) -Description "$name : exactement une instance ($($executables[$name]))"
    }

    Assert-Condition -Condition ((Get-PoolState -Name $prod.PoolIis) -eq "Started") -Description "pool IIS de production '$($prod.PoolIis)' démarré"

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
