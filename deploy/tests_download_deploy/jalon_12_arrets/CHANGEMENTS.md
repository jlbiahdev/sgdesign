# Jalon 12 - code ajouté

Fichier généré par `_tools\Build-JalonVersions.ps1`. Ne pas modifier.

| | |
|---|---|
| Lignes de la version du jalon 12 | 1796 |
| Lignes de la version précédente | 1508 |
| Lignes ajoutées par ce jalon | 277 |
| Lignes retirées par ce jalon | 0 |

La version se termine par le bloc « JALON 12 ATTEINT / TEST TERMINÉ » (non repris ci-dessous).

## Ajouté

### Configuration / variables

```powershell
# Délais maximum (secondes) pour constater un arrêt ou un démarrage.
$ProcessTimeoutSeconds = 30
$ServiceTimeoutSeconds = 60
$IisTimeoutSeconds = 60
```

### Fonction Stop-ProcessesByExecutablePath

```powershell
<#
.SYNOPSIS
    Arrête brutalement tous les processus lancés depuis cet exécutable.
.DESCRIPTION
    Utilisé pour les Runners HpcLite, et pour tout composant en mode test
    ($UseWindowsServices = $false). Attend la disparition effective des
    processus ($ProcessTimeoutSeconds).
#>
function Stop-ProcessesByExecutablePath {
    param(
        [Parameter(Mandatory = $true)] [string] $ExecutablePath,
        [Parameter(Mandatory = $true)] [string] $ComponentName,
        [Parameter()] [switch] $SingleInstance
    )

    $processes = @(Get-ProcessesByExecutablePath -ExecutablePath $ExecutablePath)

    if ($SingleInstance) {
        Assert-SingleProcessMaximum -Processes $processes -ComponentName $ComponentName
    }

    if ($processes.Count -eq 0) {
        Write-Log -Message "$ComponentName : aucun processus en cours. Aucune action nécessaire."
        return
    }

    Write-Log -Message "$ComponentName : $($processes.Count) processus à arrêter."

    foreach ($process in $processes) {
        Write-Log -Message "Arrêt brutal de $ComponentName, PID $($process.ProcessId)."

        # Le processus peut s'être terminé entre la détection et l'arrêt.
        Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
    }

    $deadline = (Get-Date).AddSeconds($ProcessTimeoutSeconds)

    do {
        Start-Sleep -Milliseconds 500
        $remainingProcesses = @(Get-ProcessesByExecutablePath -ExecutablePath $ExecutablePath)
    }
    while ($remainingProcesses.Count -gt 0 -and (Get-Date) -lt $deadline)

    if ($remainingProcesses.Count -gt 0) {
        $remainingIds = $remainingProcesses.ProcessId -join ", "

        throw @"
Impossible d'arrêter complètement $ComponentName.

Processus encore présents :
$remainingIds
"@
    }

    Write-Log -Message "$ComponentName est maintenant arrêté." -Level "OK"
}
```

### Fonction Stop-ServiceSafe

```powershell
<#
.SYNOPSIS
    Arrête un service et attend l'état Stopped.
#>
function Stop-ServiceSafe {
    param(
        [Parameter(Mandatory = $true)] [string] $ServiceName,
        [Parameter(Mandatory = $true)] [string] $ComponentName
    )

    $service = Get-ServiceSafe -ServiceName $ServiceName -ComponentName $ComponentName

    if ($service.Status -eq "Stopped") {
        Write-Log -Message "Le service $ComponentName ('$ServiceName') est déjà arrêté."
        return
    }

    Write-Log -Message "Arrêt du service $ComponentName ('$ServiceName')."

    Stop-Service -Name $ServiceName -Force -ErrorAction Stop

    try {
        $service.WaitForStatus(
            [ServiceProcess.ServiceControllerStatus]::Stopped,
            [TimeSpan]::FromSeconds($ServiceTimeoutSeconds)
        )
    }
    catch {
        throw "Le service $ComponentName ('$ServiceName') ne s'est pas arrêté dans le délai imparti."
    }

    Write-Log -Message "Le service $ComponentName est arrêté." -Level "OK"
}
```

### Fonction Stop-SingleComponent

```powershell
<#
.SYNOPSIS
    Arrête un composant à instance unique (Taskflow, Agent, Scheduler).
.DESCRIPTION
    Production : arrêt par le gestionnaire de services, puis contrôle
    qu'aucun processus ne subsiste depuis cet exécutable.
    Mode test : arrêt brutal du processus.
#>
function Stop-SingleComponent {
    param(
        [Parameter(Mandatory = $true)] [string] $ExecutablePath,
        [Parameter(Mandatory = $true)] [string] $ComponentName,
        [Parameter()] [string] $ServiceName
    )

    if ($UseWindowsServices) {
        Stop-ServiceSafe -ServiceName $ServiceName -ComponentName $ComponentName
    }

    Stop-ProcessesByExecutablePath -ExecutablePath $ExecutablePath -ComponentName $ComponentName -SingleInstance
}
```

### Fonction Wait-IisWorkerProcessExit

