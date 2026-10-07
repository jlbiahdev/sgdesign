# Jalon 3 - code ajouté

Fichier généré par `_outils\Build-JalonVersions.ps1`. Ne pas modifier.

| | |
|---|---|
| Lignes de la version du jalon 3 | 586 |
| Lignes de la version précédente | 558 |
| Lignes ajoutées par ce jalon | 27 |
| Lignes retirées par ce jalon | 0 |

La version se termine par le bloc « JALON 3 ATTEINT / TEST TERMINÉ » (non repris ci-dessous).

## Ajouté

### Programme principal / configuration

```powershell
    # --------------------------------------------------------
    # [J3] Au moins une application demandée
    # --------------------------------------------------------

    if (-not ($STP -or $STX -or $STJ)) {
        throw @"
Aucune application n'a été sélectionnée.

Ajoutez au moins un des paramètres suivants :
-STP  pour Taskflow
-STX  pour l'API
-STJ  pour HpcLite

Exemple :
.\download_deploy.ps1 -d "D:\Applications" -STX
"@
    }
```

### Programme principal - étape J3

```powershell
    # --------------------------------------------------------
    # J3 - Synthèse de la demande validée
    # --------------------------------------------------------

    Write-Step "[J3] Vérification de la demande"

    Write-Log -Message "Identifiant du déploiement : $deploymentId"
    Write-Log -Message "Dossier racine valide : $DestinationRoot" -Level "OK"
    Write-Log -Message "Applications demandées : $((@('STP', 'STX', 'STJ') | Where-Object { Get-Variable -Name $_ -ValueOnly }) -join ', ')" -Level "OK"
```

