<#
.SYNOPSIS
    Jalon 11 - Mémorisation de l'état initial - scénario t_11_01_etat_initial_enregistre_ok

.DESCRIPTION
    OBJECTIF

        L'état initial (qui tournait, combien de Runners) est enregistré dans
        state.json.

    PRÉCONDITIONS

        - Console Windows PowerShell 5.1 ouverte en tant qu'administrateur.
        - Lecteur D: disponible ; _commun\test-config.psd1 renseigné.
        - Mode test (processus factices).

    ÉTAPES

        1. Créer un environnement factice ; démarrer un Agent et 2 Runners
           factices (pas de Taskflow, pas de Scheduler).
        2. Exécuter : download_deploy.ps1 -d <racine factice> -STP -STJ
           -PackageFile <package>
        3. Lire <racine>\deployment-logs\deployment-....state.json.

    RÉSULTAT ATTENDU

        Succès : download_deploy.ps1 doit se terminer avec le code 0.
        Code 0. TaskflowWasRunning=false, AgentWasRunning=true,
        SchedulerWasRunning=false, RunnerCountBefore=2.

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
        -Objectif "L'état initial (qui tournait, combien de Runners) est enregistré dans state.json." `
        -ResultatAttendu "Succès" `
        -CodeAttendu 0

    # --- Préparation ---
    $fake = New-FakeEnvironment
    $package = New-TestPackage
    $scriptUnderTest = New-ScriptUnderTest -ModeExecutable
    Start-FakeProcess -ExecutablePath $fake.AgentExe | Out-Null
    Start-FakeProcess -ExecutablePath $fake.RunnerExe -Count 2 | Out-Null

    # --- Exécution ---
    $result = Invoke-ScriptUnderTest -ScriptPath $scriptUnderTest -Arguments @("-d", $fake.Root, "-STP", "-STJ", "-PackageFile", $package)

    # --- Vérifications ---
    Assert-ExitCode -Result $result -Expected 0
    $log = Get-LatestLog -Root $fake.Root
    $stateFile = if ($null -ne $log) { [IO.Path]::ChangeExtension($log.FullName, ".state.json") } else { "" }
    Assert-Condition -Condition ($stateFile -ne "" -and (Test-Path -LiteralPath $stateFile)) -Description "fichier state.json créé à côté du journal"
    $savedState = if ($stateFile -ne "" -and (Test-Path -LiteralPath $stateFile)) { Get-Content -LiteralPath $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }

    if ($null -ne $savedState) {
        Assert-Condition -Condition ($savedState.TaskflowWasRunning -eq $false) -Description "TaskflowWasRunning = false"
        Assert-Condition -Condition ($savedState.AgentWasRunning -eq $true) -Description "AgentWasRunning = true"
        Assert-Condition -Condition ($savedState.SchedulerWasRunning -eq $false) -Description "SchedulerWasRunning = false"
        Assert-Condition -Condition ($savedState.RunnerCountBefore -eq 2) -Description "RunnerCountBefore = 2"
    }
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
