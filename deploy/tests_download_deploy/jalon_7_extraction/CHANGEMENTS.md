# Jalon 7 - code ajouté

Fichier généré par `_outils\Build-JalonVersions.ps1`. Ne pas modifier.

| | |
|---|---|
| Lignes de la version du jalon 7 | 1083 |
| Lignes de la version précédente | 952 |
| Lignes ajoutées par ce jalon | 129 |
| Lignes retirées par ce jalon | 0 |

La version se termine par le bloc « JALON 7 ATTEINT / TEST TERMINÉ » (non repris ci-dessous).

## Ajouté

### Fonction Get-FileCount

```powershell
<#
.SYNOPSIS
    Compte les fichiers d'un dossier, sous-dossiers compris.
#>
function Get-FileCount {
    param(
        [Parameter(Mandatory = $true)] [string] $Path
    )

    return @(Get-ChildItem -LiteralPath $Path -File -Recurse -Force).Count
}
```

### Fonction Expand-NuGetPackage

```powershell
<#
.SYNOPSIS
    Extrait un .nupkg (archive ZIP) dans un dossier. (J7)
.DESCRIPTION
    Extraction .NET plutôt qu'Expand-Archive :
    - NuGet encode certains caractères des noms (espace -> %20) : décodés ;
    - toute entrée qui sortirait du dossier cible est refusée (« zip slip »).
#>
function Expand-NuGetPackage {
    param(
        [Parameter(Mandatory = $true)] [string] $PackageFile,
        [Parameter(Mandatory = $true)] [string] $Destination
    )

    Write-Log -Message "Vérification et extraction du package."

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $destinationFull = [IO.Path]::GetFullPath($Destination).TrimEnd("\") + "\"

    try {
        $zip = [IO.Compression.ZipFile]::OpenRead($PackageFile)
    }
    catch {
        throw @"
Le package n'est pas une archive NuGet/ZIP valide.

Détail :
$($_.Exception.Message)
"@
    }

    $extractedCount = 0

    try {
        foreach ($entry in $zip.Entries) {
            $entryName = [Uri]::UnescapeDataString($entry.FullName)

            # Les entrées terminées par "/" sont des dossiers.
            if ($entryName.EndsWith("/") -or $entryName.EndsWith("\")) {
                continue
            }

            $relativePath = $entryName.Replace("/", "\")
            $targetPath   = [IO.Path]::GetFullPath((Join-Path $Destination $relativePath))

            if (-not $targetPath.StartsWith($destinationFull, [StringComparison]::OrdinalIgnoreCase)) {
                throw "Entrée suspecte dans le package (chemin hors du dossier d'extraction) : $entryName"
            }

            New-Item -Path (Split-Path -Parent -Path $targetPath) -ItemType Directory -Force | Out-Null

            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $targetPath, $true)
            $extractedCount++
        }
    }
    finally {
        $zip.Dispose()
    }

    Write-Log -Message "Package extrait correctement : $extractedCount fichiers." -Level "OK"
}
```

### Programme principal - étape J7

```powershell
    # --------------------------------------------------------
    # J7 - Extraction et contrôle du contenu
    # --------------------------------------------------------

    Write-Step "[J7] Extraction et contrôle du package"

    Expand-NuGetPackage -PackageFile $workingPackageFile -Destination $extractionDirectory

    $deploymentPlan = @()

    if ($STP) {
        $deploymentPlan += [pscustomobject] @{
            Trigram     = "STP"
            PackagePath = Join-Path $extractionDirectory "content\taskflow"
            StagingPath = Join-Path $stagingDirectory "STP"
            Destination = $taskflowDestination
        }
    }

    if ($STX) {
        $deploymentPlan += [pscustomobject] @{
            Trigram     = "STX"
            PackagePath = Join-Path $extractionDirectory "content\api"
            StagingPath = Join-Path $stagingDirectory "STX"
            Destination = $apiDestination
        }
    }

    if ($STJ) {
        $deploymentPlan += [pscustomobject] @{
            Trigram     = "STJ"
            PackagePath = Join-Path $extractionDirectory "content\hpclite"
            StagingPath = Join-Path $stagingDirectory "STJ"
            Destination = $hpcLiteDestination
        }
    }

    # Seuls les contenus demandés sont contrôlés.
    foreach ($component in $deploymentPlan) {
        Assert-ExistingDirectory -Path $component.PackagePath -Description "Contenu $($component.Trigram) dans le package"

        $fileCount = Get-FileCount -Path $component.PackagePath

        if ($fileCount -eq 0) {
            throw @"
Le dossier $($component.Trigram) existe dans le package, mais il est vide.

Dossier contrôlé :
$($component.PackagePath)
"@
        }

        Write-Log -Message "Contenu $($component.Trigram) trouvé : $fileCount fichiers." -Level "OK"
    }
```

