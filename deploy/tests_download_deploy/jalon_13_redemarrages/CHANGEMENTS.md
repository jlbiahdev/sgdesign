# Jalon 13 - code ajouté

Fichier généré par `_outils\Build-JalonVersions.ps1`. Ne pas modifier.

| | |
|---|---|
| Lignes de la version du jalon 13 | 2029 |
| Lignes de la version précédente | 1785 |
| Lignes ajoutées par ce jalon | 238 |
| Lignes retirées par ce jalon | 0 |

La version se termine par le bloc « JALON 13 ATTEINT / TEST TERMINÉ » (non repris ci-dessous).

## Ajouté

### Configuration / variables

```powershell
# Arguments de démarrage, utilisés seulement si $UseWindowsServices = $false.
$TaskflowStartArguments = @()
$HpcLiteAgentStartArguments = @()
$HpcLiteSchedulerStartArguments = @()
```

### Fonction Start-Executable

```powershell
<#
.SYNOPSIS
    Démarre un exécutable (mode test uniquement) et attend son processus.
#>
function Start-Executable {
    param(
        [Parameter(Mandatory = $true)] [string] $ExecutablePath,
        [Parameter(Mandatory = $true)] [string] $ComponentName,
        [Parameter()] [string[]] $Arguments = @(),
        [Parameter()] [switch] $SingleInstance
    )

    Assert-ExistingFile -Path $ExecutablePath -Description "Exécutable de $ComponentName"

    $existingProcesses = @(Get-ProcessesByExecutablePath -ExecutablePath $ExecutablePath)

    if ($SingleInstance) {
        Assert-SingleProcessMaximum -Processes $existingProcesses -ComponentName $ComponentName
    }

    if ($existingProcesses.Count -gt 0) {
        Write-Log -Message "$ComponentName fonctionne déjà. Aucun nouveau processus ne sera créé." -Level "ATTENTION"
        return
    }

    Write-Log -Message "Démarrage de $ComponentName depuis $ExecutablePath."

    $startParameters = @{
        FilePath         = $ExecutablePath
        WorkingDirectory = (Split-Path -Parent -Path $ExecutablePath)
        WindowStyle      = "Hidden"
        ErrorAction      = "Stop"
    }

    if ($Arguments.Count -gt 0) {
        $startParameters["ArgumentList"] = $Arguments
    }

    Start-Process @startParameters | Out-Null

    $deadline = (Get-Date).AddSeconds($ProcessTimeoutSeconds)

    do {
        Start-Sleep -Milliseconds 500
        $startedProcesses = @(Get-ProcessesByExecutablePath -ExecutablePath $ExecutablePath)
    }
    while ($startedProcesses.Count -eq 0 -and (Get-Date) -lt $deadline)

    if ($startedProcesses.Count -eq 0) {
        throw @"
Le démarrage de $ComponentName a échoué.

Aucun processus n'a été détecté après le démarrage de :
$ExecutablePath
"@
    }

    if ($SingleInstance) {
        Assert-SingleProcessMaximum -Processes $startedProcesses -ComponentName $ComponentName
    }

    Write-Log -Message "$ComponentName a démarré correctement." -Level "OK"
}
```

### Fonction Start-ServiceSafe

```powershell
<#
.SYNOPSIS
    Démarre un service et attend l'état Running.
#>
function Start-ServiceSafe {
    param(
        [Parameter(Mandatory = $true)] [string] $ServiceName,
        [Parameter(Mandatory = $true)] [string] $ComponentName
    )

    $service = Get-ServiceSafe -ServiceName $ServiceName -ComponentName $ComponentName

    if ($service.Status -eq "Running") {
        Write-Log -Message "Le service $ComponentName ('$ServiceName') fonctionne déjà."
        return
    }

    Write-Log -Message "Démarrage du service $ComponentName ('$ServiceName')."

    Start-Service -Name $ServiceName -ErrorAction Stop

    try {
        $service.WaitForStatus(
            [ServiceProcess.ServiceControllerStatus]::Running,
            [TimeSpan]::FromSeconds($ServiceTimeoutSeconds)
        )
    }
    catch {
        throw "Le service $ComponentName ('$ServiceName') n'a pas démarré dans le délai imparti."
    }

    Write-Log -Message "Le service $ComponentName fonctionne." -Level "OK"
}
```

### Fonction Start-SingleComponent

```powershell
<#
.SYNOPSIS
    Démarre un composant à instance unique (Taskflow, Agent, Scheduler).
#>
function Start-SingleComponent {
    param(
        [Parameter(Mandatory = $true)] [string] $ExecutablePath,
        [Parameter(Mandatory = $true)] [string] $ComponentName,
        [Parameter()] [string] $ServiceName,
        [Parameter()] [string[]] $Arguments = @()
    )

    if ($UseWindowsServices) {
        Start-ServiceSafe -ServiceName $ServiceName -ComponentName $ComponentName

        $processes = @(Get-ProcessesByExecutablePath -ExecutablePath $ExecutablePath)
        Assert-SingleProcessMaximum -Processes $processes -ComponentName $ComponentName
        return
    }

    Start-Executable -ExecutablePath $ExecutablePath -ComponentName $ComponentName -Arguments $Arguments -SingleInstance
}
```

