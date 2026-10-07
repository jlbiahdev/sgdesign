# Jalon 10 - code ajouté

Fichier généré par `_outils\Build-JalonVersions.ps1`. Ne pas modifier.

| | |
|---|---|
| Lignes de la version du jalon 10 | 1471 |
| Lignes de la version précédente | 1386 |
| Lignes ajoutées par ce jalon | 78 |
| Lignes retirées par ce jalon | 0 |

La version se termine par le bloc « JALON 10 ATTEINT / TEST TERMINÉ » (non repris ci-dessous).

## Ajouté

### Configuration / variables

```powershell
# Nom exact du pool IIS qui héberge l'API STX.
$StxApplicationPoolName = "STYX"
```

### Fonction Assert-IisConfiguration

```powershell
<#
.SYNOPSIS
    Vérifie que le pool IIS configuré existe. (J10)
#>
function Assert-IisConfiguration {
    param(
        [Parameter(Mandatory = $true)]
        [string] $ApplicationPoolName
    )

    Assert-ExistingFile -Path $AppCmdPath -Description "Outil d'administration IIS appcmd.exe"

    $output     = & $AppCmdPath list apppool "/apppool.name:$ApplicationPoolName" 2>&1
    $exitCode   = $LASTEXITCODE
    $outputText = $output -join [Environment]::NewLine

    if ($exitCode -ne 0 -or [string]::IsNullOrWhiteSpace($outputText)) {
        throw @"
Le pool IIS configuré pour l'API est introuvable.

Nom du pool :
$ApplicationPoolName

Vérifiez la variable StxApplicationPoolName au début du script.
"@
    }

    Write-Log -Message "Pool IIS '$ApplicationPoolName' trouvé." -Level "OK"
}
```

### Fonction Get-IisApplicationPoolState

```powershell
<#
.SYNOPSIS
    Renvoie Started, Stopped ou Unknown pour le pool IIS.
#>
function Get-IisApplicationPoolState {
    param(
        [Parameter(Mandatory = $true)]
        [string] $ApplicationPoolName
    )

    $output = & $AppCmdPath list apppool "/apppool.name:$ApplicationPoolName" 2>&1

    if ($LASTEXITCODE -ne 0) {
        throw "Impossible de lire l'état du pool IIS '$ApplicationPoolName'."
    }

    $text = $output -join " "

    if ($text -match "state:Started") { return "Started" }
    if ($text -match "state:Stopped") { return "Stopped" }

    # Sortie inattendue : on ne prétend pas connaître une information incertaine.
    return "Unknown"
}
```

### Programme principal - étape J10

```powershell
    # --------------------------------------------------------
    # J10 - IIS
    # --------------------------------------------------------

    Write-Step "[J10] Pool IIS de l'API"

    $apiState = "NotSelected"

    if ($STX) {
        Assert-IisConfiguration -ApplicationPoolName $StxApplicationPoolName

        $apiState = Get-IisApplicationPoolState -ApplicationPoolName $StxApplicationPoolName

        if ($apiState -eq "Unknown") {
            throw "L'état du pool IIS '$StxApplicationPoolName' n'a pas pu être déterminé. Déploiement annulé."
        }

        Write-Log -Message "État actuel du pool IIS STX : $apiState"
    }
    else {
        Write-Log -Message "API non demandée : IIS n'est pas consulté."
    }
```

