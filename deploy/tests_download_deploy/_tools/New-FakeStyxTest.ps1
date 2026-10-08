#requires -Version 5.1

<#
.SYNOPSIS
    Installe des binaires FACTICES et des services Windows de TEST dans
    l'environnement réel de test (RacineReelle, par défaut D:\Styx-Test).

.DESCRIPTION
    Remplace temporairement les vrais binaires Styx pour les tests réels :
    on utilisera les vrais quand ils seront vraiment nécessaires.

    Le binaire factice ne fait RIEN :
      - lancé à la main ou par un test (processus normal) : il attend
        indéfiniment, comme une application qui tourne ;
      - lancé par Windows en tant que service : il répond correctement au
        gestionnaire de services (démarrer / arrêter), sans rien faire
        d'autre.

    Il est compilé une fois sur cette machine (aucun téléchargement), puis
    copié sous les noms lus dans _common\test-config.psd1 :

        <RacineReelle>\taskflow\<ExecutableTaskflow>
        <RacineReelle>\HpcLite\agent\<ExecutableAgent>
        <RacineReelle>\HpcLite\runner\<ExecutableRunner>       (pas de service)
        <RacineReelle>\HpcLite\scheduler\<ExecutableScheduler>

    Puis il crée (si besoin) les trois services de TEST nommés par
    ServiceTaskflow, ServiceAgent et ServiceScheduler, en démarrage manuel,
    pointant vers ces binaires. Chaque service est démarré puis arrêté une
    fois pour vérifier qu'il fonctionne ; il est laissé ARRÊTÉ.

    SÉCURITÉ : le script ne touche JAMAIS à un service existant qui pointe
    hors de RacineReelle (ex. les services de production). Dans ce cas il
    s'arrête et demande de choisir d'autres noms dans test-config.psd1,
    par exemple « TaskFlow.Runner.Test ».

    Le script peut être relancé sans risque (il remet les choses en place).

.PARAMETER ConfigPath
    Chemin de test-config.psd1. Par défaut : ..\_common\test-config.psd1
    par rapport à ce script (à placer dans _tools).

.EXAMPLE
    .\_tools\New-FakeStyxTest.ps1
#>

