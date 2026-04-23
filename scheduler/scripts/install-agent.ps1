#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Installe ou met à jour HpcLite Agent en tant que Windows Service sur un compute node.

.PARAMETER DeployPath
    Répertoire de destination du service. Défaut : C:\apps\HpcLite.Agent

.PARAMETER RunnerDeployPath
    Répertoire où HpcLite.Runner.exe sera déposé. Défaut : C:\apps\HpcLite.Runner

.PARAMETER SolutionRoot
    Racine de la solution .NET. Défaut : répertoire parent de ce script.

.EXAMPLE
    .\install-agent.ps1
    .\install-agent.ps1 -DeployPath "D:\services\HpcLite.Agent"
#>
param(
    [string]$DeployPath       = "C:\apps\HpcLite.Agent",
    [string]$RunnerDeployPath = "C:\apps\HpcLite.Runner",
    [string]$SolutionRoot     = (Resolve-Path "$PSScriptRoot\..")
)

$ServiceName    = "HpcLite Agent"
$ExeName        = "HpcLite.Agent.exe"
$AgentProject   = Join-Path $SolutionRoot "HpcLite.Agent"
$RunnerProject  = Join-Path $SolutionRoot "HpcLite.Runner"

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

foreach ($p in @($AgentProject, $RunnerProject)) {
    if (-not (Test-Path $p)) {
        Write-Host "ERREUR : Projet introuvable : $p" -ForegroundColor Red
        exit 1
    }
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

# ── publication Agent ─────────────────────────────────────────────────────────

Write-Step "Publication de l'Agent vers '$DeployPath'..."
Invoke-Or-Fail {
    dotnet publish $AgentProject `
        --configuration Release `
        --output $DeployPath `
        --runtime win-x64 `
        --self-contained false
}
Write-Host "  Agent publié OK"

# ── publication Runner ────────────────────────────────────────────────────────

Write-Step "Publication du Runner vers '$RunnerDeployPath'..."
Invoke-Or-Fail {
    dotnet publish $RunnerProject `
        --configuration Release `
        --output $RunnerDeployPath `
        --runtime win-x64 `
        --self-contained false
}
Write-Host "  Runner publié OK"

# ── vérifier que runners.exe_path en DB correspond ───────────────────────────

$RunnerExe = Join-Path $RunnerDeployPath "HpcLite.Runner.exe"
Write-Host "`n  ⚠  Vérifiez que la colonne exe_path en DB correspond à :"
Write-Host "     $RunnerExe" -ForegroundColor Yellow
Write-Host "  SQL : UPDATE runners SET exe_path='$RunnerExe' WHERE host='$env:COMPUTERNAME';"

# ── création / mise à jour du service ────────────────────────────────────────

$ExePath = Join-Path $DeployPath $ExeName

if ($existing) {
    Write-Step "Mise à jour du binPath du service..."
    sc.exe config $ServiceName binPath= "`"$ExePath`""
} else {
    Write-Step "Création du service '$ServiceName'..."
    sc.exe create $ServiceName `
        binPath= "`"$ExePath`"" `
        start= auto `
        DisplayName= $ServiceName
    sc.exe description $ServiceName "HpcLite Agent — compute node HPC (.NET 8)"
}

# ── droits sur les dossiers de logs ──────────────────────────────────────────

foreach ($dir in @((Join-Path $DeployPath "logs"), (Join-Path $RunnerDeployPath "logs"))) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $Acl  = Get-Acl (Split-Path $dir)
    $Rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        "NETWORK SERVICE", "Modify", "ContainerInherit,ObjectInherit", "None", "Allow"
    )
    $Acl.SetAccessRule($Rule)
    Set-Acl (Split-Path $dir) $Acl
}
Write-Host "  Droits NETWORK SERVICE sur les dossiers logs OK"

# ── démarrage ────────────────────────────────────────────────────────────────

Write-Step "Démarrage du service..."
Start-Service -Name $ServiceName
Start-Sleep -Seconds 2

$status = (Get-Service -Name $ServiceName).Status
if ($status -eq "Running") {
    Write-Host "`n✓ '$ServiceName' est Running." -ForegroundColor Green
} else {
    Write-Host "`n⚠ '$ServiceName' est en état : $status" -ForegroundColor Yellow
}

Write-Host "`nAgent logs    : $(Join-Path $DeployPath 'logs')"
Write-Host "Runner logs   : $(Join-Path $RunnerDeployPath 'logs')"
Write-Host "Agent écoute  : http://localhost:5200/run`n"
