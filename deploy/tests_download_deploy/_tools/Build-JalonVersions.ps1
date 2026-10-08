#requires -Version 5.1

<#
.SYNOPSIS
    Génère, à partir du modèle, le script de production et la version
    incrémentale de download_deploy.ps1 propre à chaque jalon.

.DESCRIPTION
    Source unique : _tools\download_deploy.template.ps1

    Le modèle est le script complet, découpé par balises (lignes commençant
    en colonne 0 par le caractère dièse, retirées de toutes les versions
    générées). Notées ici [#] pour ne pas fermer ce bloc d'aide :

        [#]>>J<a>   ...   [#]<<J<a>       code présent à partir du jalon a
        [#]>>J<a>-<b> ... [#]<<J<a>-<b>   code présent du jalon a au jalon b
        [#]@FIN <n>|<description>         fin de la version du jalon n

    Pour chaque jalon N (0 à 19), la version générée contient UNIQUEMENT le
    code des régions dont le jalon d'introduction est <= N. Pour N <= 14,
    elle se termine, à l'endroit marqué [#]@FIN N, par :

        JALON N ATTEINT : <description>.
        TEST TERMINÉ : ...
        exit 0

    Les versions des jalons 15 à 19 sont identiques au script de production.

    Fichiers écrits (UTF-8 avec BOM, fins de ligne Windows) :
      - <racine>\download_deploy.ps1                  script de production
      - <racine>\jalon_N_*\t_*\download_deploy.ps1     version du jalon N
      - <racine>\jalon_N_*\CHANGEMENTS.md              code ajouté au jalon N

    Contrôles effectués :
      - balises équilibrées et bien imbriquées ;
      - chaque version est syntaxiquement valide (analyseur PowerShell) ;
      - chaque jalon 0 à 14 possède exactement une fin [#]@FIN ;
      - les versions 15 à 19 sont identiques au script de production.

.PARAMETER Racine
    Dossier tests_download_deploy. Par défaut : le dossier parent de _tools.

.EXAMPLE
    .\_tools\Build-JalonVersions.ps1

.NOTES
    À relancer après TOUTE modification du modèle. Ne jamais modifier à la
    main les download_deploy.ps1 générés : la modification serait perdue.
#>

[CmdletBinding()]
param(
    [string] $Racine = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$templatePath = Join-Path $PSScriptRoot "download_deploy.template.ps1"
$utf8Bom      = New-Object System.Text.UTF8Encoding $true

# Lecture du modèle (BOM éventuel ignoré, fins de ligne normalisées).
$templateText  = [IO.File]::ReadAllText($templatePath).TrimStart([char] 0xFEFF).Replace("`r`n", "`n")
$templateLines = $templateText.TrimEnd("`n").Split("`n")

$openPattern  = '^#>>J(\d+)(?:-(\d+))?\s*$'
$closePattern = '^#<<J(\d+)(?:-(\d+))?\s*$'
$finPattern   = '^#@FIN (\d+)\|(.+)$'

<#
.SYNOPSIS
    Texte de fin de version pour le jalon N.
#>
function Get-EndBlock {
    param([int] $N, [string] $Description)

    $detail = if ($N -lt 12) { "TEST TERMINÉ : aucune application n'a été arrêtée." }
              elseif ($N -eq 12) { "TEST TERMINÉ : les applications sélectionnées sont arrêtées et le RESTENT. Le lanceur de test doit restaurer leur état." }
              else { "TEST TERMINÉ : les applications ont retrouvé leur état initial." }

    $indent = "    "
    if ($N -ge 12) { $indent = "        " }

    return @(
        "$indent# ---- Fin de la version du jalon $N (générée par Build-JalonVersions.ps1) ----",
        "${indent}Write-Log -Message `"JALON $N ATTEINT : $Description.`" -Level `"ATTENTION`"",
        "${indent}Write-Log -Message `"$detail`" -Level `"ATTENTION`"",
        "${indent}exit 0"
    )
}

<#
.SYNOPSIS
    Construit la version du jalon N.
.OUTPUTS
    Objet { Lines ; Added ; Removed ; EndCount }.
    Added / Removed : lignes dont la région la plus interne commence au
    jalon N / se termine au jalon N-1 (pour CHANGEMENTS.md).
#>
function Build-Version {
    param([int] $N)

    $stack   = New-Object System.Collections.Generic.List[object]
    $lines   = New-Object System.Collections.Generic.List[string]
    $added   = New-Object System.Collections.Generic.List[object]
    $removed = New-Object System.Collections.Generic.List[object]
    $endCount = 0
    $lineNumber = 0

    foreach ($line in $templateLines) {
        $lineNumber++

        if ($line -match $openPattern) {
            $from = [int] $Matches[1]
            $to   = if ($Matches[2]) { [int] $Matches[2] } else { 999 }
            $stack.Add([pscustomobject] @{ From = $from; To = $to; Tag = $line.Substring(3).Trim(); Line = $lineNumber })
            continue
        }

        if ($line -match $closePattern) {
            if ($stack.Count -eq 0) { throw "Balise fermante sans ouverture, ligne $lineNumber : $line" }
            $top = $stack[$stack.Count - 1]
            if ($top.Tag -ne $line.Substring(3).Trim()) { throw "Balises mal imbriquées, ligne $lineNumber : $line (ouverte : $($top.Tag) ligne $($top.Line))" }
            $stack.RemoveAt($stack.Count - 1)
            continue
        }

        $kept = $true
        foreach ($region in $stack) {
            if ($N -lt $region.From -or $N -gt $region.To) { $kept = $false }
        }

        if ($line -match $finPattern) {
            if ($kept -and [int] $Matches[1] -eq $N) {
                foreach ($endLine in (Get-EndBlock -N $N -Description $Matches[2])) { $lines.Add($endLine) }
                $endCount++
            }
            continue
        }

        $innermost = if ($stack.Count -gt 0) { $stack[$stack.Count - 1] } else { $null }

        if ($kept) {
            $lines.Add($line)

            if ($null -ne $innermost -and $innermost.From -eq $N) {
                $added.Add([pscustomobject] @{ Index = $lineNumber; Text = $line })
            }
        }
        elseif ($null -ne $innermost -and $innermost.To -eq ($N - 1)) {
            # Numéro de ligne du modèle : regroupe les lignes retirées consécutives.
            $removed.Add([pscustomobject] @{ Index = $lineNumber; Text = $line })
        }
    }

    if ($stack.Count -ne 0) {
        throw "Balise non fermée : $($stack[$stack.Count - 1].Tag) (ligne $($stack[$stack.Count - 1].Line))"
    }

    # Retire les bandeaux de section devenus vides, puis les lignes vides en double.
    $clean = New-Object System.Collections.Generic.List[string]
    $banner = '^# =+$'
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match $banner -and ($i + 2) -lt $lines.Count -and $lines[$i + 2] -match $banner -and $lines[$i + 1] -match '^# \S') {
            $next = $i + 3
            while ($next -lt $lines.Count -and $lines[$next].Trim() -eq "") { $next++ }
            if ($next -lt $lines.Count -and $lines[$next] -match $banner -and ($next + 2) -lt $lines.Count -and $lines[$next + 2] -match $banner) {
                $i = $next - 1
                continue
            }
        }
        if ($lines[$i].Trim() -eq "" -and $clean.Count -gt 0 -and $clean[$clean.Count - 1].Trim() -eq "") { continue }
        $clean.Add($lines[$i])
    }

    return [pscustomobject] @{
        Lines    = $clean
        Added    = $added
        Removed  = $removed
        EndCount = $endCount
    }
}

<#
.SYNOPSIS
    Regroupe des lignes consécutives en blocs titrés pour CHANGEMENTS.md.
#>
function Format-Blocks {
    param([object[]] $Items)

    $blocks = @()
    $current = $null
    $previousIndex = -10

    foreach ($item in $Items) {
        if ($null -eq $current -or $item.Index -ne $previousIndex + 1) {
            if ($null -ne $current) { $blocks += , $current }
            $current = New-Object System.Collections.Generic.List[string]
        }
        $current.Add($item.Text)
        $previousIndex = $item.Index
    }
    if ($null -ne $current) { $blocks += , $current }

    $output = New-Object System.Collections.Generic.List[string]
    foreach ($block in $blocks) {
        $text = ($block -join "`n").Trim("`n")
        if ($text.Trim() -eq "") { continue }

        $title = "Programme principal / configuration"
        $function = [regex]::Match($text, '(?m)^function ([\w-]+)')
        if ($function.Success) { $title = "Fonction $($function.Groups[1].Value)" }
        elseif ($text -match '(?m)^\$\w+ = ') { $title = "Configuration / variables" }
        elseif ($text -match 'Write-Step "\[(J\d+)\]') { $title = "Programme principal - étape $($Matches[1])" }

        $output.Add("### $title")
        $output.Add("")
        $output.Add('```powershell')
        $output.Add($text)
        $output.Add('```')
        $output.Add("")
    }

    return $output
}

function Write-TextFile {
    param([string] $Path, [string[]] $Lines)
    [IO.File]::WriteAllText($Path, (($Lines -join "`r`n") + "`r`n"), $utf8Bom)
}

function Test-Syntax {
    param([string] $Text, [string] $Name)
    $tokens = $null; $errors = $null
    [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref] $tokens, [ref] $errors) | Out-Null
    if ($errors.Count -gt 0) {
        throw "Version $Name invalide : ligne $($errors[0].Extent.StartLineNumber) : $($errors[0].Message)"
    }
}

# ------------------------------------------------------------------
# Génération
# ------------------------------------------------------------------

$production = Build-Version -N 19
$productionText = $production.Lines -join "`n"
Test-Syntax -Text $productionText -Name "production"
Write-TextFile -Path (Join-Path $Racine "download_deploy.ps1") -Lines $production.Lines
Write-Host "Script de production : $($production.Lines.Count) lignes" -ForegroundColor Green

$previousCount = 0

for ($n = 0; $n -le 19; $n++) {
    $version = Build-Version -N $n
    $text = $version.Lines -join "`n"

    Test-Syntax -Text $text -Name "jalon $n"

    if ($n -le 14 -and $version.EndCount -ne 1) {
        throw "Jalon $n : $($version.EndCount) fin(s) de version trouvée(s), 1 attendue."
    }
    if ($n -ge 15 -and $text -ne $productionText) {
        throw "Jalon $n : la version devrait être identique au script de production."
    }

    $jalonDirs = @(Get-ChildItem -LiteralPath $Racine -Directory -Filter "jalon_$($n)_*")
    if ($jalonDirs.Count -ne 1) { throw "Dossier du jalon $n introuvable ou ambigu." }

    $scenarios = @(Get-ChildItem -LiteralPath $jalonDirs[0].FullName -Directory -Filter "t_*")
    foreach ($scenario in $scenarios) {
        Write-TextFile -Path (Join-Path $scenario.FullName "download_deploy.ps1") -Lines $version.Lines
    }

    # CHANGEMENTS.md
    $doc = New-Object System.Collections.Generic.List[string]
    $doc.Add("# Jalon $n - code ajouté")
    $doc.Add("")
    $doc.Add("Fichier généré par ``_tools\Build-JalonVersions.ps1``. Ne pas modifier.")
    $doc.Add("")
    $doc.Add("| | |")
    $doc.Add("|---|---|")
    $doc.Add("| Lignes de la version du jalon $n | $($version.Lines.Count) |")
    $doc.Add("| Lignes de la version précédente | $previousCount |")
    $doc.Add("| Lignes ajoutées par ce jalon | $($version.Added.Count) |")
    $doc.Add("| Lignes retirées par ce jalon | $($version.Removed.Count) |")
    $doc.Add("")

    if ($n -le 14) {
        $doc.Add("La version se termine par le bloc « JALON $n ATTEINT / TEST TERMINÉ » (non repris ci-dessous).")
    }
    else {
        $doc.Add("Version identique au script de production.")
    }
    $doc.Add("")

    if ($version.Added.Count -gt 0) {
        $doc.Add("## Ajouté")
        $doc.Add("")
        foreach ($l in (Format-Blocks -Items $version.Added)) { $doc.Add($l) }
    }
    else {
        $doc.Add("Aucun code ajouté : ce jalon teste le code des jalons précédents.")
        $doc.Add("")
    }

    if ($version.Removed.Count -gt 0) {
        $doc.Add("## Retiré")
        $doc.Add("")
        foreach ($l in (Format-Blocks -Items $version.Removed)) { $doc.Add($l) }
    }

    Write-TextFile -Path (Join-Path $jalonDirs[0].FullName "CHANGEMENTS.md") -Lines $doc

    Write-Host ("Jalon {0,2} : {1,5} lignes (+{2}, -{3}) -> {4} scénario(s)" -f $n, $version.Lines.Count, $version.Added.Count, $version.Removed.Count, $scenarios.Count)
    $previousCount = $version.Lines.Count
}

Write-Host "Versions générées et vérifiées." -ForegroundColor Green
