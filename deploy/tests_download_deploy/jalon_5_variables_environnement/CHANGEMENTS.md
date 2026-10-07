# Jalon 5 - code ajouté

Fichier généré par `_outils\Build-JalonVersions.ps1`. Ne pas modifier.

| | |
|---|---|
| Lignes de la version du jalon 5 | 785 |
| Lignes de la version précédente | 668 |
| Lignes ajoutées par ce jalon | 112 |
| Lignes retirées par ce jalon | 0 |

La version se termine par le bloc « JALON 5 ATTEINT / TEST TERMINÉ » (non repris ci-dessous).

## Ajouté

### Fonction Get-ConfigurationValue

```powershell
<#
.SYNOPSIS
    Lit une variable d'environnement : session courante, puis Machine.
.DESCRIPTION
    Le niveau Machine est relu directement : une console ouverte avant la
    création de la variable ne la voit pas dans $env:.
    Renvoie $null si absente, sinon un objet { Value ; Source }.
    La valeur n'est jamais journalisée par l'appelant.
#>
function Get-ConfigurationValue {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name
    )

    $value  = [Environment]::GetEnvironmentVariable($Name, "Process")
    $source = "session"

    if ([string]::IsNullOrWhiteSpace($value)) {
        $value  = [Environment]::GetEnvironmentVariable($Name, "Machine")
        $source = "machine"
    }

    if ([string]::IsNullOrWhiteSpace($value)) {
        return $null
    }

    return [pscustomobject] @{
        Value  = $value
        Source = $source
    }
}
```

### Programme principal - étape J5

```powershell
    # --------------------------------------------------------
    # J5 - Source du package et variables d'environnement
    # --------------------------------------------------------

    Write-Step "[J5] Source du package"

    $usernameSetting = $null
    $tokenSetting    = $null

    if ($usePackageFile) {
        if (-not [IO.Path]::IsPathRooted($PackageFile)) {
            throw "Le chemin du package (-PackageFile) doit être complet : $PackageFile"
        }

        $PackageFile = [IO.Path]::GetFullPath($PackageFile)

        Assert-ExistingFile -Path $PackageFile -Description "Package local (-PackageFile)"

        Write-Log -Message "Package local trouvé : $PackageFile" -Level "OK"
        Write-Log -Message "Aucun identifiant Artifactory n'est nécessaire."
    }
    else {
        $usernameSetting = Get-ConfigurationValue -Name "ARTIFACTORY_USERNAME"
        $tokenSetting    = Get-ConfigurationValue -Name "ARTIFACTORY_TOKEN"

        if ($null -eq $usernameSetting) {
            throw @"
Le nom d'utilisateur Artifactory est absent.

Définissez la variable ARTIFACTORY_USERNAME (niveau Machine en production,
ou `$env:ARTIFACTORY_USERNAME pour la session courante).
"@
        }

        if ($null -eq $tokenSetting) {
            throw @"
Le token Artifactory est absent.

Définissez la variable ARTIFACTORY_TOKEN (niveau Machine en production,
ou `$env:ARTIFACTORY_TOKEN pour la session courante).
"@
        }

        Write-Log -Message "Utilisateur Artifactory trouvé (variables $($usernameSetting.Source))." -Level "OK"
        Write-Log -Message "Token Artifactory trouvé (variables $($tokenSetting.Source))." -Level "OK"

        if ([string]::IsNullOrWhiteSpace($PackageUrl)) {
            $urlSetting = Get-ConfigurationValue -Name "STYX_PACKAGE_URL"

            if ($null -eq $urlSetting) {
                throw @"
L'adresse du package est absente.

Trois possibilités :

1. passer l'adresse dans la commande :
   -PackageUrl "https://.../Styx.Publish.1.2.3.nupkg"

2. définir la variable d'environnement STYX_PACKAGE_URL ;

3. fournir un package local : -PackageFile "D:\...\Styx.Publish.1.2.3.nupkg"
"@
            }

            $PackageUrl = $urlSetting.Value
            Write-Log -Message "Adresse du package trouvée (variables $($urlSetting.Source))." -Level "OK"
        }

        if (-not $PackageUrl.StartsWith("https://", [StringComparison]::OrdinalIgnoreCase)) {
            throw @"
L'adresse du package doit commencer par https://

Adresse reçue :
$PackageUrl
"@
        }

        Write-Log -Message "Adresse du package valide : $PackageUrl" -Level "OK"
    }
```

