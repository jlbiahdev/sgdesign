# Jalon 0 - code ajouté

Fichier généré par `_outils\Build-JalonVersions.ps1`. Ne pas modifier.

| | |
|---|---|
| Lignes de la version du jalon 0 | 392 |
| Lignes de la version précédente | 0 |
| Lignes ajoutées par ce jalon | 142 |
| Lignes retirées par ce jalon | 0 |

La version se termine par le bloc « JALON 0 ATTEINT / TEST TERMINÉ » (non repris ci-dessous).

## Ajouté

### Configuration / variables

```powershell
# Lecteur obligatoire pour la destination, le journal, le staging et
# les sauvegardes.
$RequiredDrive = "D:\"
```

### Configuration / variables

```powershell
# Outils Windows utilisés.
# curl.exe est appelé explicitement : dans Windows PowerShell 5.1,
# « curl » est un alias d'Invoke-WebRequest.
$AppCmdPath = Join-Path $env:WINDIR "System32\inetsrv\appcmd.exe"
$CurlPath = Join-Path $env:WINDIR "System32\curl.exe"
```

### Fonction Write-Log

```powershell
<#
.SYNOPSIS
    Écrit un message horodaté dans la console (en couleur) et dans le journal.
.DESCRIPTION
    Format : [yyyy-MM-dd HH:mm:ss] [NIVEAU] message
    Avant la création du journal, les lignes sont mises en attente puis
    recopiées dans le fichier par Set-LogFile.
    Ne jamais passer de secret à cette fonction.
#>
function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Message,

        [ValidateSet("INFO", "OK", "ATTENTION", "ERREUR")]
        [string] $Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] [$Level] $Message"

    switch ($Level) {
        "OK"        { Write-Host $line -ForegroundColor Green }
        "ATTENTION" { Write-Host $line -ForegroundColor Yellow }
        "ERREUR"    { Write-Host $line -ForegroundColor Red }
        default     { Write-Host $line }
    }

    if ([string]::IsNullOrWhiteSpace($script:LogFile)) {
        $script:PendingLogLines.Add($line)
        return
    }

    Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
}
```

### Fonction Write-Step

```powershell
<#
.SYNOPSIS
    Affiche un titre d'étape encadré et l'écrit dans le journal.
#>
function Write-Step {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Title
    )

    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host $Title -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor Cyan

    Write-Log -Message $Title
}
```

### Fonction Assert-Administrator

```powershell
<#
.SYNOPSIS
    Vérifie que la console est ouverte en tant qu'administrateur. (J0)
#>
function Assert-Administrator {
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)

    $isAdministrator = $principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )

    if (-not $isAdministrator) {
        throw @"
Ce script doit être exécuté en tant qu'administrateur.

Fermez cette fenêtre, puis :
1. faites un clic droit sur PowerShell ;
2. choisissez « Exécuter en tant qu'administrateur » ;
3. relancez la commande.
"@
    }

    Write-Log -Message "Console administrateur : oui." -Level "OK"
}
```

### Fonction Assert-ServerCompatibility

```powershell
<#
.SYNOPSIS
    Vérifie que le serveur dispose de ce dont le script a besoin. (J0)
.DESCRIPTION
    - version de PowerShell (garantie par #requires, journalisée ici) ;
    - lecteur obligatoire ($RequiredDrive) ;
    - curl.exe, sauf si le package est fourni localement (-PackageFile) ;
    - appcmd.exe (IIS), si l'API est demandée (-STX).
#>
function Assert-ServerCompatibility {
    Write-Log -Message "Version de PowerShell : $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))." -Level "OK"

    if (-not (Test-Path -LiteralPath $RequiredDrive -PathType Container)) {
        throw @"
Le lecteur $RequiredDrive est introuvable sur ce serveur.

Le déploiement exige ce lecteur pour les applications, le journal,
les fichiers temporaires et les sauvegardes.
"@
    }

    Write-Log -Message "Lecteur $RequiredDrive disponible." -Level "OK"

    if ($usePackageFile) {
        Write-Log -Message "Package local fourni : curl.exe n'est pas nécessaire."
    }
    else {
        Assert-ExistingFile -Path $CurlPath -Description "Outil de téléchargement curl.exe (Windows 10 / Server 2019 et ultérieurs)"
        Write-Log -Message "curl.exe disponible : $CurlPath" -Level "OK"
    }

    if ($STX) {
        Assert-ExistingFile -Path $AppCmdPath -Description "Outil d'administration IIS appcmd.exe"
        Write-Log -Message "IIS (appcmd.exe) disponible : $AppCmdPath" -Level "OK"
    }
}
```

### Fonction Assert-ExistingFile

```powershell
<#
.SYNOPSIS
    Échoue avec un message clair si le fichier n'existe pas.
#>
function Assert-ExistingFile {
    param(
        [Parameter(Mandatory = $true)] [string] $Path,
        [Parameter(Mandatory = $true)] [string] $Description
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw @"
$Description introuvable.

Fichier attendu :
$Path

Vérifiez le nom configuré au début du script.
"@
    }
}
```

