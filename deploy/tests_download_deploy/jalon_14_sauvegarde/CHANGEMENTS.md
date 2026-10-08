# Jalon 14 - code ajouté

Fichier généré par `_tools\Build-JalonVersions.ps1`. Ne pas modifier.

| | |
|---|---|
| Lignes de la version du jalon 14 | 2184 |
| Lignes de la version précédente | 2040 |
| Lignes ajoutées par ce jalon | 137 |
| Lignes retirées par ce jalon | 0 |

La version se termine par le bloc « JALON 14 ATTEINT / TEST TERMINÉ » (non repris ci-dessous).

## Ajouté

### Programme principal / configuration

```powershell
# Composants dont le dossier a été déplacé en sauvegarde. Sert au rollback.
$script:ChangedComponents = [System.Collections.ArrayList]::new()
```

### Fonction Backup-Component

```powershell
<#
.SYNOPSIS
    Déplace le dossier actuel d'un composant dans la sauvegarde. (J14)
.DESCRIPTION
    Move-Item d'un dossier ne fonctionne qu'au sein d'un même volume :
    la sauvegarde est donc sur D:, comme la destination.
    Le déplacement est enregistré immédiatement pour le rollback, puis le
    nombre de fichiers sauvegardés est contrôlé.
#>
function Backup-Component {
    param(
        [Parameter(Mandatory = $true)] [string] $Trigram,
        [Parameter(Mandatory = $true)] [string] $Destination,
        [Parameter(Mandatory = $true)] [string] $Backup
    )

    Assert-ExistingDirectory -Path $Destination -Description "Destination du composant $Trigram"

    if (Test-Path -LiteralPath $Backup) {
        throw "Une sauvegarde existe déjà à cet emplacement, elle ne sera pas écrasée : $Backup"
    }

    $fileCount = Get-FileCount -Path $Destination

    New-Item -Path (Split-Path -Parent -Path $Backup) -ItemType Directory -Force | Out-Null

    Write-Log -Message "Sauvegarde de $Trigram."
    Write-Log -Message "Ancien dossier : $Destination"
    Write-Log -Message "Sauvegarde     : $Backup"

    Move-Item -LiteralPath $Destination -Destination $Backup -ErrorAction Stop

    # Enregistré immédiatement : si la suite échoue, le rollback sait quoi faire.
    [void] $script:ChangedComponents.Add(
        [pscustomobject] @{
            Trigram     = $Trigram
            Destination = $Destination
            Backup      = $Backup
        }
    )

    $backupCount = Get-FileCount -Path $Backup

    if ($backupCount -ne $fileCount) {
        throw "Sauvegarde de $Trigram incomplète : $backupCount fichiers sur $fileCount."
    }

    Write-Log -Message "Sauvegarde de $Trigram vérifiée : $backupCount fichiers." -Level "OK"
}
```

### Fonction Invoke-Rollback

```powershell
<#
.SYNOPSIS
    Restaure les dossiers sauvegardés, dans l'ordre inverse. (J16)
.OUTPUTS
    $true si tout a été restauré (ou s'il n'y avait rien à restaurer),
    $false si au moins une restauration a échoué.
.DESCRIPTION
    Chaque composant restauré est retiré de la liste : un second appel ne
    refait rien. Une erreur sur un composant n'empêche pas les suivants.
#>
function Invoke-Rollback {
    if ($script:ChangedComponents.Count -eq 0) {
        Write-Log -Message "Aucun dossier n'a été remplacé. Aucun rollback nécessaire." -Level "ATTENTION"
        return $true
    }

    Write-Step "ROLLBACK : restauration des anciens fichiers"

    $allRestored = $true

    for ($index = $script:ChangedComponents.Count - 1; $index -ge 0; $index--) {
        $component = $script:ChangedComponents[$index]

        try {
            Write-Log -Message "Restauration de $($component.Trigram)."

            if (-not (Test-Path -LiteralPath $component.Backup -PathType Container)) {
                throw "Le dossier de sauvegarde est introuvable : $($component.Backup)"
            }

            if (Test-Path -LiteralPath $component.Destination) {
                Remove-Item -LiteralPath $component.Destination -Recurse -Force -ErrorAction Stop
            }

            Move-Item -LiteralPath $component.Backup -Destination $component.Destination -ErrorAction Stop

            $script:ChangedComponents.RemoveAt($index)

            Write-Log -Message "$($component.Trigram) a été restauré." -Level "OK"
        }
        catch {
            $allRestored = $false
            Write-Log -Message "Échec du rollback de $($component.Trigram) : $($_.Exception.Message)" -Level "ERREUR"
        }
    }

    return $allRestored
}
```

### Programme principal / configuration

```powershell
    $backupRoot = Join-Path $DestinationRoot ".rollback\$deploymentTimestamp-$deploymentId"
```

### Programme principal - étape J14

```powershell
        Write-Step "[J14] Sauvegarde et installation"

        New-Item -Path $backupRoot -ItemType Directory -Force | Out-Null

        foreach ($component in $deploymentPlan) {
            $backupPath = Join-Path $backupRoot $component.Trigram

            Backup-Component -Trigram $component.Trigram -Destination $component.Destination -Backup $backupPath

            # [POINT-DE-TEST:apres-sauvegarde]
```

### Programme principal / configuration

```powershell
        }
```

### Programme principal - étape J14

```powershell
        # Version du jalon 14 uniquement : la sauvegarde est vérifiée puis
        # immédiatement restaurée (l'installation arrive au jalon 15).
        Write-Step "[J14] Restauration des dossiers sauvegardés (test de sauvegarde)"

        if (-not (Invoke-Rollback)) {
            throw "La restauration des dossiers sauvegardés est incomplète."
        }
```

### Programme principal / configuration

```powershell
        # On arrête les éventuels nouveaux processus avant de remettre les
        # anciens fichiers.
        try {
            Write-Log -Message "Arrêt des applications avant le rollback." -Level "ATTENTION"
            Stop-SelectedApplications -Paths $paths
        }
        catch {
            Write-Log -Message "Certaines applications n'ont pas pu être arrêtées avant le rollback : $($_.Exception.Message)" -Level "ERREUR"
        }

        $rollbackComplete = Invoke-Rollback

        if (-not $rollbackComplete) {
            Write-Log -Message "ROLLBACK INCOMPLET : intervention manuelle nécessaire. Sauvegardes : $backupRoot" -Level "ERREUR"
        }
```

