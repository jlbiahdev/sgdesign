$racine = "C:\chemin\vers\01_POC"   # à adapter
$utf8Bom = New-Object System.Text.UTF8Encoding $true

Get-ChildItem -Path $racine -Recurse -Include *.ps1, *.psm1, *.psd1 | ForEach-Object {
    $bytes = [IO.File]::ReadAllBytes($_.FullName)
    $text  = [Text.Encoding]::UTF8.GetString($bytes).TrimStart([char]0xFEFF, [char]0xFFFD)

    $hasBom   = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $corrupt  = [Text.Encoding]::UTF8.GetString($bytes).TrimStart([char]0xFEFF).StartsWith([char]0xFFFD)

    if ($corrupt -or -not $hasBom) {
        [IO.File]::WriteAllText($_.FullName, $text, $utf8Bom)
        "Réparé : $($_.FullName)"
    }
}