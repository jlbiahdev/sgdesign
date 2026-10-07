# Jalon 6 - code ajouté

Fichier généré par `_outils\Build-JalonVersions.ps1`. Ne pas modifier.

| | |
|---|---|
| Lignes de la version du jalon 6 | 952 |
| Lignes de la version précédente | 785 |
| Lignes ajoutées par ce jalon | 160 |
| Lignes retirées par ce jalon | 0 |

La version se termine par le bloc « JALON 6 ATTEINT / TEST TERMINÉ » (non repris ci-dessous).

## Ajouté

### Configuration / variables

```powershell
# Initialisée ici pour que le bloc finally fonctionne même si l'erreur
# survient très tôt (Set-StrictMode interdit les variables non définies).
$workingDirectory = $null
```

### Fonction Save-ArtifactoryPackage

```powershell
<#
.SYNOPSIS
    Télécharge le package avec curl.exe. (J6)
.DESCRIPTION
    Équivalent de : curl -u utilisateur:token -L -o <fichier> <url>
    mais les identifiants sont transmis à curl par son entrée standard
    (--config -) et non en argument : la ligne de commande d'un processus
    est visible des autres utilisateurs (Gestionnaire des tâches).
#>
function Save-ArtifactoryPackage {
    param(
        [Parameter(Mandatory = $true)] [string] $Url,
        [Parameter(Mandatory = $true)] [string] $Username,
        [Parameter(Mandatory = $true)] [string] $Token,
        [Parameter(Mandatory = $true)] [string] $OutputFile
    )

    Assert-ExistingFile -Path $CurlPath -Description "Outil de téléchargement curl.exe"

    Write-Log -Message "Téléchargement du package depuis Artifactory (curl.exe)."
    Write-Log -Message "Adresse : $Url"

    # Format du fichier de configuration curl : user = "utilisateur:token"
    $escapedUser  = $Username.Replace('\', '\\').Replace('"', '\"')
    $escapedToken = $Token.Replace('\', '\\').Replace('"', '\"')
    $curlConfig   = "user = `"${escapedUser}:${escapedToken}`""

    $curlArguments = @(
        "--config", "-",            # identifiants lus sur l'entrée standard
        "--location",               # -L : suit les redirections Artifactory
        "--fail",                   # code de sortie 22 si HTTP >= 400
        "--silent", "--show-error",
        "--connect-timeout", "30",
        "--output", $OutputFile,
        "--write-out", '%{http_code}',
        $Url
    )

    # Avec Windows PowerShell 5.1, la sortie d'erreur d'un programme externe
    # redirigée par 2>&1 devient une erreur PowerShell, bloquante avec
    # $ErrorActionPreference = "Stop". On l'assouplit le temps de l'appel.
    $previousErrorActionPreference = $ErrorActionPreference

    try {
        $ErrorActionPreference = "Continue"
        $curlOutput   = @($curlConfig | & $CurlPath @curlArguments 2>&1)
        $curlExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference

        # On efface le secret dès que possible.
        $curlConfig   = $null
        $escapedToken = $null
    }

    $curlErrors = @($curlOutput | Where-Object { $_ -is [Management.Automation.ErrorRecord] })
    $httpCode   = (@($curlOutput | Where-Object { $_ -isnot [Management.Automation.ErrorRecord] }) -join "").Trim()

    if ($curlExitCode -ne 0) {
        Remove-Item -LiteralPath $OutputFile -Force -ErrorAction SilentlyContinue

        $hint = switch ($httpCode) {
            "401"   { "Identifiants refusés : vérifiez ARTIFACTORY_USERNAME et ARTIFACTORY_TOKEN." }
            "403"   { "Accès refusé : le compte n'a pas les droits sur ce dépôt." }
            "404"   { "Package introuvable : vérifiez l'adresse (version, nom du fichier)." }
            default { "Vérifiez l'adresse, le réseau et un éventuel proxy (code curl $curlExitCode)." }
        }

        # Les messages de curl ne contiennent pas le token.
        throw @"
Le téléchargement du package a échoué.

Code HTTP : $httpCode
$hint

Détail curl :
$(($curlErrors | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine)
"@
    }

    Write-Log -Message "Réponse HTTP : $httpCode"
    Assert-PackageFile -Path $OutputFile -Description "Package téléchargé"
}
```

### Fonction Assert-PackageFile

```powershell
<#
.SYNOPSIS
    Vérifie qu'un package existe, n'est pas vide, et journalise taille et
    empreinte SHA-256.
#>
function Assert-PackageFile {
    param(
        [Parameter(Mandatory = $true)] [string] $Path,
        [Parameter(Mandatory = $true)] [string] $Description
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Description : aucun fichier n'a été créé."
    }

    $file = Get-Item -LiteralPath $Path

    if ($file.Length -eq 0) {
        throw "$Description : le fichier est vide."
    }

    $hash = Get-FileHash -LiteralPath $Path -Algorithm SHA256

    Write-Log -Message "$Description : $($file.Length) octets." -Level "OK"
    Write-Log -Message "Empreinte SHA-256 : $($hash.Hash)"
}
```

### Programme principal - étape J6

```powershell
    # --------------------------------------------------------
    # J6 - Téléchargement (ou copie du package local)
    # --------------------------------------------------------
    # Le dossier de travail est sur D:, comme les destinations : Move-Item
    # ne sait pas déplacer un dossier d'un volume à un autre.

    Write-Step "[J6] Récupération du package"

    $workingDirectory    = Join-Path $DestinationRoot ".deploy\$deploymentTimestamp-$deploymentId"
    $extractionDirectory = Join-Path $workingDirectory "extracted"
    $stagingDirectory    = Join-Path $workingDirectory "staging"
    $workingPackageFile  = Join-Path $workingDirectory "Styx.Publish.nupkg"

    New-Item -Path $extractionDirectory -ItemType Directory -Force | Out-Null
    New-Item -Path $stagingDirectory    -ItemType Directory -Force | Out-Null

    Write-Log -Message "Dossier de travail : $workingDirectory"

    if ($usePackageFile) {
        Copy-Item -LiteralPath $PackageFile -Destination $workingPackageFile -Force -ErrorAction Stop
        Assert-PackageFile -Path $workingPackageFile -Description "Package local copié"
    }
    else {
        Save-ArtifactoryPackage `
            -Url $PackageUrl `
            -Username $usernameSetting.Value `
            -Token $tokenSetting.Value `
            -OutputFile $workingPackageFile

        $tokenSetting = $null
    }
```

### Programme principal / configuration

```powershell
    if (-not [string]::IsNullOrWhiteSpace($workingDirectory) -and (Test-Path -LiteralPath $workingDirectory)) {
        if ($KeepTemporaryFiles) {
            Write-Log -Message "Les fichiers temporaires sont conservés dans : $workingDirectory" -Level "ATTENTION"
        }
        else {
            Remove-Item -LiteralPath $workingDirectory -Recurse -Force -ErrorAction SilentlyContinue

            # Supprime aussi <d>\.deploy s'il est vide.
            $deployRoot = Split-Path -Parent -Path $workingDirectory

            if ((Test-Path -LiteralPath $deployRoot) -and @(Get-ChildItem -LiteralPath $deployRoot -Force).Count -eq 0) {
                Remove-Item -LiteralPath $deployRoot -Force -ErrorAction SilentlyContinue
            }
        }
    }
```