### Fonction Start-IisApplicationPoolSafe

```powershell
<#
.SYNOPSIS
    Démarre le pool IIS et attend l'état Started.
#>
function Start-IisApplicationPoolSafe {
    param(
        [Parameter(Mandatory = $true)]
        [string] $ApplicationPoolName
    )

    $state = Get-IisApplicationPoolState -ApplicationPoolName $ApplicationPoolName

    if ($state -eq "Started") {
        Write-Log -Message "Le pool IIS '$ApplicationPoolName' fonctionne déjà."
        return
    }

    Write-Log -Message "Démarrage du pool IIS '$ApplicationPoolName'."

    $output = & $AppCmdPath start apppool "/apppool.name:$ApplicationPoolName" 2>&1

    if ($LASTEXITCODE -ne 0) {
        throw @"
Impossible de démarrer le pool IIS '$ApplicationPoolName'.

Message IIS :
$($output -join [Environment]::NewLine)
"@
    }

    $deadline = (Get-Date).AddSeconds($IisTimeoutSeconds)

    do {
        Start-Sleep -Seconds 1
        $state = Get-IisApplicationPoolState -ApplicationPoolName $ApplicationPoolName
    }
    while ($state -ne "Started" -and (Get-Date) -lt $deadline)

    if ($state -ne "Started") {
        throw "Le pool IIS '$ApplicationPoolName' n'a pas redémarré."
    }

    Write-Log -Message "Le pool IIS '$ApplicationPoolName' fonctionne." -Level "OK"
}
```

### Fonction Start-PreviouslyRunningApplications

```powershell
<#
.SYNOPSIS
    Redémarre ce qui fonctionnait avant le déploiement. (J13)
.DESCRIPTION
    Un composant arrêté avant le déploiement reste arrêté.
    Ordre HpcLite : Scheduler, puis Agent. Les Runners ne sont jamais
    redémarrés par le script : l'Agent les recrée.
#>
function Start-PreviouslyRunningApplications {
    param(
        [Parameter(Mandatory = $true)] [object] $Paths,
        [Parameter(Mandatory = $true)] [object] $PreviousState
    )

    if ($STP) {
        if ($PreviousState.TaskflowWasRunning) {
            Write-Step "Redémarrage de Taskflow"

            Start-SingleComponent -ExecutablePath $Paths.TaskflowExecutable -ComponentName "Taskflow" -ServiceName $TaskflowServiceName -Arguments $TaskflowStartArguments
        }
        else {
            Write-Log -Message "Taskflow était arrêté avant le déploiement. Il reste arrêté." -Level "ATTENTION"
        }
    }

    if ($STX) {
        if ($PreviousState.ApiWasRunning) {
            Write-Step "Redémarrage de l'API STX"

            Start-IisApplicationPoolSafe -ApplicationPoolName $StxApplicationPoolName
        }
        else {
            Write-Log -Message "Le pool IIS STX était arrêté avant le déploiement. Il reste arrêté." -Level "ATTENTION"
        }
    }

    # [POINT-DE-TEST:pendant-redemarrage]

    if ($STJ) {
        Write-Step "Redémarrage de HpcLite"

        if ($PreviousState.SchedulerWasRunning) {
            Start-SingleComponent -ExecutablePath $Paths.SchedulerExecutable -ComponentName "HpcLite Scheduler" -ServiceName $HpcLiteSchedulerServiceName -Arguments $HpcLiteSchedulerStartArguments
        }
        else {
            Write-Log -Message "Le Scheduler était arrêté avant le déploiement. Il reste arrêté." -Level "ATTENTION"
        }

        if ($PreviousState.AgentWasRunning) {
            Start-SingleComponent -ExecutablePath $Paths.AgentExecutable -ComponentName "HpcLite Agent" -ServiceName $HpcLiteAgentServiceName -Arguments $HpcLiteAgentStartArguments
        }
        else {
            Write-Log -Message "L'Agent était arrêté avant le déploiement. Il reste arrêté." -Level "ATTENTION"
        }

        Write-Log -Message "Les Runners ne sont pas redémarrés directement par le script."
        Write-Log -Message "L'Agent pourra créer de nouveaux Runners selon les jobs présents en base."
    }
}
```

### Programme principal - étape J13

```powershell
        Write-Step "[J13] Redémarrage des applications"

        Start-PreviouslyRunningApplications -Paths $paths -PreviousState $previousState
```

### Programme principal / configuration

```powershell
        # On tente de remettre les applications dans leur état initial.
        try {
            Write-Step "Redémarrage après rollback"
            Start-PreviouslyRunningApplications -Paths $paths -PreviousState $previousState
        }
        catch {
            Write-Log -Message "Les fichiers sont en place, mais le redémarrage a échoué : $($_.Exception.Message)" -Level "ERREUR"
        }
```

