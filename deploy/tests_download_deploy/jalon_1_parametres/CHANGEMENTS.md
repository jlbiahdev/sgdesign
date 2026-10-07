# Jalon 1 - code ajouté

Fichier généré par `_outils\Build-JalonVersions.ps1`. Ne pas modifier.

| | |
|---|---|
| Lignes de la version du jalon 1 | 417 |
| Lignes de la version précédente | 392 |
| Lignes ajoutées par ce jalon | 25 |
| Lignes retirées par ce jalon | 0 |

La version se termine par le bloc « JALON 1 ATTEINT / TEST TERMINÉ » (non repris ci-dessous).

## Ajouté

### Programme principal - étape J1

```powershell
    # --------------------------------------------------------
    # J1 - Paramètres reçus
    # --------------------------------------------------------

    Write-Step "[J1] Paramètres reçus"

    Write-Log -Message "Destination demandée (-d) : $DestinationRoot"
    Write-Log -Message "STP demandé : $STP"
    Write-Log -Message "STX demandé : $STX"
    Write-Log -Message "STJ demandé : $STJ"

    if ($usePackageFile) {
        Write-Log -Message "Source du package : fichier local ($PackageFile)"
    }
    elseif (-not [string]::IsNullOrWhiteSpace($PackageUrl)) {
        Write-Log -Message "Source du package : URL passée en paramètre"
    }
    else {
        Write-Log -Message "Source du package : variable STYX_PACKAGE_URL"
    }

    Write-Log -Message "Validation seule (-ValidationOnly) : $ValidationOnly"
    Write-Log -Message "Sans confirmation (-Force) : $Force"
    Write-Log -Message "Conserver les fichiers temporaires : $KeepTemporaryFiles"
```

