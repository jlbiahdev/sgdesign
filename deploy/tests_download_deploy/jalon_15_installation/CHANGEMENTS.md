# Jalon 15 - code ajouté

Fichier généré par `_outils\Build-JalonVersions.ps1`. Ne pas modifier.

| | |
|---|---|
| Lignes de la version du jalon 15 | 2259 |
| Lignes de la version précédente | 2173 |
| Lignes ajoutées par ce jalon | 96 |
| Lignes retirées par ce jalon | 8 |

Version identique au script de production.

## Ajouté

### Configuration / variables

```powershell
# Fichiers propres au serveur, conservés d'une version à l'autre.
# Chemins relatifs au dossier du composant (<d>\taskflow, <d>\api,
# <d>\HpcLite). Ils sont recopiés depuis la sauvegarde après installation.
# Exemple : $PreservedRelativePathsSTJ = @("agent\appsettings.Production.json")
$PreservedRelativePathsSTP = @()
$PreservedRelativePathsSTX = @()
$PreservedRelativePathsSTJ = @()
```

### Fonction Install-Component

```powershell
<#
.SYNOPSIS
    Installe les nouveaux fichiers d'un composant depuis le staging. (J15)
.DESCRIPTION
    Le dossier de staging (sur D:) est déplacé vers la destination, puis
    les fichiers propres au serveur ($PreservedRelativePaths<TRI>) sont
    recopiés depuis la sauvegarde.
#>
function Install-Component {
    param(
        [Parameter(Mandatory = $true)] [string] $Trigram,
        [Parameter(Mandatory = $true)] [string] $Source,
        [Parameter(Mandatory = $true)] [string] $Destination,
        [Parameter(Mandatory = $true)] [string] $Backup
    )

    Assert-ExistingDirectory -Path $Source -Description "Staging du composant $Trigram"

    $stagingCount = Get-FileCount -Path $Source

    Write-Log -Message "Installation des nouveaux fichiers de $Trigram."

    try {
        Move-Item -LiteralPath $Source -Destination $Destination -ErrorAction Stop
    }
    catch {
        throw @"
Impossible d'installer les nouveaux fichiers de $Trigram.

Source :
$Source

Destination :
$Destination

Détail :
$($_.Exception.Message)
"@
    }

    $preservedPaths = @((Get-Variable -Name "PreservedRelativePaths$Trigram" -ValueOnly))

    foreach ($relativePath in $preservedPaths) {
        if ([string]::IsNullOrWhiteSpace($relativePath)) { continue }

        $preservedSource = Join-Path $Backup $relativePath
        $preservedTarget = Join-Path $Destination $relativePath

        if (Test-Path -LiteralPath $preservedSource -PathType Leaf) {
            New-Item -Path (Split-Path -Parent $preservedTarget) -ItemType Directory -Force | Out-Null
            Copy-Item -LiteralPath $preservedSource -Destination $preservedTarget -Force -ErrorAction Stop
            Write-Log -Message "Fichier conservé depuis l'ancienne version : $relativePath"
        }
        else {
            Write-Log -Message "Fichier à conserver absent de l'ancienne version : $relativePath" -Level "ATTENTION"
        }
    }

    $installedCount = Get-FileCount -Path $Destination

    if ($installedCount -lt $stagingCount) {
        throw "Installation de $Trigram incomplète : $installedCount fichiers pour $stagingCount attendus."
    }

    Write-Log -Message "$Trigram a été installé correctement : $installedCount fichiers." -Level "OK"
}
```

### Programme principal / configuration

```powershell
            Install-Component -Trigram $component.Trigram -Source $component.StagingPath -Destination $component.Destination -Backup $backupPath

            # [POINT-DE-TEST:apres-installation-composant]
```

### Programme principal / configuration

```powershell
    # --------------------------------------------------------
    # J15 - Succès
    # --------------------------------------------------------

    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Green
    Write-Host "DÉPLOIEMENT TERMINÉ AVEC SUCCÈS" -ForegroundColor Green
    Write-Host ("=" * 60) -ForegroundColor Green

    Write-Log -Message "Déploiement terminé avec succès." -Level "OK"
    Write-Log -Message "Sauvegarde disponible dans : $backupRoot"
    Write-Log -Message "Journal disponible dans : $($script:LogFile)"

    if ($STJ -and $previousState.RunnerCountBefore -gt 0) {
        Write-Log -Message "$($previousState.RunnerCountBefore) Runner(s) ont été arrêtés brutalement." -Level "ATTENTION"
        Write-Log -Message "Ils n'ont pas été redémarrés directement par le script." -Level "ATTENTION"
    }

    exit 0
```

## Retiré

### Programme principal - étape J14

```powershell
        # Version du jalon 14 uniquement : la sauvegarde est vérifiée puis
        # immédiatement restaurée (l'installation arrive au jalon 15).
        Write-Step "[J14] Restauration des dossiers sauvegardés (test de sauvegarde)"

        if (-not (Invoke-Rollback)) {
            throw "La restauration des dossiers sauvegardés est incomplète."
        }
```

