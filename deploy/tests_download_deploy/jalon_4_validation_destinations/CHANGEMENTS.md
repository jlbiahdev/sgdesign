# Jalon 4 - code ajouté

Fichier généré par `_outils\Build-JalonVersions.ps1`. Ne pas modifier.

| | |
|---|---|
| Lignes de la version du jalon 4 | 668 |
| Lignes de la version précédente | 586 |
| Lignes ajoutées par ce jalon | 80 |
| Lignes retirées par ce jalon | 0 |

La version se termine par le bloc « JALON 4 ATTEINT / TEST TERMINÉ » (non repris ci-dessous).

## Ajouté

### Configuration / variables

```powershell
# Exécutable Taskflow, relatif à <d>\taskflow. Une seule instance autorisée.
$TaskflowExecutableRelativePath = "Taskflow.exe"

# Dossiers HpcLite, relatifs à <d>\HpcLite.
$HpcLiteAgentFolder = "agent"
$HpcLiteRunnerFolder = "runner"
$HpcLiteSchedulerFolder = "scheduler"

# Exécutables HpcLite, relatifs à leur dossier.
$HpcLiteAgentExecutableName = "HpcLite.Agent.exe"
$HpcLiteRunnerExecutableName = "HpcLite.Runner.exe"
$HpcLiteSchedulerExecutableName = "HpcLite.Scheduler.exe"
```

### Fonction Assert-ExistingDirectory

```powershell
<#
.SYNOPSIS
    Échoue avec un message clair si le dossier n'existe pas.
#>
function Assert-ExistingDirectory {
    param(
        [Parameter(Mandatory = $true)] [string] $Path,
        [Parameter(Mandatory = $true)] [string] $Description
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw @"
$Description introuvable.

Dossier attendu :
$Path

Le déploiement est annulé avant l'arrêt des applications.
"@
    }
}
```

### Programme principal - étape J4

```powershell
    # --------------------------------------------------------
    # J4 - Destinations
    # --------------------------------------------------------

    Write-Step "[J4] Vérification des dossiers de destination"

    $taskflowDestination  = Join-Path $DestinationRoot "taskflow"
    $apiDestination       = Join-Path $DestinationRoot "api"
    $hpcLiteDestination   = Join-Path $DestinationRoot "HpcLite"

    $agentDestination     = Join-Path $hpcLiteDestination $HpcLiteAgentFolder
    $runnerDestination    = Join-Path $hpcLiteDestination $HpcLiteRunnerFolder
    $schedulerDestination = Join-Path $hpcLiteDestination $HpcLiteSchedulerFolder

    $paths = [pscustomobject] @{
        TaskflowExecutable  = Join-Path $taskflowDestination  $TaskflowExecutableRelativePath
        AgentExecutable     = Join-Path $agentDestination     $HpcLiteAgentExecutableName
        RunnerExecutable    = Join-Path $runnerDestination    $HpcLiteRunnerExecutableName
        SchedulerExecutable = Join-Path $schedulerDestination $HpcLiteSchedulerExecutableName
    }

    # Seules les applications demandées sont contrôlées : -STX ne doit pas
    # échouer parce que taskflow est absent.
    if ($STP) {
        Assert-ExistingDirectory -Path $taskflowDestination -Description "Destination STP / Taskflow"
        Assert-ExistingFile -Path $paths.TaskflowExecutable -Description "Exécutable Taskflow"
        Write-Log -Message "Destination STP valide : $taskflowDestination" -Level "OK"
    }

    if ($STX) {
        Assert-ExistingDirectory -Path $apiDestination -Description "Destination STX / API"
        Write-Log -Message "Destination STX valide : $apiDestination" -Level "OK"
    }

    if ($STJ) {
        Assert-ExistingDirectory -Path $hpcLiteDestination   -Description "Destination STJ / HpcLite"
        Assert-ExistingDirectory -Path $agentDestination     -Description "Destination HpcLite Agent"
        Assert-ExistingDirectory -Path $runnerDestination    -Description "Destination HpcLite Runner"
        Assert-ExistingDirectory -Path $schedulerDestination -Description "Destination HpcLite Scheduler"

        Assert-ExistingFile -Path $paths.AgentExecutable     -Description "Exécutable HpcLite Agent"
        Assert-ExistingFile -Path $paths.RunnerExecutable    -Description "Exécutable HpcLite Runner"
        Assert-ExistingFile -Path $paths.SchedulerExecutable -Description "Exécutable HpcLite Scheduler"

        Write-Log -Message "Destination STJ valide : $hpcLiteDestination" -Level "OK"
    }
```