[CmdletBinding()]
param(
    [string] $ConfigPath = (Join-Path $PSScriptRoot "..\_common\test-config.psd1")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ------------------------------------------------------------
# 1. Contrôles préalables
# ------------------------------------------------------------

# Créer des services Windows exige les droits administrateur.
$principal = New-Object Security.Principal.WindowsPrincipal ([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Ce script doit être lancé depuis une console administrateur."
}

if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    throw "test-config.psd1 introuvable : $ConfigPath"
}

$config = Import-PowerShellDataFile -Path $ConfigPath
$root   = [IO.Path]::GetFullPath($config.RacineReelle).TrimEnd("\")
$prod   = [IO.Path]::GetFullPath($config.RacineProduction).TrimEnd("\")

# Garde-fou : jamais dans la racine de production.
if ($root.Equals($prod, [StringComparison]::OrdinalIgnoreCase)) {
    throw "RacineReelle et RacineProduction désignent le même dossier ($root). Arrêt."
}

# Les quatre composants. Le Runner n'a pas de service (n instances).
$components = @(
    @{ Nom = "Taskflow";          Dossier = "taskflow";          Exe = $config.ExecutableTaskflow;  Service = $config.ServiceTaskflow  }
    @{ Nom = "HpcLite Agent";     Dossier = "HpcLite\agent";     Exe = $config.ExecutableAgent;     Service = $config.ServiceAgent     }
    @{ Nom = "HpcLite Runner";    Dossier = "HpcLite\runner";    Exe = $config.ExecutableRunner;    Service = $null                    }
    @{ Nom = "HpcLite Scheduler"; Dossier = "HpcLite\scheduler"; Exe = $config.ExecutableScheduler; Service = $config.ServiceScheduler }
)

foreach ($c in $components) {
    $c.Chemin = Join-Path (Join-Path $root $c.Dossier) $c.Exe
}

# Un service existant qui pointe ailleurs (ex. la production) n'est jamais
# modifié : on vérifie TOUT avant de commencer, pour ne rien faire à moitié.
foreach ($c in $components | Where-Object { $_.Service }) {
    $cim = Get-CimInstance -ClassName Win32_Service -Filter "Name = '$($c.Service.Replace("'", "''"))'"

    if ($null -ne $cim) {
        $pathName = $cim.PathName.Trim('"', ' ')

        if (-not $pathName.StartsWith($root + "\", [StringComparison]::OrdinalIgnoreCase)) {
            throw @"
Le service '$($c.Service)' existe déjà et exécute un binaire hors de $root :
    $($cim.PathName)
C'est probablement un service de production : il n'est pas modifié.
Choisis des noms de services de TEST dans test-config.psd1, par exemple :
    ServiceTaskflow  = "TaskFlow.Runner.Test"
    ServiceAgent     = "HpcLite.Agent.Test"
    ServiceScheduler = "HpcLite.Scheduler.Test"
puis relance ce script.
"@
        }
    }
}

Write-Host "Racine de test : $root" -ForegroundColor Cyan

# ------------------------------------------------------------
# 2. Compilation du binaire factice (une seule fois)
# ------------------------------------------------------------
# UserInteractive vaut false uniquement quand Windows lance le programme
# en tant que service : on répond alors au gestionnaire de services.
# Sinon (console, test), on attend indéfiniment.

$source = @"
using System;
using System.ServiceProcess;
using System.Threading;

public class FauxStyx : ServiceBase
{
    public FauxStyx()
    {
        // Pour un service seul dans son processus, Windows ignore ce nom.
        ServiceName = "FauxStyx";
        CanStop = true;
    }

    public static void Main()
    {
        if (Environment.UserInteractive)
        {
            Thread.Sleep(Timeout.Infinite);
        }
        else
        {
            ServiceBase.Run(new FauxStyx());
        }
    }

    protected override void OnStart(string[] args) { }
    protected override void OnStop() { }
}
"@

$compiled = Join-Path $env:TEMP ("FauxStyx-" + [guid]::NewGuid().ToString("N") + ".exe")
Add-Type -TypeDefinition $source -OutputAssembly $compiled -OutputType ConsoleApplication -ReferencedAssemblies "System.ServiceProcess"
Write-Host "Binaire factice compilé." -ForegroundColor Green

try {
    # --------------------------------------------------------
    # 3. Dossiers et binaires
    # --------------------------------------------------------
    # Le dossier api doit exister (contrôle de l'environnement réel). Il
    # n'est pas rempli : l'API est servie par le pool IIS, pas par un exe.
    New-Item -Path (Join-Path $root "api") -ItemType Directory -Force | Out-Null

    foreach ($c in $components) {
        # Un service de test en cours d'exécution verrouille son exe :
        # on l'arrête avant de le remplacer.
        if ($c.Service) {
            $svc = Get-Service -Name $c.Service -ErrorAction SilentlyContinue
            if ($null -ne $svc -and $svc.Status -ne "Stopped") {
                Stop-Service -Name $c.Service -Force
                $svc.WaitForStatus("Stopped", [TimeSpan]::FromSeconds(30))
            }
        }

        # Un Runner factice lancé à la main verrouillerait aussi son exe.
        Get-Process -ErrorAction SilentlyContinue |
            Where-Object { $_.Path -and $_.Path.Equals($c.Chemin, [StringComparison]::OrdinalIgnoreCase) } |
            Stop-Process -Force

        New-Item -Path (Split-Path -Parent $c.Chemin) -ItemType Directory -Force | Out-Null
        Copy-Item -LiteralPath $compiled -Destination $c.Chemin -Force
        Write-Host "Binaire factice : $($c.Chemin)" -ForegroundColor Green
    }

    # --------------------------------------------------------
    # 4. Services de test
    # --------------------------------------------------------
    foreach ($c in $components | Where-Object { $_.Service }) {
        $binPath = '"' + $c.Chemin + '"'
        $cim = Get-CimInstance -ClassName Win32_Service -Filter "Name = '$($c.Service.Replace("'", "''"))'"

        if ($null -eq $cim) {
            New-Service -Name $c.Service -BinaryPathName $binPath -DisplayName "$($c.Nom) (TEST)" -StartupType Manual | Out-Null
            Write-Host "Service créé : $($c.Service)" -ForegroundColor Green
        }
        elseif ($cim.PathName.Trim('"', ' ') -ne $c.Chemin) {
            # Service de test existant (sous $root) mais exe différent.
            & sc.exe config $c.Service binPath= $binPath | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "sc.exe config a échoué pour '$($c.Service)'." }
            Write-Host "Service mis à jour : $($c.Service)" -ForegroundColor Green
        }
        else {
            Write-Host "Service déjà en place : $($c.Service)" -ForegroundColor Green
        }

        # Vérification : démarrer puis arrêter une fois.
        Start-Service -Name $c.Service
        (Get-Service -Name $c.Service).WaitForStatus("Running", [TimeSpan]::FromSeconds(30))
        Stop-Service -Name $c.Service -Force
        (Get-Service -Name $c.Service).WaitForStatus("Stopped", [TimeSpan]::FromSeconds(30))
        Write-Host "  démarrage / arrêt OK (laissé arrêté)" -ForegroundColor Green
    }
}
finally {
    Remove-Item -LiteralPath $compiled -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "Environnement de test prêt (binaires factices)." -ForegroundColor Cyan
Write-Host "Rappel : le pool IIS '$($config.PoolIis)' doit aussi exister pour les tests réels." -ForegroundColor Yellow
