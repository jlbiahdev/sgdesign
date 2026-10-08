Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$nupkg = [IO.Compression.ZipFile]::OpenRead("D:\Styx-Test-Packages\Styx.Publish.nupkg")
$entry = $nupkg.Entries | Where-Object FullName -like "*styx_publish.zip"
$inner = New-Object IO.Compression.ZipArchive($entry.Open())

# Dossiers des 2 premiers niveaux et tous les .exe
$inner.Entries |
    Where-Object { $_.FullName -match '\.exe$' -or ($_.FullName.TrimEnd('/') -split '/').Count -le 2 } |
    Select-Object FullName, Length | Format-Table -AutoSize

# Nombre de fichiers par dossier de 1er niveau
$inner.Entries | Where-Object { -not $_.FullName.EndsWith('/') } |
    Group-Object { ($_.FullName -split '/')[0] } | Select-Object Count, Name

$inner.Dispose(); $nupkg.Dispose()