```powershell
<#
.SYNOPSIS
    Attend la fin du processus w3wp.exe du pool.
.DESCRIPTION
    Un pool à l'état Stopped peut encore avoir un w3wp.exe en cours
    d'arrêt qui verrouille les fichiers de l'API.
#>
function Wait-IisWorkerProcessExit {
    param(
        [Parameter(Mandatory = $true)]
        [string] $ApplicationPoolName
    )

    $pattern  = "*-ap `"$ApplicationPoolName`"*"
    $deadline = (Get-Date).AddSeconds($IisTimeoutSeconds)

    do {
        $workers = @(
            Get-CimInstance -ClassName Win32_Process -Filter "Name = 'w3wp.exe'" -ErrorAction Stop |
                Where-Object { $null -ne $_.CommandLine -and $_.CommandLine -like $pattern }
        )

        if ($workers.Count -eq 0) {
            return
        }

        Start-Sleep -Seconds 1
    }
    while ((Get-Date) -lt $deadline)

    $workerIds = $workers.ProcessId -join ", "
    throw "Le processus IIS (w3wp.exe) du pool '$ApplicationPoolName' ne s'est pas terminé. PID : $workerIds"
}
```

### Fonction Stop-IisApplicationPoolSafe

```powershell
<#
.SYNOPSIS
    Arrête le pool IIS (jamais IIS entier) et attend la fin de son w3wp.
#>
function Stop-IisApplicationPoolSafe {
    param(
        [Parameter(Mandatory = $true)]
        [string] $ApplicationPoolName
    )

    $state = Get-IisApplicationPoolState -ApplicationPoolName $ApplicationPoolName

    if ($state -eq "Stopped") {
        Write-Log -Message "Le pool IIS '$ApplicationPoolName' est déjà arrêté."
        Wait-IisWorkerProcessExit -ApplicationPoolName $ApplicationPoolName
        return
    }

    Write-Log -Message "Arrêt du pool IIS '$ApplicationPoolName'."

    $output = & $AppCmdPath stop apppool "/apppool.name:$ApplicationPoolName" 2>&1

    if ($LASTEXITCODE -ne 0) {
        throw @"
Impossible d'arrêter le pool IIS '$ApplicationPoolName'.

Message IIS :
$($output -join [Environment]::NewLine)
"@
    }

    $deadline = (Get-Date).AddSeconds($IisTimeoutSeconds)

    do {
        Start-Sleep -Seconds 1
        $state = Get-IisApplicationPoolState -ApplicationPoolName $ApplicationPoolName
    }
    while ($state -ne "Stopped" -and (Get-Date) -lt $deadline)

    if ($state -ne "Stopped") {
        throw "Le pool IIS '$ApplicationPoolName' ne s'est pas arrêté."
    }

    Wait-IisWorkerProcessExit -ApplicationPoolName $ApplicationPoolName

    Write-Log -Message "Le pool IIS '$ApplicationPoolName' est arrêté." -Level "OK"
}
```

### Fonction Stop-SelectedApplications

```powershell
<#
.SYNOPSIS
    Arrête les applications sélectionnées. (J12)
.DESCRIPTION
    Ordre HpcLite : Agent (pour qu'il ne crée plus de Runners), puis
    Scheduler, puis tous les Runners.
#>
function Stop-SelectedApplications {
    param(
        [Parameter(Mandatory = $true)]
        [object] $Paths
    )

    if ($STP) {
        Write-Step "Arrêt de Taskflow"

        Stop-SingleComponent -ExecutablePath $Paths.TaskflowExecutable -ComponentName "Taskflow" -ServiceName $TaskflowServiceName
    }

    if ($STX) {
        Write-Step "Arrêt de l'API STX sous IIS"

        Stop-IisApplicationPoolSafe -ApplicationPoolName $StxApplicationPoolName
    }

    if ($STJ) {
        Write-Step "Arrêt de HpcLite"

        Stop-SingleComponent -ExecutablePath $Paths.AgentExecutable -ComponentName "HpcLite Agent" -ServiceName $HpcLiteAgentServiceName

        Stop-SingleComponent -ExecutablePath $Paths.SchedulerExecutable -ComponentName "HpcLite Scheduler" -ServiceName $HpcLiteSchedulerServiceName

        # Zéro, un ou plusieurs Runners : tous sont arrêtés.
        Stop-ProcessesByExecutablePath -ExecutablePath $Paths.RunnerExecutable -ComponentName "HpcLite Runner"

        Write-Log -Message "Tous les processus HpcLite concernés sont arrêtés." -Level "OK"
    }
}
```

### Programme principal / configuration

```powershell
    # --------------------------------------------------------
    # J12 - Confirmation
    # --------------------------------------------------------

    if (-not $Force) {
        Write-Host ""

        try {
            $confirmation = Read-Host "Tapez DEPLOYER pour arrêter les applications et continuer"
        }
        catch {
            # Session non interactive (planificateur, -NonInteractive...).
            Write-Log -Message "Confirmation impossible : la session n'est pas interactive. Utilisez -Force pour une exécution automatisée." -Level "ATTENTION"
            Write-Log -Message "Déploiement annulé. Aucune application n'a été arrêtée." -Level "ATTENTION"
            exit 2
        }

        if ($confirmation -cne "DEPLOYER") {
            Write-Log -Message "Déploiement annulé par l'utilisateur. Aucune application n'a été arrêtée." -Level "ATTENTION"
            exit 2
        }
    }

    Write-Log -Message "Les applications vont maintenant être arrêtées." -Level "ATTENTION"

    # --------------------------------------------------------
    # J12 à J15 - Arrêt, sauvegarde, installation, redémarrage
    # --------------------------------------------------------
```

### Programme principal - étape J12

```powershell
    try {
        Write-Step "[J12] Arrêt des applications"

        Stop-SelectedApplications -Paths $paths

        # [POINT-DE-TEST:apres-arret]
```

### Programme principal / configuration

```powershell
    }
    catch {
        $deploymentError = $_

        Write-Log -Message "Le déploiement a échoué après l'arrêt des applications." -Level "ERREUR"
        Write-Log -Message $deploymentError.Exception.Message -Level "ERREUR"
```

### Programme principal / configuration

```powershell
        throw $deploymentError
    }
```

