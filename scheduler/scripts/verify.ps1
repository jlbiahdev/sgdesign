<#
.SYNOPSIS
    Vérifie que HpcLite Scheduler et Agent sont opérationnels.

.PARAMETER SchedulerHost
    Hôte du Scheduler à tester. Défaut : localhost

.PARAMETER SchedulerPort
    Port Kestrel du Scheduler. Défaut : 5100

.PARAMETER AgentHost
    Hôte de l'Agent à tester (optionnel — omis si non spécifié).

.PARAMETER AgentPort
    Port Kestrel de l'Agent. Défaut : 5200

.EXAMPLE
    # Vérifier le Scheduler local
    .\verify.ps1

.EXAMPLE
    # Vérifier Scheduler distant + Agent
    .\verify.ps1 -SchedulerHost "HEADNODE-01" -AgentHost "COMPUTE-01"

.EXAMPLE
    # Vérifier Scheduler distant uniquement
    .\verify.ps1 -SchedulerHost "HEADNODE-01"

.EXAMPLE
    # Vérifier avec ports non standard
    .\verify.ps1 -SchedulerHost "HEADNODE-01" -SchedulerPort 6100 -AgentHost "COMPUTE-01" -AgentPort 6200
#>
param(
    [string] $SchedulerHost = "localhost",
    [int]    $SchedulerPort = 5100,
    [string] $AgentHost     = "",
    [int]    $AgentPort     = 5200
)

$pass = 0
$fail = 0

function Write-Pass([string]$msg) { Write-Host "  ✓ $msg" -ForegroundColor Green;  $script:pass++ }
function Write-Fail([string]$msg) { Write-Host "  ✗ $msg" -ForegroundColor Red;    $script:fail++ }
function Write-Section([string]$title) { Write-Host "`n── $title" -ForegroundColor Cyan }

# ── Windows Services ──────────────────────────────────────────────────────────

Write-Section "Windows Services"

$schedulerSvc = Get-Service "HpcLite Scheduler" -ErrorAction SilentlyContinue
if ($schedulerSvc -and $schedulerSvc.Status -eq "Running") {
    Write-Pass "HpcLite Scheduler : Running"
} elseif ($schedulerSvc) {
    Write-Fail "HpcLite Scheduler : $($schedulerSvc.Status)"
} else {
    Write-Host "  ~ HpcLite Scheduler : non installé sur cette machine" -ForegroundColor DarkGray
}

$agentSvc = Get-Service "HpcLite Agent" -ErrorAction SilentlyContinue
if ($agentSvc -and $agentSvc.Status -eq "Running") {
    Write-Pass "HpcLite Agent : Running"
} elseif ($agentSvc) {
    Write-Fail "HpcLite Agent : $($agentSvc.Status)"
} else {
    Write-Host "  ~ HpcLite Agent : non installé sur cette machine" -ForegroundColor DarkGray
}

# ── GET /runners/ping ─────────────────────────────────────────────────────────

Write-Section "GET /runners/ping  ($SchedulerHost`:$SchedulerPort)"

try {
    $resp    = Invoke-RestMethod -Uri "http://${SchedulerHost}:${SchedulerPort}/runners/ping" -Method GET -TimeoutSec 5
    $runners = $resp.runners

    if ($runners.Count -eq 0) {
        Write-Fail "Aucun runner en DB — avez-vous exécuté setup-db.ps1 ?"
    } else {
        Write-Pass "$($runners.Count) runner(s) en DB"
        foreach ($r in $runners) {
            $aliveStr = if ($null -eq $r.is_alive) { "idle" }
                        elseif ($r.is_alive)        { "alive" }
                        else                         { "STALE" }
            $color    = if ($aliveStr -eq "STALE") { "Yellow" } else { "Gray" }
            Write-Host "     $($r.name) @ $($r.host)  [$aliveStr]" -ForegroundColor $color
        }
    }
} catch {
    Write-Fail "GET /runners/ping échoué : $_"
}

# ── POST /run sur l'Agent ─────────────────────────────────────────────────────

if ($AgentHost) {
    Write-Section "POST /run (Agent $AgentHost`:$AgentPort) — dry run"

    $body = @{
        runner_id     = 0
        exe_path      = "C:\Windows\System32\cmd.exe"
        settings_path = "C:\nonexistent\settings.json"
    } | ConvertTo-Json

    try {
        # On s'attend à un 202 ou une erreur process — pas de timeout réseau
        $r = Invoke-WebRequest `
            -Uri         "http://${AgentHost}:${AgentPort}/run" `
            -Method      POST `
            -Body        $body `
            -ContentType "application/json" `
            -TimeoutSec  5 `
            -ErrorAction SilentlyContinue

        if ($r.StatusCode -in 200,202) {
            Write-Pass "Agent répond sur :$AgentPort (HTTP $($r.StatusCode))"
        } else {
            Write-Fail "Agent a répondu HTTP $($r.StatusCode)"
        }
    } catch {
        Write-Fail "Agent injoignable sur ${AgentHost}:${AgentPort} : $_"
    }
}

# ── Logs ──────────────────────────────────────────────────────────────────────

Write-Section "Logs récents"

$logDirs = @(
    "C:\apps\HpcLite.Scheduler\logs",
    "C:\apps\HpcLite.Agent\logs",
    "C:\apps\HpcLite.Runner\logs"
)
foreach ($dir in $logDirs) {
    if (Test-Path $dir) {
        $latest = Get-ChildItem $dir -Filter "*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($latest) {
            Write-Host "  $dir" -ForegroundColor DarkGray
            Get-Content $latest.FullName -Tail 5 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
        }
    }
}

# ── Résumé ────────────────────────────────────────────────────────────────────

Write-Host ""
if ($fail -eq 0) {
    Write-Host "✓ Tous les checks sont OK ($pass/$($pass+$fail))" -ForegroundColor Green
} else {
    Write-Host "⚠ $fail check(s) en échec, $pass OK" -ForegroundColor Yellow
}
Write-Host ""
