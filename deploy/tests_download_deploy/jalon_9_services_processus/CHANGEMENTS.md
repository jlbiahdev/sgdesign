# Jalon 9 - code ajouté

Fichier généré par `_tools\Build-JalonVersions.ps1`. Ne pas modifier.

| | |
|---|---|
| Lignes de la version du jalon 9 | 1397 |
| Lignes de la version précédente | 1149 |
| Lignes ajoutées par ce jalon | 234 |
| Lignes retirées par ce jalon | 0 |

La version se termine par le bloc « JALON 9 ATTEINT / TEST TERMINÉ » (non repris ci-dessous).

## Ajouté

### Configuration / variables

```powershell
# $true  : production. Taskflow, l'Agent et le Scheduler sont pilotés par
#          le gestionnaire de services (Stop-Service / Start-Service).
#          Tuer le processus d'un service déclencherait ses options de
#          récupération : il pourrait redémarrer pendant le déploiement.
# $false : réservé aux tests avec des exécutables factices ; arrêt brutal
#          et redémarrage par Start-Process.
$UseWindowsServices = $true

# Noms des services Windows (colonne « Nom du service » de services.msc).
# Attention : « TaskFlow.Runner » est le service de Taskflow (STP), à ne
# pas confondre avec les Runners HpcLite.
$TaskflowServiceName = "TaskFlow.Runner"
$HpcLiteAgentServiceName = "HpcLite.Agent"
$HpcLiteSchedulerServiceName = "HpcLite.Scheduler"
```

### Fonction Get-ProcessesByExecutablePath

```powershell
<#
.SYNOPSIS
    Renvoie les processus dont l'exécutable est exactement ce chemin.
.DESCRIPTION
    Win32_Process fournit le chemin complet : on n'arrête jamais par erreur
    une autre application portant le même nom ailleurs sur le disque.
#>
function Get-ProcessesByExecutablePath {
    param(
        [Parameter(Mandatory = $true)]
        [string] $ExecutablePath
    )

    $expectedPath = [IO.Path]::GetFullPath($ExecutablePath)

    $processes = @(
        Get-CimInstance -ClassName Win32_Process -ErrorAction Stop |
            Where-Object {
                -not [string]::IsNullOrWhiteSpace($_.ExecutablePath) -and
                $_.ExecutablePath.Equals($expectedPath, [StringComparison]::OrdinalIgnoreCase)
            }
    )

    return $processes
}
```

### Fonction Assert-SingleProcessMaximum

```powershell
<#
.SYNOPSIS
    Échoue si plus d'une instance est détectée (Taskflow, Agent, Scheduler).
.DESCRIPTION
    [AllowEmptyCollection()] est indispensable : sans lui, PowerShell refuse
    un tableau vide sur un paramètre obligatoire, et le script échouerait dès
    qu'une application est arrêtée.
#>
function Assert-SingleProcessMaximum {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]] $Processes,

        [Parameter(Mandatory = $true)]
        [string] $ComponentName
    )

    if ($Processes.Count -gt 1) {
        $processIds = $Processes.ProcessId -join ", "

        throw @"
Anomalie détectée pour $ComponentName.

Une seule instance au maximum est autorisée.
Nombre d'instances détectées : $($Processes.Count)
Identifiants des processus : $processIds

Aucun processus n'a été arrêté.
Le déploiement est annulé.
"@
    }
}
```

### Fonction Get-ServiceSafe

```powershell
<#
.SYNOPSIS
    Renvoie le service Windows, ou échoue clairement s'il n'existe pas.
#>
function Get-ServiceSafe {
    param(
        [Parameter(Mandatory = $true)] [string] $ServiceName,
        [Parameter(Mandatory = $true)] [string] $ComponentName
    )

    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue

    if ($null -eq $service) {
        throw @"
Le service Windows de $ComponentName est introuvable.

Nom du service :
$ServiceName

Vérifiez la configuration au début du script.
"@
    }

    return $service
}
```

### Fonction Assert-ServiceConfiguration

