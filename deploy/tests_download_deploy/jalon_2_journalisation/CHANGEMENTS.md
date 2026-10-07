# Jalon 2 - code ajouté

Fichier généré par `_outils\Build-JalonVersions.ps1`. Ne pas modifier.

| | |
|---|---|
| Lignes de la version du jalon 2 | 558 |
| Lignes de la version précédente | 417 |
| Lignes ajoutées par ce jalon | 139 |
| Lignes retirées par ce jalon | 0 |

La version se termine par le bloc « JALON 2 ATTEINT / TEST TERMINÉ » (non repris ci-dessous).

## Ajouté

### Fonction Set-LogFile

```powershell
<#
.SYNOPSIS
    Crée le fichier journal et y recopie les lignes en attente.
.DESCRIPTION
    Échoue (exception) si le fichier ne peut pas être écrit : un
    déploiement sans journal n'est pas acceptable.
#>
function Set-LogFile {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    Set-Content -LiteralPath $Path -Value $script:PendingLogLines -Encoding UTF8 -ErrorAction Stop

    $script:LogFile = $Path
    $script:PendingLogLines.Clear()
}
```

### Fonction Get-ValidatedDestinationRoot

```powershell
<#
.SYNOPSIS
    Valide la racine -d et la renvoie sous forme normalisée. (J3)
.DESCRIPTION
    Refuse : chemin vide, relatif, « D: » sans antislash, situé sur un
    autre lecteur que $RequiredDrive, inexistant. Ne crée jamais le dossier.
#>
function Get-ValidatedDestinationRoot {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string] $Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw "Le paramètre -d est vide."
    }

    # « D: » seul est accepté par IsPathRooted mais désigne le dossier
    # courant du lecteur : on exige un chemin du type D:\...
    if (-not [IO.Path]::IsPathRooted($Path) -or $Path -notmatch '^[A-Za-z]:\\') {
        throw @"
La destination doit être un chemin Windows complet.

Chemin reçu :
$Path

Exemple correct :
D:\Applications
"@
    }

    try {
        $fullPath = [IO.Path]::GetFullPath($Path)
    }
    catch {
        throw "Le chemin de destination n'est pas valide : $Path"
    }

    $root = [IO.Path]::GetPathRoot($fullPath)

    if (-not $root.Equals($RequiredDrive, [StringComparison]::OrdinalIgnoreCase)) {
        throw @"
Le dossier de destination doit obligatoirement être situé sur le lecteur $RequiredDrive

Chemin reçu :
$fullPath

Lecteur détecté :
$root
"@
    }

    if (-not (Test-Path -LiteralPath $fullPath -PathType Container)) {
        throw @"
Le dossier fourni avec -d n'existe pas.

Dossier recherché :
$fullPath

Le script ne crée pas automatiquement ce dossier.
"@
    }

    $resolvedPath = (Resolve-Path -LiteralPath $fullPath -ErrorAction Stop).ProviderPath

    # On ne retire pas le "\" si le chemin est simplement D:\.
    if ($resolvedPath.Length -gt 3) {
        $resolvedPath = $resolvedPath.TrimEnd("\")
    }

    # Un lien symbolique pourrait pointer ailleurs : on revérifie.
    $resolvedRoot = [IO.Path]::GetPathRoot($resolvedPath)

    if (-not $resolvedRoot.Equals($RequiredDrive, [StringComparison]::OrdinalIgnoreCase)) {
        throw @"
Après résolution, le dossier ne se trouve pas sur $RequiredDrive

Dossier résolu :
$resolvedPath
"@
    }

    return $resolvedPath
}
```

### Programme principal - étape J2

```powershell
    # --------------------------------------------------------
    # [J2] Journal
    # --------------------------------------------------------
    # Le journal est créé dans <d>\deployment-logs : -d est donc validé
    # dès ce jalon (lecteur, chemin complet, existence).

    $DestinationRoot = Get-ValidatedDestinationRoot -Path $DestinationRoot

    Write-Step "[J2] Journal"

    $logDirectory = Join-Path $DestinationRoot "deployment-logs"

    try {
        New-Item -Path $logDirectory -ItemType Directory -Force -ErrorAction Stop | Out-Null

        $deploymentTimestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $deploymentId        = [Guid]::NewGuid().ToString("N")

        Set-LogFile -Path (Join-Path $logDirectory "deployment-$deploymentTimestamp-$($deploymentId.Substring(0, 8)).log")
    }
    catch {
        throw @"
Impossible de créer le journal du déploiement.

Dossier attendu :
$logDirectory

Détail :
$($_.Exception.Message)
"@
    }

    Write-Log -Message "Journal créé : $($script:LogFile)" -Level "OK"

    # [POINT-DE-TEST:apres-journal]
```

