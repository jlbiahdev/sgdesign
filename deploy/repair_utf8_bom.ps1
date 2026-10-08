#requires -Version 5.1

<#
.SYNOPSIS
    Restores the UTF-8 BOM on PowerShell files (.ps1, .psm1, .psd1).

.DESCRIPTION
    For each file found under the given path(s):
      - BOM present and correct          : file left untouched;
      - BOM missing                      : BOM added;
      - BOM replaced by U+FFFD ("?")     : bad character removed, BOM added.

    Content is read as UTF-8 and rewritten as UTF-8 with BOM.
    Only the start of the file changes.

    This script is written in plain ASCII on purpose: it works even if it
    has itself lost its BOM.

.PARAMETER Path
    One or more files or folders. Folders are scanned recursively.

.EXAMPLE
    .\Repair-Bom.ps1 -Path D:\tests_scripts

.EXAMPLE
    .\Repair-Bom.ps1 -Path D:\tests_scripts\run_jalon.ps1, D:\tests_scripts\_commun
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string[]] $Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$utf8Bom    = New-Object System.Text.UTF8Encoding $true
$extensions = @(".ps1", ".psm1", ".psd1")

$files = foreach ($item in $Path) {
    if (-not (Test-Path -LiteralPath $item)) {
        throw "Path not found: $item"
    }

    $resolved = Get-Item -LiteralPath $item

    if ($resolved.PSIsContainer) {
        Get-ChildItem -LiteralPath $resolved.FullName -Recurse -File |
            Where-Object { $extensions -contains $_.Extension.ToLowerInvariant() }
    }
    else {
        $resolved
    }
}

$repaired = 0
$checked  = 0

foreach ($file in @($files)) {
    $checked++

    $bytes   = [IO.File]::ReadAllBytes($file.FullName)
    $text    = [Text.Encoding]::UTF8.GetString($bytes)
    $hasBom  = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $corrupt = $text.TrimStart([char] 0xFEFF).StartsWith([string] [char] 0xFFFD)

    if ($hasBom -and -not $corrupt) {
        continue
    }

    $clean = $text.TrimStart([char] 0xFEFF, [char] 0xFFFD)
    [IO.File]::WriteAllText($file.FullName, $clean, $utf8Bom)

    $reason = if ($corrupt) { "bad character removed, BOM added" } else { "BOM added" }
    Write-Host "Repaired ($reason): $($file.FullName)" -ForegroundColor Yellow
    $repaired++
}

Write-Host "Files checked: $checked - repaired: $repaired" -ForegroundColor Green