```powershell
<#
.SYNOPSIS
    Vérifie qu'un service existe ET exécute l'exécutable du dossier -d. (J9)
.DESCRIPTION
    Si le service lançait un exécutable situé ailleurs, remplacer les
    fichiers de -d n'aurait aucun effet sur l'application réelle : on
    s'arrête avant toute action.
#>
function Assert-ServiceConfiguration {
    param(
        [Parameter(Mandatory = $true)] [AllowEmptyString()] [string] $ServiceName,
        [Parameter(Mandatory = $true)] [string] $ComponentName,
        [Parameter(Mandatory = $true)] [string] $ExpectedExecutablePath
    )

    if ([string]::IsNullOrWhiteSpace($ServiceName)) {
        throw @"
Le nom du service Windows de $ComponentName n'est pas configuré.

Renseignez-le au début du script (section CONFIGURATION).
"@
    }

    Get-ServiceSafe -ServiceName $ServiceName -ComponentName $ComponentName | Out-Null

    $cimService = Get-CimInstance `
        -ClassName Win32_Service `
        -Filter "Name = '$($ServiceName.Replace("'", "''"))'" `
        -ErrorAction Stop

    # PathName : "D:\...\App.exe" --args   ou   D:\...\App.exe --args
    $pathName = $cimService.PathName.Trim()

    if ($pathName.StartsWith('"')) {
        $serviceExecutable = $pathName.Substring(1, $pathName.IndexOf('"', 1) - 1)
    }
    else {
        $exeIndex = $pathName.IndexOf(".exe", [StringComparison]::OrdinalIgnoreCase)
        $serviceExecutable = if ($exeIndex -ge 0) { $pathName.Substring(0, $exeIndex + 4) } else { $pathName }
    }

    $expected = [IO.Path]::GetFullPath($ExpectedExecutablePath)

    if (-not [IO.Path]::GetFullPath($serviceExecutable).Equals($expected, [StringComparison]::OrdinalIgnoreCase)) {
        throw @"
Le service $ComponentName ('$ServiceName') n'exécute pas l'exécutable attendu.

Exécutable du service :
$serviceExecutable

Exécutable attendu (dossier de déploiement) :
$expected

Vérifiez -d et les noms configurés au début du script.
"@
    }

    Write-Log -Message "Service $ComponentName ('$ServiceName') trouvé et cohérent avec la destination." -Level "OK"
}
```

### Fonction Test-SingleComponentRunning

```powershell
<#
.SYNOPSIS
    Indique si un composant à instance unique fonctionne actuellement.
.DESCRIPTION
    Production : état du service (Running). Mode test : présence d'un processus.
#>
function Test-SingleComponentRunning {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]] $Processes,

        [Parameter(Mandatory = $true)] [string] $ComponentName,
        [Parameter()] [string] $ServiceName
    )

    if ($UseWindowsServices) {
        $service = Get-ServiceSafe -ServiceName $ServiceName -ComponentName $ComponentName
        return ($service.Status -eq "Running")
    }

    return ($Processes.Count -gt 0)
}
```

### Programme principal - étape J9

```powershell
    # --------------------------------------------------------
    # J9 - Services Windows et processus
    # --------------------------------------------------------

    Write-Step "[J9] Services et processus en cours"

    $taskflowProcesses   = @()
    $agentProcesses      = @()
    $schedulerProcesses  = @()
    $runnerProcesses     = @()
    $taskflowWasRunning  = $false
    $agentWasRunning     = $false
    $schedulerWasRunning = $false

    if ($UseWindowsServices) {
        if ($STP) {
            Assert-ServiceConfiguration -ServiceName $TaskflowServiceName -ComponentName "Taskflow" -ExpectedExecutablePath $paths.TaskflowExecutable
        }

        if ($STJ) {
            Assert-ServiceConfiguration -ServiceName $HpcLiteAgentServiceName -ComponentName "HpcLite Agent" -ExpectedExecutablePath $paths.AgentExecutable
            Assert-ServiceConfiguration -ServiceName $HpcLiteSchedulerServiceName -ComponentName "HpcLite Scheduler" -ExpectedExecutablePath $paths.SchedulerExecutable
        }
    }
    else {
        Write-Log -Message "Mode test : services Windows ignorés, composants pilotés comme de simples processus." -Level "ATTENTION"
    }

    if ($STP) {
        $taskflowProcesses = @(Get-ProcessesByExecutablePath -ExecutablePath $paths.TaskflowExecutable)
        Assert-SingleProcessMaximum -Processes $taskflowProcesses -ComponentName "Taskflow"

        $taskflowWasRunning = Test-SingleComponentRunning -Processes $taskflowProcesses -ComponentName "Taskflow" -ServiceName $TaskflowServiceName

        Write-Log -Message "Taskflow : $($taskflowProcesses.Count) processus, démarré : $taskflowWasRunning."
    }

    if ($STJ) {
        $agentProcesses     = @(Get-ProcessesByExecutablePath -ExecutablePath $paths.AgentExecutable)
        $schedulerProcesses = @(Get-ProcessesByExecutablePath -ExecutablePath $paths.SchedulerExecutable)
        $runnerProcesses    = @(Get-ProcessesByExecutablePath -ExecutablePath $paths.RunnerExecutable)

        Assert-SingleProcessMaximum -Processes $agentProcesses     -ComponentName "HpcLite Agent"
        Assert-SingleProcessMaximum -Processes $schedulerProcesses -ComponentName "HpcLite Scheduler"

        # Volontairement aucun maximum pour les Runners.

        $agentWasRunning     = Test-SingleComponentRunning -Processes $agentProcesses -ComponentName "HpcLite Agent" -ServiceName $HpcLiteAgentServiceName
        $schedulerWasRunning = Test-SingleComponentRunning -Processes $schedulerProcesses -ComponentName "HpcLite Scheduler" -ServiceName $HpcLiteSchedulerServiceName

        Write-Log -Message "HpcLite Agent : $($agentProcesses.Count) processus, démarré : $agentWasRunning."
        Write-Log -Message "HpcLite Scheduler : $($schedulerProcesses.Count) processus, démarré : $schedulerWasRunning."
        Write-Log -Message "HpcLite Runner : $($runnerProcesses.Count) processus."
    }
```

