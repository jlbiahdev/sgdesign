#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Installe ou met à jour HpcLite Scheduler en tant que Windows Service.

.PARAMETER DeployPath
    Répertoire de destination du service. Défaut : C:\apps\HpcLite.Scheduler

.PARAMETER SolutionRoot
    Racine de la solution .NET. Défaut : répertoire parent de ce script.

.EXAMPLE
    .\install-scheduler.ps1
    .\install-scheduler.ps1 -DeployPath "D:\services\HpcLite.Scheduler"
#>
param(
    [string]$DeployPath   = "C:\apps\HpcLite.Scheduler",
    [string]$SolutionRoot = (Resolve-Path "$PSScriptRoot\..")
)

$ServiceName = "HpcLite Scheduler"
$ExeName     = "HpcLite.Scheduler.exe"
$Project     = Join-Path $SolutionRoot "HpcLite.Scheduler"

# ── helpers ──────────────────────────────────────────────────────────────────

function Write-Step([string]$msg) {
    Write-Host "`n[$([datetime]::Now.ToString('HH:mm:ss'))] $msg" -ForegroundColor Cyan
}

function Invoke-Or-Fail([scriptblock]$block) {
    & $block
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
        Write-Host "ECHEC (code $LASTEXITCODE)" -ForegroundColor Red
        exit $LASTEXITCODE
    }
}

# ── vérifications préalables ─────────────────────────────────────────────────

Write-Step "Vérification de .NET 8..."
$dotnetVersion = dotnet --version 2>$null
if (-not $dotnetVersion -or -not $dotnetVersion.StartsWith("8.")) {
    Write-Host "ERREUR : .NET 8 requis. Version détectée : $dotnetVersion" -ForegroundColor Red
    exit 1
}
Write-Host "  .NET $dotnetVersion OK"

if (-not (Test-Path $Project)) {
    Write-Host "ERREUR : Projet introuvable : $Project" -ForegroundColor Red
    exit 1
}

# ── arrêt du service existant ─────────────────────────────────────────────────

$existing = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Step "Arrêt du service existant '$ServiceName'..."
    if ($existing.Status -eq "Running") {
        Stop-Service -Name $ServiceName -Force
        Start-Sleep -Seconds 3
    }
}

# ── publication ───────────────────────────────────────────────────────────────

Write-Step "Publication du projet vers '$DeployPath'..."
Invoke-Or-Fail {
    dotnet publish $Project `
        --configuration Release `
        --output $DeployPath `
        --runtime win-x64 `
        --self-contained false `
        /p:PublishSingleFile=false
}
Write-Host "  Publication OK"

# ── création / mise à jour du service ────────────────────────────────────────

$ExePath = Join-Path $DeployPath $ExeName

if ($existing) {
    Write-Step "Service existant détecté — mise à jour du binPath..."
    sc.exe config $ServiceName binPath= "`"$ExePath`""
} else {
    Write-Step "Création du service '$ServiceName'..."
    sc.exe create $ServiceName `
        binPath= "`"$ExePath`"" `
        start= auto `
        DisplayName= $ServiceName
    sc.exe description $ServiceName "HpcLite Scheduler — headnode HPC (.NET 8)"
}

# ── droits sur le dossier de logs ─────────────────────────────────────────────

$LogDir = Join-Path $DeployPath "logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$Acl  = Get-Acl $DeployPath
$Rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
    "NETWORK SERVICE", "Modify", "ContainerInherit,ObjectInherit", "None", "Allow"
)
$Acl.SetAccessRule($Rule)
Set-Acl $DeployPath $Acl
Write-Host "  Droits NETWORK SERVICE sur '$DeployPath' OK"

# ── démarrage ────────────────────────────────────────────────────────────────

Write-Step "Démarrage du service..."
Start-Service -Name $ServiceName
Start-Sleep -Seconds 2

$status = (Get-Service -Name $ServiceName).Status
if ($status -eq "Running") {
    Write-Host "`n✓ '$ServiceName' est Running." -ForegroundColor Green
} else {
    Write-Host "`n⚠ '$ServiceName' est en état : $status" -ForegroundColor Yellow
    Write-Host "  Consultez les logs : $LogDir" -ForegroundColor Yellow
}

Write-Host "`nLogs : $LogDir"
Write-Host "Ping : http://localhost:5100/runners/ping`n"
