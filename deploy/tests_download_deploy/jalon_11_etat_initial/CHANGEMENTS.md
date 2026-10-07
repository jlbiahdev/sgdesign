# Jalon 11 - code ajouté

Fichier généré par `_outils\Build-JalonVersions.ps1`. Ne pas modifier.

| | |
|---|---|
| Lignes de la version du jalon 11 | 1497 |
| Lignes de la version précédente | 1471 |
| Lignes ajoutées par ce jalon | 26 |
| Lignes retirées par ce jalon | 0 |

La version se termine par le bloc « JALON 11 ATTEINT / TEST TERMINÉ » (non repris ci-dessous).

## Ajouté

### Programme principal - étape J11

```powershell
    # --------------------------------------------------------
    # J11 - État initial
    # --------------------------------------------------------

    Write-Step "[J11] Mémorisation de l'état initial"

    $previousState = [pscustomobject] @{
        TaskflowWasRunning  = $taskflowWasRunning
        ApiWasRunning       = $apiState -eq "Started"
        AgentWasRunning     = $agentWasRunning
        SchedulerWasRunning = $schedulerWasRunning
        RunnerCountBefore   = $runnerProcesses.Count
    }

    # Manifeste de l'état initial, à côté du journal. Jamais de secret dedans.
    $stateFile = [IO.Path]::ChangeExtension($script:LogFile, ".state.json")
    $previousState | ConvertTo-Json | Set-Content -LiteralPath $stateFile -Encoding UTF8

    Write-Log -Message "État initial enregistré : $stateFile" -Level "OK"

    if ($ValidationOnly) {
        Write-Log -Message "MODE VALIDATION : toutes les vérifications sont terminées." -Level "OK"
        Write-Log -Message "Aucune application n'a été arrêtée et aucun fichier n'a été remplacé." -Level "OK"
        exit 0
    }
```

