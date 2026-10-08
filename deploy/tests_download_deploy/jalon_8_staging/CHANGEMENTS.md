# Jalon 8 - code ajouté

Fichier généré par `_tools\Build-JalonVersions.ps1`. Ne pas modifier.

| | |
|---|---|
| Lignes de la version du jalon 8 | 1149 |
| Lignes de la version précédente | 1094 |
| Lignes ajoutées par ce jalon | 54 |
| Lignes retirées par ce jalon | 0 |

La version se termine par le bloc « JALON 8 ATTEINT / TEST TERMINÉ » (non repris ci-dessous).

## Ajouté

### Fonction Copy-DirectoryContent

```powershell
<#
.SYNOPSIS
    Copie le contenu d'un dossier et vérifie le nombre de fichiers. (J8)
.OUTPUTS
    Nombre de fichiers copiés.
#>
function Copy-DirectoryContent {
    param(
        [Parameter(Mandatory = $true)] [string] $Source,
        [Parameter(Mandatory = $true)] [string] $Destination
    )

    New-Item -Path $Destination -ItemType Directory -Force | Out-Null

    Get-ChildItem -LiteralPath $Source -Force |
        Copy-Item -Destination $Destination -Recurse -Force -ErrorAction Stop

    $sourceCount  = Get-FileCount -Path $Source
    $stagingCount = Get-FileCount -Path $Destination

    if ($sourceCount -ne $stagingCount) {
        throw "La préparation des fichiers est incomplète ($stagingCount / $sourceCount fichiers copiés)."
    }

    return $sourceCount
}
```

### Programme principal - étape J8

```powershell
    # --------------------------------------------------------
    # J8 - Staging
    # --------------------------------------------------------
    # Copie complète des nouveaux fichiers AVANT tout arrêt : on vérifie
    # qu'ils sont lisibles et complets pendant que les applications tournent.

    Write-Step "[J8] Préparation des nouveaux fichiers (staging)"

    foreach ($component in $deploymentPlan) {
        $copiedCount = Copy-DirectoryContent -Source $component.PackagePath -Destination $component.StagingPath
        Write-Log -Message "Staging $($component.Trigram) prêt : $copiedCount fichiers." -Level "OK"
    }

    # Les exécutables de la nouvelle version doivent exister.
    if ($STP) {
        Assert-ExistingFile -Path (Join-Path (Join-Path $stagingDirectory "STP") $TaskflowExecutableRelativePath) -Description "Nouvel exécutable Taskflow dans le package"
    }

    if ($STJ) {
        $stjStaging = Join-Path $stagingDirectory "STJ"

        Assert-ExistingFile -Path (Join-Path (Join-Path $stjStaging $HpcLiteAgentFolder) $HpcLiteAgentExecutableName) -Description "Nouvel exécutable HpcLite Agent dans le package"
        Assert-ExistingFile -Path (Join-Path (Join-Path $stjStaging $HpcLiteRunnerFolder) $HpcLiteRunnerExecutableName) -Description "Nouvel exécutable HpcLite Runner dans le package"
        Assert-ExistingFile -Path (Join-Path (Join-Path $stjStaging $HpcLiteSchedulerFolder) $HpcLiteSchedulerExecutableName) -Description "Nouvel exécutable HpcLite Scheduler dans le package"
    }

    Write-Log -Message "Nouveaux exécutables présents dans le staging." -Level "OK"
```

