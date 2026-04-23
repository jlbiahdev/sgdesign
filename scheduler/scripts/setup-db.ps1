#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Exécute les migrations SQL et enregistre les nœuds Scheduler/Runner en DB.

.DESCRIPTION
    Étape 1 : CREATE TABLE schedulers, runners + ALTER TABLE model_job
    Étape 2 : INSERT des nœuds (idempotent via ON CONFLICT DO NOTHING)

    Requiert psql.exe dans le PATH ou -PsqlPath explicite.

.PARAMETER PgHost
    Hôte PostgreSQL. Défaut : localhost

.PARAMETER PgPort
    Port PostgreSQL. Défaut : 5432

.PARAMETER PgDatabase
    Nom de la base. Défaut : hpclite

.PARAMETER PgUser
    Utilisateur PostgreSQL. Défaut : postgres

.PARAMETER PgPassword
    Mot de passe PostgreSQL.

.PARAMETER SolutionRoot
    Racine de la solution (pour localiser migrations.sql). Défaut : répertoire parent de ce script.

.PARAMETER PsqlPath
    Chemin vers psql.exe si non dans le PATH. Défaut : psql

.PARAMETER SchedulerHost
    Nom de machine du headnode à enregistrer (résultat de hostname sur cette machine).

.PARAMETER SchedulerName
    Nom logique du Scheduler. Défaut : Scheduler-<SchedulerHost>

.PARAMETER Runners
    Tableau de hashtables décrivant les runners.
    Chaque entrée : @{ Name="Runner-01"; Host="COMPUTE-01"; ExePath="C:\apps\HpcLite.Runner\HpcLite.Runner.exe" }

.EXAMPLE
    # Minimal — migrations seules, sans nœuds
    .\setup-db.ps1 -PgPassword "secret" -SchedulerHost "HEADNODE-01"

.EXAMPLE
    # Complet avec deux compute nodes
    .\setup-db.ps1 `
        -PgHost      "db-server" `
        -PgDatabase  "hpclite" `
        -PgUser      "postgres" `
        -PgPassword  "secret" `
        -SchedulerHost "HEADNODE-01" `
        -Runners @(
            @{ Name="Runner-01"; Host="COMPUTE-01"; ExePath="C:\apps\HpcLite.Runner\HpcLite.Runner.exe" },
            @{ Name="Runner-02"; Host="COMPUTE-02"; ExePath="C:\apps\HpcLite.Runner\HpcLite.Runner.exe" }
        )

.EXAMPLE
    # Ajouter un troisième Runner sans retoucher les existants
    .\setup-db.ps1 `
        -PgPassword "secret" `
        -SchedulerHost "HEADNODE-01" `
        -Runners @(
            @{ Name="Runner-03"; Host="COMPUTE-03"; ExePath="C:\apps\HpcLite.Runner\HpcLite.Runner.exe" }
        )
#>
param(
    [string]  $PgHost        = "localhost",
    [int]     $PgPort        = 5432,
    [string]  $PgDatabase    = "hpclite",
    [string]  $PgUser        = "postgres",
    [Parameter(Mandatory)]
    [string]  $PgPassword,
    [string]  $SolutionRoot  = (Resolve-Path "$PSScriptRoot\.."),
    [string]  $PsqlPath      = "psql",
    [Parameter(Mandatory)]
    [string]  $SchedulerHost,
    [string]  $SchedulerName = "",
    [hashtable[]] $Runners   = @()
)

if (-not $SchedulerName) { $SchedulerName = "Scheduler-$SchedulerHost" }

$env:PGPASSWORD = $PgPassword
$conn = "-h $PgHost -p $PgPort -U $PgUser -d $PgDatabase"

function Write-Step([string]$msg) {
    Write-Host "`n[$([datetime]::Now.ToString('HH:mm:ss'))] $msg" -ForegroundColor Cyan
}

function Invoke-Psql([string]$sql) {
    $tmp = [System.IO.Path]::GetTempFileName() + ".sql"
    Set-Content -Path $tmp -Value $sql -Encoding UTF8
    & $PsqlPath -h $PgHost -p $PgPort -U $PgUser -d $PgDatabase -f $tmp -v ON_ERROR_STOP=1
    Remove-Item $tmp -ErrorAction SilentlyContinue
    if ($LASTEXITCODE -ne 0) { Write-Host "ERREUR psql (code $LASTEXITCODE)" -ForegroundColor Red; exit $LASTEXITCODE }
}

# ── vérifier psql ─────────────────────────────────────────────────────────────

Write-Step "Vérification de psql..."
$null = & $PsqlPath --version 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERREUR : psql introuvable. Installez PostgreSQL client tools ou passez -PsqlPath." -ForegroundColor Red
    exit 1
}

# ── migrations ────────────────────────────────────────────────────────────────

Write-Step "Exécution des migrations..."
$migrationFile = Join-Path $SolutionRoot "Database\migrations.sql"
if (-not (Test-Path $migrationFile)) {
    Write-Host "ERREUR : migrations.sql introuvable : $migrationFile" -ForegroundColor Red
    exit 1
}
& $PsqlPath -h $PgHost -p $PgPort -U $PgUser -d $PgDatabase -f $migrationFile -v ON_ERROR_STOP=1
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host "  Migrations OK" -ForegroundColor Green

# ── enregistrement Scheduler ──────────────────────────────────────────────────

Write-Step "Enregistrement du Scheduler '$SchedulerName' (host=$SchedulerHost)..."
Invoke-Psql @"
INSERT INTO schedulers (name, host)
VALUES ('$SchedulerName', '$SchedulerHost')
ON CONFLICT (host) DO UPDATE SET name = EXCLUDED.name;
"@
Write-Host "  Scheduler OK" -ForegroundColor Green

# ── enregistrement Runners ────────────────────────────────────────────────────

if ($Runners.Count -eq 0) {
    Write-Host "`n  Aucun runner spécifié — ignoré." -ForegroundColor DarkGray
} else {
    Write-Step "Enregistrement de $($Runners.Count) Runner(s)..."
    foreach ($r in $Runners) {
        $exeEscaped = $r.ExePath -replace "'", "''"
        Invoke-Psql @"
INSERT INTO runners (name, host, exe_path)
VALUES ('$($r.Name)', '$($r.Host)', '$exeEscaped')
ON CONFLICT (name) DO UPDATE
    SET host     = EXCLUDED.host,
        exe_path = EXCLUDED.exe_path;
"@
        Write-Host "  $($r.Name) @ $($r.Host) OK" -ForegroundColor Green
    }
}

Write-Host "`n✓ Setup DB terminé.`n" -ForegroundColor Green
