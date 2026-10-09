#requires -Version 5.1

<#
.SYNOPSIS
    Boîte à outils commune à tous les lanceurs de test (launch_test.ps1).

.DESCRIPTION
    Chaque launch_test.ps1 suit le même schéma :

        Import-Module ..\..\_common\TestHelpers.psm1
        Start-Test ...                 # en-tête, prérequis, dossier de travail
        try {
            # Préparation : environnement factice, package, script adapté
            # Exécution   : Invoke-ScriptUnderTest
            # Vérifications : Assert-*
        }
        catch   { Register-TestError -ErrorRecord $_ }
        finally { Clear-TestEnvironment }   # nettoyage TOUJOURS exécuté
        exit (Complete-Test)                # TEST RÉUSSI / ÉCHOUÉ

    Principes :
      - Les assertions n'interrompent pas le test : toutes les anomalies
        sont listées à la fin.
      - Tout ce qu'un test crée, démarre ou modifie est enregistré ici, puis
        défait par Clear-TestEnvironment (dossiers factices, processus
        factices, variables d'environnement, état des services et du pool
        IIS, marqueurs de version, sauvegardes créées pendant le test).
      - Rien n'est supprimé en dehors de ce que le test a lui-même créé.
      - Aucun secret n'est jamais affiché.

    Codes de sortie d'un lanceur (Complete-Test) :
      0  TEST RÉUSSI   : le comportement observé est celui attendu
      1  TEST ÉCHOUÉ   : au moins une vérification a échoué
      2  NON EXÉCUTÉ   : prérequis absent ou erreur de préparation du test

.NOTES
    Module chargé par Import-Module -Force à chaque test : aucun état ne
    survit d'un test à l'autre.
#>

Set-StrictMode -Version Latest

# ============================================================
# ÉTAT DU TEST EN COURS
# ============================================================

# Rempli par Start-Test, lu par toutes les autres fonctions.
$script:T = $null

# Valeur du faux token utilisé par les tests : ne correspond à aucun compte.
$script:FakeToken    = "token-factice-NE-PAS-UTILISER-0123456789"
$script:FakeUsername = "utilisateur-de-test"

<#
.SYNOPSIS
    Renvoie l'état du test en cours (échoue si Start-Test n'a pas été appelé).
#>
function Get-TestState {
    if ($null -eq $script:T) {
        throw "PREPARATION : Start-Test doit être appelé en premier."
    }

    return $script:T
}

<#
.SYNOPSIS
    Renvoie la configuration lue dans _common\test-config.psd1.
#>
function Get-TestConfig {
    return (Get-TestState).Config
}

<#
.SYNOPSIS
    Renvoie les faux identifiants Artifactory des tests.
.OUTPUTS
    Objet { Username ; Token }. Ces valeurs ne donnent accès à rien.
#>
function Get-FakeCredentials {
    return [pscustomobject] @{
        Username = $script:FakeUsername
        Token    = $script:FakeToken
    }
}

# ============================================================
# DÉBUT ET FIN DE TEST
# ============================================================

<#
.SYNOPSIS
    Démarre un test : en-tête, vérification des prérequis, dossier de travail.

.PARAMETER ScenarioRoot
    Toujours $PSScriptRoot (dossier du scénario).

.PARAMETER Jalon
    Numéro du jalon testé (0 à 19).

.PARAMETER Objectif
    Phrase décrivant ce que le scénario vérifie.

.PARAMETER ResultatAttendu
    « Succès », « Échec contrôlé » ou « Annulation ».

.PARAMETER CodeAttendu
    Code de sortie attendu de download_deploy.ps1.

.PARAMETER NonAdministrateur
    Le test DOIT être lancé depuis une console NON administrateur.

.PARAMETER AvecIis
    IIS (appcmd.exe) doit être installé (tests utilisant -STX).

.PARAMETER PoolIis
    Le pool IIS de test doit exister (implique AvecIis).

.PARAMETER ServicesReels
    Les trois services Windows doivent exister.

.PARAMETER EnvironnementReel
    L'environnement réel de test doit être complet et sûr (implique
    ServicesReels et PoolIis). L'état des services et du pool est mémorisé
    et sera restauré à la fin du test, ainsi que les sauvegardes créées.

.PARAMETER IdentifiantsReels
    De vrais identifiants Artifactory et UrlPackageReel sont nécessaires.
#>
function Start-Test {
    param(
        [Parameter(Mandatory = $true)] [string] $ScenarioRoot,
        [Parameter(Mandatory = $true)] [int] $Jalon,
        [Parameter(Mandatory = $true)] [string] $Objectif,
        [Parameter(Mandatory = $true)] [string] $ResultatAttendu,
        [Parameter(Mandatory = $true)] [int] $CodeAttendu,
        [switch] $NonAdministrateur,
        [switch] $AvecIis,
        [switch] $PoolIis,
        [switch] $ServicesReels,
        [switch] $EnvironnementReel,
        [switch] $IdentifiantsReels
    )

    $scenario = Split-Path -Leaf -Path $ScenarioRoot

    $script:T = [pscustomobject] @{
        Scenario            = $scenario
        ScenarioRoot        = $ScenarioRoot
        Jalon               = $Jalon
        Objectif            = $Objectif
        ResultatAttendu     = $ResultatAttendu
        CodeAttendu         = $CodeAttendu
        CodeObtenu          = $null
        StartTime           = Get-Date
        Config              = $null
        WorkDirectory       = Join-Path $env:TEMP "styx-tests\$scenario"
        Failures            = [System.Collections.Generic.List[string]]::new()
        Successes           = [System.Collections.Generic.List[string]]::new()
        PrerequisiteError   = $null
        PreparationError    = $null
        StartedProcessIds   = [System.Collections.Generic.List[int]]::new()
        FakeRoots           = [System.Collections.Generic.List[string]]::new()
        PathsToRemove       = [System.Collections.Generic.List[string]]::new()
        EnvironmentBackups  = [System.Collections.Generic.List[object]]::new()
        SavedAppState       = $null
        RollbackSnapshot    = $null
        VersionMarkers      = [System.Collections.Generic.List[object]]::new()
        PoolRestore         = $null
    }

    Write-Host ""
    Write-Host ("=" * 70) -ForegroundColor Cyan
    Write-Host "SCÉNARIO  : $scenario" -ForegroundColor Cyan
    Write-Host "JALON     : $Jalon" -ForegroundColor Cyan
    Write-Host "OBJECTIF  : $Objectif" -ForegroundColor Cyan
    Write-Host "ATTENDU   : $ResultatAttendu (code $CodeAttendu)" -ForegroundColor Cyan
    Write-Host ("=" * 70) -ForegroundColor Cyan

    # Les vérifications ci-dessous lèvent une exception « PREREQUIS : ... »
    # en cas d'absence : le lanceur l'intercepte (catch) et le corps du test
    # n'est pas exécuté.

    # Configuration
    $configPath = Join-Path $PSScriptRoot "test-config.psd1"

    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        throw "PREREQUIS : fichier de configuration introuvable : $configPath"
    }

    $script:T.Config = Import-PowerShellDataFile -Path $configPath

    # PowerShell
    if ($PSVersionTable.PSVersion -lt [version] "5.1") {
        throw "PREREQUIS : Windows PowerShell 5.1 est nécessaire (version actuelle : $($PSVersionTable.PSVersion))."
    }

    # Droits
    $isAdmin = Test-IsAdministrator

    if ($NonAdministrateur -and $isAdmin) {
        throw "PREREQUIS : ce test doit être lancé depuis une console NON administrateur. Ouvrez PowerShell normalement (sans « Exécuter en tant qu'administrateur ») et relancez-le."
    }

    if (-not $NonAdministrateur -and -not $isAdmin) {
        throw "PREREQUIS : ce test doit être lancé depuis une console administrateur."
    }

    # Lecteur D:
    if (-not (Test-Path -LiteralPath "D:\" -PathType Container)) {
        throw "PREREQUIS : le lecteur D: est introuvable."
    }

    if ($EnvironnementReel) {
        $ServicesReels = $true
        $PoolIis = $true
    }

    if ($PoolIis) {
        $AvecIis = $true
    }

    if ($AvecIis -and -not (Test-Path -LiteralPath (Get-AppCmdPath) -PathType Leaf)) {
        throw "PREREQUIS : IIS (appcmd.exe) n'est pas installé sur cette machine."
    }

    if ($PoolIis -and -not (Test-IisPoolExists -Name $script:T.Config.PoolIis)) {
        throw "PREREQUIS : le pool IIS de test '$($script:T.Config.PoolIis)' est introuvable (voir test-config.psd1)."
    }

    if ($ServicesReels) {
        foreach ($serviceName in (Get-ConfiguredServiceNames)) {
            if ($null -eq (Get-Service -Name $serviceName -ErrorAction SilentlyContinue)) {
                throw "PREREQUIS : le service Windows '$serviceName' est introuvable sur cette machine."
            }
        }
    }

    if ($EnvironnementReel) {
        Assert-RealEnvironmentIsSafe

        # Mémorisation pour restauration automatique en fin de test.
        $script:T.SavedAppState    = Get-ApplicationState
        $script:T.RollbackSnapshot = @(Get-RollbackDirectoryNames -Root $script:T.Config.RacineReelle)

        Write-Host "État initial mémorisé : $(Format-ApplicationState -State $script:T.SavedAppState)"
    }

    if ($IdentifiantsReels) {
        if ([string]::IsNullOrWhiteSpace($script:T.Config.UrlPackageReel)) {
            throw "PREREQUIS : UrlPackageReel n'est pas renseignée dans test-config.psd1."
        }

        foreach ($name in @("ARTIFACTORY_USERNAME", "ARTIFACTORY_TOKEN")) {
            if ([string]::IsNullOrWhiteSpace((Get-AnyEnvironmentValue -Name $name))) {
                throw "PREREQUIS : la variable $name (vrais identifiants) est absente de la session et du niveau Machine."
            }
        }
    }

    # Dossier de travail propre au scénario.
    if (Test-Path -LiteralPath $script:T.WorkDirectory) {
        Remove-Item -LiteralPath $script:T.WorkDirectory -Recurse -Force
    }

    New-Item -Path $script:T.WorkDirectory -ItemType Directory -Force | Out-Null
}

<#
.SYNOPSIS
    Enregistre une erreur survenue pendant la préparation ou l'exécution.
.DESCRIPTION
    Message commençant par « PREREQUIS » : prérequis absent (code 2).
    Autre message : erreur de préparation du test (code 2).
    Dans les deux cas, le comportement du script n'a pas pu être jugé.
#>
function Register-TestError {
    param(
        [Parameter(Mandatory = $true)]
        [Management.Automation.ErrorRecord] $ErrorRecord
    )

    $state   = Get-TestState
    $message = $ErrorRecord.Exception.Message

    if ($message -like "PREREQUIS*") {
        if ($null -eq $state.PrerequisiteError) { $state.PrerequisiteError = $message }
        Write-Host $message -ForegroundColor Yellow
    }
    else {
        if ($null -eq $state.PreparationError) {
            $state.PreparationError = "$message (ligne $($ErrorRecord.InvocationInfo.ScriptLineNumber) : $($ErrorRecord.InvocationInfo.Line.Trim()))"
        }
        Write-Host "ERREUR DE PRÉPARATION DU TEST : $message" -ForegroundColor Red
    }
}

<#
.SYNOPSIS
    Interrompt le test comme « non exécuté » si la condition est fausse.
#>
function Assert-Prerequisite {
    param(
        [Parameter(Mandatory = $true)] [bool] $Condition,
        [Parameter(Mandatory = $true)] [string] $Message
    )

    if (-not $Condition) {
        throw "PREREQUIS : $Message"
    }
}

<#
.SYNOPSIS
    Affiche le verdict et renvoie le code de sortie du lanceur.
.OUTPUTS
    0 (réussi), 1 (échoué), 2 (non exécuté).
#>
function Complete-Test {
    $state = Get-TestState

    $codeObtenu = if ($null -eq $state.CodeObtenu) { "(script non exécuté)" } else { $state.CodeObtenu }

    if ($null -ne $state.PrerequisiteError -or $null -ne $state.PreparationError) {
        $verdict = "TEST NON EXÉCUTÉ"
        $color   = "Yellow"
        $code    = 2
    }
    elseif ($state.Failures.Count -gt 0) {
        $verdict = "TEST ÉCHOUÉ"
        $color   = "Red"
        $code    = 1
    }
    else {
        $verdict = "TEST RÉUSSI"
        $color   = "Green"
        $code    = 0
    }

    Write-Host ""
    Write-Host ("=" * 70) -ForegroundColor $color
    Write-Host $verdict -ForegroundColor $color
    Write-Host "Scénario          : $($state.Scenario)" -ForegroundColor $color
    Write-Host "Résultat attendu  : $($state.ResultatAttendu)" -ForegroundColor $color
    Write-Host "Code attendu      : $($state.CodeAttendu)" -ForegroundColor $color
    Write-Host "Code obtenu       : $codeObtenu" -ForegroundColor $color
    Write-Host "Vérifications OK  : $($state.Successes.Count)" -ForegroundColor $color

    if ($null -ne $state.PrerequisiteError) {
        Write-Host "Prérequis absent  : $($state.PrerequisiteError)" -ForegroundColor $color
    }

    if ($null -ne $state.PreparationError) {
        Write-Host "Erreur du test    : $($state.PreparationError)" -ForegroundColor $color
    }

    foreach ($failure in $state.Failures) {
        Write-Host "  ÉCHEC : $failure" -ForegroundColor $color
    }

    if ($code -eq 1) {
        Write-Host "Consultez les messages affichés ci-dessus." -ForegroundColor $color
    }

    Write-Host ("=" * 70) -ForegroundColor $color

    return $code
}

# ============================================================
# NETTOYAGE
# ============================================================

<#
.SYNOPSIS
    Défait tout ce que le test a créé ou modifié. Ne lève jamais d'erreur.
.DESCRIPTION
    Ordre :
      1. arrêt des processus factices (démarrés par le test ou relancés par
         le script dans un dossier factice) ;
      2. restauration de l'état des services et du pool IIS ;
      3. restauration des variables d'environnement (session et Machine) ;
      4. suppression des marqueurs de version posés dans l'environnement réel ;
      5. suppression des sauvegardes (.rollback) créées pendant le test ;
      6. suppression des dossiers factices et des chemins enregistrés ;
      7. suppression du dossier de travail du scénario.
#>
function Clear-TestEnvironment {
    if ($null -eq $script:T) { return }

    $state = $script:T

    Write-Host ""
    Write-Host "Nettoyage du test..." -ForegroundColor DarkGray

    # 1. Processus factices
    try {
        foreach ($processId in $state.StartedProcessIds) {
            Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue
        }

        foreach ($root in $state.FakeRoots) {
            Stop-ProcessesUnderPath -Root $root
        }
    }
    catch { Write-Warning "Nettoyage des processus : $($_.Exception.Message)" }

    # 2. Services et pool IIS
    if ($null -ne $state.PoolRestore) {
        try { Set-PoolState -State $state.PoolRestore }
        catch { Write-Warning "Restauration du pool IIS : $($_.Exception.Message)" }
    }

    if ($null -ne $state.SavedAppState) {
        try {
            Restore-ApplicationState -State $state.SavedAppState
        }
        catch { Write-Warning "Restauration des services / du pool : $($_.Exception.Message)" }
    }

    # 3. Variables d'environnement (dans l'ordre inverse des modifications)
    for ($index = $state.EnvironmentBackups.Count - 1; $index -ge 0; $index--) {
        $backup = $state.EnvironmentBackups[$index]

        try {
            [Environment]::SetEnvironmentVariable($backup.Name, $backup.Value, $backup.Target)
        }
        catch { Write-Warning "Restauration de $($backup.Name) ($($backup.Target)) : $($_.Exception.Message)" }
    }

    # 4. Marqueurs de version : contenu d'origine remis, ou fichier supprimé
    #    s'il n'existait pas avant le test.
    for ($index = $state.VersionMarkers.Count - 1; $index -ge 0; $index--) {
        $marker = $state.VersionMarkers[$index]
        $file   = Join-Path $marker.Directory "version.txt"

        try {
            if ($null -eq $marker.Original) {
                Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
            }
            elseif (Test-Path -LiteralPath $marker.Directory) {
                [IO.File]::WriteAllBytes($file, $marker.Original)
            }
        }
        catch { Write-Warning "Restauration de $file : $($_.Exception.Message)" }
    }

    # 5. Sauvegardes créées pendant le test (environnement réel)
    if ($null -ne $state.RollbackSnapshot) {
        try {
            $rollbackRoot = Join-Path $state.Config.RacineReelle ".rollback"

            foreach ($name in @(Get-RollbackDirectoryNames -Root $state.Config.RacineReelle)) {
                if ($state.RollbackSnapshot -notcontains $name) {
                    Remove-Item -LiteralPath (Join-Path $rollbackRoot $name) -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
        catch { Write-Warning "Nettoyage des sauvegardes : $($_.Exception.Message)" }
    }

    # 6. Chemins enregistrés et dossiers factices
    foreach ($path in @($state.PathsToRemove) + @($state.FakeRoots)) {
        try {
            if (Test-Path -LiteralPath $path) {
                Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
            }
        }
        catch { Write-Warning "Suppression de $path : $($_.Exception.Message)" }
    }

    # 7. Dossier de travail
    if (Test-Path -LiteralPath $state.WorkDirectory) {
        Remove-Item -LiteralPath $state.WorkDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
}

<#
.SYNOPSIS
    Enregistre un chemin créé par le test, à supprimer au nettoyage.
#>
function Register-PathToRemove {
    param([Parameter(Mandatory = $true)] [string] $Path)

    (Get-TestState).PathsToRemove.Add($Path)
}

# ============================================================
# OUTILS GÉNÉRAUX
# ============================================================

<#
.SYNOPSIS
    Indique si la console courante est administrateur.
#>
function Test-IsAdministrator {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

<#
.SYNOPSIS
    Chemin d'appcmd.exe.
#>
function Get-AppCmdPath {
    return (Join-Path $env:WINDIR "System32\inetsrv\appcmd.exe")
}

<#
.SYNOPSIS
    Noms des trois services configurés dans test-config.psd1.
#>
function Get-ConfiguredServiceNames {
    $config = Get-TestConfig
    return @($config.ServiceTaskflow, $config.ServiceAgent, $config.ServiceScheduler)
}

<#
.SYNOPSIS
    Transforme un texte en littéral PowerShell entre apostrophes.
.EXAMPLE
    ConvertTo-PsLiteral "Q:\"   ->   'Q:\'
#>
function ConvertTo-PsLiteral {
    param([Parameter(Mandatory = $true)] [AllowEmptyString()] [string] $Value)

    return "'" + $Value.Replace("'", "''") + "'"
}

<#
.SYNOPSIS
    Renvoie une lettre de lecteur inutilisée, sous la forme « X:\ ».
#>
function Get-UnusedDriveLetter {
    $used = @(Get-PSDrive -PSProvider FileSystem | ForEach-Object { $_.Name.ToUpperInvariant() })

    foreach ($letter in [char[]] "QRSTUVWXYZ") {
        if ($used -notcontains [string] $letter) {
            return "${letter}:\"
        }
    }

    throw "PREREQUIS : aucune lettre de lecteur libre entre Q: et Z:."
}

<#
.SYNOPSIS
    Valeur d'une variable d'environnement (session, sinon Machine).
#>
function Get-AnyEnvironmentValue {
    param([Parameter(Mandatory = $true)] [string] $Name)

    $value = [Environment]::GetEnvironmentVariable($Name, "Process")

    if ([string]::IsNullOrWhiteSpace($value)) {
        $value = [Environment]::GetEnvironmentVariable($Name, "Machine")
    }

    return $value
}

<#
.SYNOPSIS
    Modifie temporairement des variables d'environnement.
.DESCRIPTION
    -Session : variables du processus du lanceur (héritées par le script testé).
    -Machine : variables de niveau Machine (registre). À n'utiliser que si
               le comportement Machine est l'objet du test.
    Une valeur $null supprime la variable.
    Les anciennes valeurs sont restaurées par Clear-TestEnvironment.
.EXAMPLE
    Set-TestEnvironmentVariables -Session @{ ARTIFACTORY_TOKEN = $null } -Machine @{ ARTIFACTORY_TOKEN = $null }
#>
function Set-TestEnvironmentVariables {
    param(
        [hashtable] $Session = @{},
        [hashtable] $Machine = @{}
    )

    $state = Get-TestState

    foreach ($target in @("Process", "Machine")) {
        $values = if ($target -eq "Process") { $Session } else { $Machine }

        foreach ($name in $values.Keys) {
            $state.EnvironmentBackups.Add([pscustomobject] @{
                Name   = $name
                Target = $target
                Value  = [Environment]::GetEnvironmentVariable($name, $target)
            })

            [Environment]::SetEnvironmentVariable($name, $values[$name], $target)
        }
    }
}

<#
.SYNOPSIS
    Supprime temporairement les trois variables Artifactory (session ET
    Machine), pour partir d'un environnement maîtrisé.
#>
function Clear-ArtifactoryVariables {
    $empty = @{
        ARTIFACTORY_USERNAME = $null
        ARTIFACTORY_TOKEN    = $null
        STYX_PACKAGE_URL     = $null
    }

    Set-TestEnvironmentVariables -Session $empty -Machine $empty
}

# ============================================================
# SCRIPT TESTÉ
# ============================================================

<#
.SYNOPSIS
    Prépare la copie du script à exécuter, adaptée à la machine de test.

.DESCRIPTION
    Le download_deploy.ps1 du dossier du scénario n'est JAMAIS modifié.
    Une copie est écrite dans le dossier de travail, avec :

      - les valeurs de test-config.psd1 (pool IIS, noms de services),
        sauf avec -SansAdaptation ;
      - $UseWindowsServices = $false avec -ModeExecutable ;
      - les lignes de -Configuration (section CONFIGURATION uniquement) ;
      - une erreur volontaire à la place d'un « # [POINT-DE-TEST:nom] »
        avec -InjecterErreur (déclenchée une seule fois) ;
      - une autre version dans #requires avec -RequiresVersion.

    Chaque remplacement doit trouver exactement une ligne, sinon le test
    s'arrête (non exécuté) : un test ne doit jamais tourner sur un script
    qu'il croit avoir adapté.

.PARAMETER Configuration
    Hashtable Nom -> expression PowerShell. Exemple :
    @{ RequiredDrive = "'Q:\'" ; PreservedRelativePathsSTX = "@('config.local.json')" }

.PARAMETER InjecterErreur
    apres-journal, apres-arret, apres-sauvegarde,
    apres-installation-composant, pendant-redemarrage.

.PARAMETER ConditionErreur
    Condition PowerShell supplémentaire pour déclencher l'erreur.
    Exemple : '$script:ChangedComponents.Count -ge 2'

.OUTPUTS
    Chemin de la copie à passer à Invoke-ScriptUnderTest.
#>
function New-ScriptUnderTest {
    param(
        [hashtable] $Configuration = @{},
        [switch] $ModeExecutable,
        [switch] $SansAdaptation,
        [string] $InjecterErreur,
        [string] $ConditionErreur,
        [string] $RequiresVersion
    )

    $state  = Get-TestState
    $config = $state.Config
    $source = Join-Path $state.ScenarioRoot "download_deploy.ps1"

    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "PREPARATION : download_deploy.ps1 introuvable dans le dossier du scénario."
    }

    $text = [IO.File]::ReadAllText($source)

    # Valeurs appliquées, dans l'ordre : test-config, mode, demandes du test.
    # Les versions des premiers jalons ne contiennent pas encore toutes les
    # lignes de configuration (ex. le pool IIS arrive au jalon 10) : les
    # valeurs de test-config et du mode test ne sont appliquées que si la
    # ligne existe. Les valeurs demandées explicitement (-Configuration)
    # doivent, elles, toujours exister.
    $overrides = [ordered] @{}
    $optional  = @{}

    if (-not $SansAdaptation) {
        $overrides["StxApplicationPoolName"]      = ConvertTo-PsLiteral $config.PoolIis
        $overrides["TaskflowServiceName"]         = ConvertTo-PsLiteral $config.ServiceTaskflow
        $overrides["HpcLiteAgentServiceName"]     = ConvertTo-PsLiteral $config.ServiceAgent
        $overrides["HpcLiteSchedulerServiceName"] = ConvertTo-PsLiteral $config.ServiceScheduler
        # Délai de stabilité réduit pour les tests (optionnel).
        if ($config.ContainsKey("StabiliteDemarrageSecondes")) {
            $overrides["StartupStabilitySeconds"] = [string] [int] $config.StabiliteDemarrageSecondes
        }
        if ($config.ContainsKey("ArchiveApplicative")) {
            $overrides["PackageApplicationArchive"] = ConvertTo-PsLiteral $config.ArchiveApplicative
        }
        foreach ($key in @($overrides.Keys)) { $optional[$key] = $true }
    }

    if ($ModeExecutable) {
        $overrides["UseWindowsServices"] = '$false'
        $optional["UseWindowsServices"] = $true
    }

    foreach ($key in $Configuration.Keys) {
        $overrides[$key] = $Configuration[$key]
        $optional.Remove($key)
    }

    # Remplacements limités à la section CONFIGURATION.
    $startMarker = "# >>> DEBUT CONFIGURATION"
    $endMarker   = "# <<< FIN CONFIGURATION"
    $startIndex  = $text.IndexOf($startMarker)
    $endIndex    = $text.IndexOf($endMarker)

    if ($startIndex -lt 0 -or $endIndex -lt $startIndex) {
        throw "PREPARATION : section CONFIGURATION introuvable dans download_deploy.ps1."
    }

    $before = $text.Substring(0, $startIndex)
    $block  = $text.Substring($startIndex, $endIndex - $startIndex)
    $after  = $text.Substring($endIndex)

    foreach ($name in $overrides.Keys) {
        $pattern = "(?m)^\`$" + [regex]::Escape($name) + "\s*=.*$"
        $count   = ([regex]::Matches($block, $pattern)).Count

        if ($count -eq 0 -and $optional.ContainsKey($name)) {
            continue
        }

        if ($count -ne 1) {
            throw "PREPARATION : la ligne de configuration `$$name a été trouvée $count fois (1 attendue)."
        }

        $replacement = "`$$name = $($overrides[$name])   # <- valeur de test"
        $block = [regex]::Replace($block, $pattern, [Text.RegularExpressions.MatchEvaluator] { param($m) $replacement })

        Write-Host "Configuration de test : `$$name = $($overrides[$name])" -ForegroundColor DarkGray
    }

    $text = $before + $block + $after

    # Erreur volontaire.
    if (-not [string]::IsNullOrWhiteSpace($InjecterErreur)) {
        $pattern = "(?m)^(?<indent>[ \t]*)# \[POINT-DE-TEST:" + [regex]::Escape($InjecterErreur) + "\][ \t]*\r?$"
        $count   = ([regex]::Matches($text, $pattern)).Count

        if ($count -ne 1) {
            throw "PREPARATION : point de test '$InjecterErreur' trouvé $count fois (1 attendu)."
        }

        $condition = if ([string]::IsNullOrWhiteSpace($ConditionErreur)) { '$true' } else { $ConditionErreur }

        # Déclenchée une seule fois : le redémarrage après rollback, qui
        # repasse au même endroit, doit pouvoir réussir.
        $code = "if (($condition) -and -not (Get-Variable -Name PointDeTestDeclenche -Scope Script -ErrorAction SilentlyContinue)) { `$script:PointDeTestDeclenche = `$true; throw 'ERREUR DE TEST VOLONTAIRE ($InjecterErreur)' }"

        $text = [regex]::Replace($text, $pattern, [Text.RegularExpressions.MatchEvaluator] { param($m) $m.Groups["indent"].Value + $code })

        Write-Host "Erreur volontaire injectée : $InjecterErreur" -ForegroundColor DarkGray
    }

    # Version exigée par #requires.
    if (-not [string]::IsNullOrWhiteSpace($RequiresVersion)) {
        $pattern = "(?m)^#requires -Version 5\.1"

        if (([regex]::Matches($text, $pattern)).Count -ne 1) {
            throw "PREPARATION : ligne #requires introuvable."
        }

        $text = [regex]::Replace($text, $pattern, "#requires -Version $RequiresVersion")
    }

    $target = Join-Path $state.WorkDirectory "download_deploy.ps1"

    # UTF-8 AVEC BOM, indispensable pour Windows PowerShell 5.1.
    [IO.File]::WriteAllText($target, $text, (New-Object Text.UTF8Encoding $true))

    return $target
}

<#
.SYNOPSIS
    Exécute le script testé dans un processus PowerShell séparé.

.DESCRIPTION
    powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ...
    -NonInteractive garantit qu'aucun test ne reste bloqué sur une saisie.
    La sortie est affichée (en retrait) et capturée.

.OUTPUTS
    Objet { ExitCode ; Output (texte complet) ; Lines }.
#>
function Invoke-ScriptUnderTest {
    param(
        [Parameter(Mandatory = $true)] [string] $ScriptPath,
        [string[]] $Arguments = @()
    )

    $state  = Get-TestState
    $config = $state.Config

    $powershell = Join-Path $PSHOME "powershell.exe"

    if (-not (Test-Path -LiteralPath $powershell)) {
        # Exécution depuis PowerShell 7 : on vise quand même Windows PowerShell 5.1.
        $powershell = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
    }

    # Délai maximal d'exécution du script (test-config : DelaiMaxScriptSecondes).
    $timeoutSeconds = 900
    if ($config.ContainsKey("DelaiMaxScriptSecondes") -and [int] $config.DelaiMaxScriptSecondes -gt 0) {
        $timeoutSeconds = [int] $config.DelaiMaxScriptSecondes
    }

    $allArguments = @("-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", $ScriptPath) + $Arguments

    # Start-Process concatène les arguments : chacun est mis entre guillemets.
    $argumentLine = ($allArguments | ForEach-Object { '"' + ([string] $_).Replace('"', '\"') + '"' }) -join " "

    Write-Host ""
    Write-Host "Exécution : download_deploy.ps1 $($Arguments -join ' ')" -ForegroundColor White
    Write-Host "(sortie affichée en direct ; délai maximal : $timeoutSeconds s)" -ForegroundColor DarkGray
    Write-Host ("-" * 70) -ForegroundColor DarkGray

    # La sortie est écrite dans des fichiers et relue au fil de l'eau :
    # elle s'affiche en direct, et le script peut être arrêté s'il dépasse
    # le délai maximal.
    $stdoutFile = Join-Path $state.WorkDirectory ("stdout-" + [guid]::NewGuid().ToString("N") + ".txt")
    $stderrFile = Join-Path $state.WorkDirectory ("stderr-" + [guid]::NewGuid().ToString("N") + ".txt")
    $encoding   = [Console]::OutputEncoding

    $process = Start-Process -FilePath $powershell -ArgumentList $argumentLine -NoNewWindow -PassThru `
        -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile

    # Sans cet accès, ExitCode peut rester vide (comportement connu de Start-Process).
    $null = $process.Handle

    $lines    = New-Object System.Collections.Generic.List[string]
    $readers  = @{}
    $pending  = @{ $stdoutFile = ""; $stderrFile = "" }
    $deadline = (Get-Date).AddSeconds($timeoutSeconds)
    $timedOut = $false

    # Lit et affiche les nouvelles lignes complètes d'un fichier de sortie.
    $readNew = {
        param([string] $File, [switch] $Final)

        if (-not $readers.ContainsKey($File)) {
            if (-not (Test-Path -LiteralPath $File)) { return }
            $stream = [IO.File]::Open($File, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete)
            $readers[$File] = New-Object IO.StreamReader($stream, $encoding)
        }

        $text = $pending[$File] + $readers[$File].ReadToEnd()
        $parts = $text -split "\r?\n"

        # La dernière partie est une ligne incomplète (ou vide) : elle est
        # gardée pour la lecture suivante, ou affichée à la fin si non vide.
        $last = $parts[-1]
        if ($parts.Count -gt 1) { $complete = @($parts[0..($parts.Count - 2)]) } else { $complete = @() }

        if ($Final) {
            $pending[$File] = ""
            if ($last -ne "") { $complete += $last }
        }
        else {
            $pending[$File] = $last
        }

        foreach ($line in $complete) {
            $lines.Add($line)
            Write-Host "  | $line" -ForegroundColor DarkGray
        }
    }

    try {
        while (-not $process.HasExited) {
            & $readNew $stdoutFile
            & $readNew $stderrFile

            if ((Get-Date) -gt $deadline) {
                $timedOut = $true
                # Arrêt du script et de ses processus enfants.
                & taskkill.exe /T /F /PID $process.Id 2>&1 | Out-Null
                break
            }

            Start-Sleep -Milliseconds 300
        }

        $process.WaitForExit()
        & $readNew $stdoutFile -Final
        & $readNew $stderrFile -Final
    }
    finally {
        foreach ($reader in $readers.Values) { $reader.Dispose() }
        Remove-Item -LiteralPath $stdoutFile, $stderrFile -Force -ErrorAction SilentlyContinue
    }

    if ($timedOut) { $exitCode = $null } else { $exitCode = $process.ExitCode }

    Write-Host ("-" * 70) -ForegroundColor DarkGray

    if ($timedOut) {
        Write-Host "download_deploy.ps1 arrêté : délai maximal de $timeoutSeconds s dépassé." -ForegroundColor Red
        Add-CheckResult -Success $false -Description "download_deploy.ps1 terminé dans le délai maximal ($timeoutSeconds s) - voir le journal du déploiement"
    }
    else {
        Write-Host "Code de sortie de download_deploy.ps1 : $exitCode" -ForegroundColor White
    }

    $state.CodeObtenu = $exitCode

    return [pscustomobject] @{
        ExitCode = $exitCode
        Output   = $lines -join [Environment]::NewLine
        Lines    = $lines.ToArray()
        TimedOut = $timedOut
    }
}

# ============================================================
# ASSERTIONS
# ============================================================
# Elles n'interrompent pas le test : chaque échec est mémorisé et
# affiché par Complete-Test.

<#
.SYNOPSIS
    Enregistre le résultat d'une vérification.
#>
function Add-CheckResult {
    param(
        [Parameter(Mandatory = $true)] [bool] $Success,
        [Parameter(Mandatory = $true)] [string] $Description
    )

    $state = Get-TestState

    if ($Success) {
        $state.Successes.Add($Description)
        Write-Host "  [OK]    $Description" -ForegroundColor Green
    }
    else {
        $state.Failures.Add($Description)
        Write-Host "  [ÉCHEC] $Description" -ForegroundColor Red
    }
}

<#
.SYNOPSIS
    Vérifie le code de sortie du script testé.
#>
function Assert-ExitCode {
    param(
        [Parameter(Mandatory = $true)] [object] $Result,
        [Parameter(Mandatory = $true)] [int] $Expected
    )

    Add-CheckResult -Success ($Result.ExitCode -eq $Expected) -Description "code de sortie $Expected (obtenu : $($Result.ExitCode))"
}

<#
.SYNOPSIS
    Vérifie que la sortie console contient le motif (expression régulière).
#>
function Assert-OutputMatch {
    param(
        [Parameter(Mandatory = $true)] [object] $Result,
        [Parameter(Mandatory = $true)] [string] $Pattern,
        [Parameter(Mandatory = $true)] [string] $Description
    )

    Add-CheckResult -Success ($Result.Output -match $Pattern) -Description "console : $Description"
}

<#
.SYNOPSIS
    Vérifie que la sortie console NE contient PAS le motif.
#>
function Assert-OutputNotMatch {
    param(
        [Parameter(Mandatory = $true)] [object] $Result,
        [Parameter(Mandatory = $true)] [string] $Pattern,
        [Parameter(Mandatory = $true)] [string] $Description
    )

    Add-CheckResult -Success (-not ($Result.Output -match $Pattern)) -Description "console : $Description"
}

<#
.SYNOPSIS
    Vérifie une condition quelconque.
#>
function Assert-Condition {
    param(
        [Parameter(Mandatory = $true)] [bool] $Condition,
        [Parameter(Mandatory = $true)] [string] $Description
    )

    Add-CheckResult -Success $Condition -Description $Description
}

<#
.SYNOPSIS
    Renvoie le journal le plus récent créé pendant ce test, ou $null.
#>
function Get-LatestLog {
    param([Parameter(Mandatory = $true)] [string] $Root)

    $state  = Get-TestState
    $logDir = Join-Path $Root "deployment-logs"

    if (-not (Test-Path -LiteralPath $logDir -PathType Container)) {
        return $null
    }

    return Get-ChildItem -LiteralPath $logDir -Filter "deployment-*.log" -File |
        Where-Object { $_.LastWriteTime -ge $state.StartTime.AddSeconds(-2) } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

<#
.SYNOPSIS
    Vérifie que le journal du test contient le motif.
#>
function Assert-LogMatch {
    param(
        [Parameter(Mandatory = $true)] [string] $Root,
        [Parameter(Mandatory = $true)] [string] $Pattern,
        [Parameter(Mandatory = $true)] [string] $Description
    )

    $log = Get-LatestLog -Root $Root

    if ($null -eq $log) {
        Add-CheckResult -Success $false -Description "journal : $Description (aucun journal créé pendant le test)"
        return
    }

    $content = [IO.File]::ReadAllText($log.FullName)
    Add-CheckResult -Success ($content -match $Pattern) -Description "journal : $Description"
}

<#
.SYNOPSIS
    Vérifie qu'aucun token (réel ou factice) n'apparaît dans la console,
    le journal ou le fichier d'état.
#>
function Assert-NoSecret {
    param(
        [Parameter(Mandatory = $true)] [object] $Result,
        [string] $Root
    )

    $secrets = @($script:FakeToken)

    foreach ($target in @("Process", "Machine")) {
        $value = [Environment]::GetEnvironmentVariable("ARTIFACTORY_TOKEN", $target)
        if (-not [string]::IsNullOrWhiteSpace($value)) { $secrets += $value }
    }

    $texts = @{ "console" = $Result.Output }

    if (-not [string]::IsNullOrWhiteSpace($Root)) {
        $log = Get-LatestLog -Root $Root

        if ($null -ne $log) {
            $texts["journal"] = [IO.File]::ReadAllText($log.FullName)

            $stateFile = [IO.Path]::ChangeExtension($log.FullName, ".state.json")
            if (Test-Path -LiteralPath $stateFile) {
                $texts["state.json"] = [IO.File]::ReadAllText($stateFile)
            }
        }
    }

    foreach ($place in $texts.Keys) {
        $leak = $false
        foreach ($secret in ($secrets | Select-Object -Unique)) {
            if ($texts[$place].Contains($secret)) { $leak = $true }
        }

        # Le message ne cite jamais la valeur du secret.
        Add-CheckResult -Success (-not $leak) -Description "$place : aucun token n'apparaît"
    }
}

# ============================================================
# ENVIRONNEMENT FACTICE
# ============================================================

<#
.SYNOPSIS
    Renvoie un petit exécutable « dormeur » compilé localement.
.DESCRIPTION
    Programme console qui attend indéfiniment. Copié sous les noms
    Socgen.TaskFlow.Runner.exe, Styx.HpcLite.Agent.exe... il simule des applications en cours
    d'exécution, sans aucun effet. Compilé une seule fois (Add-Type).
#>
<#
.SYNOPSIS
    Exécutable « instable » : démarre, attend 1 seconde, puis s'arrête.
.DESCRIPTION
    Simule une application qui démarre puis tombe (configuration invalide,
    port occupé...). Sert à vérifier le contrôle de stabilité du script.
    Compilé une seule fois (Add-Type).
#>
function Get-ShortLivedExecutable {
    $toolsDir = Join-Path $env:TEMP "styx-tests\_tools"
    $exe      = Join-Path $toolsDir "short-lived.exe"

    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {
        New-Item -Path $toolsDir -ItemType Directory -Force | Out-Null

        Add-Type -OutputAssembly $exe -OutputType ConsoleApplication -TypeDefinition @"
public static class ShortLived
{
    public static void Main()
    {
        System.Threading.Thread.Sleep(1000);
    }
}
"@
    }

    return $exe
}

function Get-SleeperExecutable {
    $toolsDir = Join-Path $env:TEMP "styx-tests\_tools"
    $sleeper  = Join-Path $toolsDir "sleeper.exe"

    if (-not (Test-Path -LiteralPath $sleeper -PathType Leaf)) {
        New-Item -Path $toolsDir -ItemType Directory -Force | Out-Null

        Add-Type -OutputAssembly $sleeper -OutputType ConsoleApplication -TypeDefinition @"
public static class Sleeper
{
    public static void Main()
    {
        System.Threading.Thread.Sleep(System.Threading.Timeout.Infinite);
    }
}
"@
    }

    return $sleeper
}

<#
.SYNOPSIS
    Crée une arborescence factice complète pour le scénario.

.DESCRIPTION
    <RacineTestsAuto>\<scénario>\
        taskflow\<ExecutableTaskflow>, version.txt
        api\web.config, version.txt
        HpcLite\version.txt
        HpcLite\agent\<ExecutableAgent>
        HpcLite\runner\<ExecutableRunner>
        HpcLite\scheduler\<ExecutableScheduler>

    Les .exe sont des copies du « dormeur » : ils peuvent être lancés.
    Chaque version.txt contient « ancienne-version ».
    Le dossier est supprimé (et ses processus arrêtés) au nettoyage.

.PARAMETER Omettre
    Éléments à ne pas créer : taskflow, api, HpcLite, agent, runner,
    scheduler, taskflow.exe, agent.exe, runner.exe, scheduler.exe.

.OUTPUTS
    Objet { Root ; TaskflowDir ; ApiDir ; HpcLiteDir ; AgentDir ; RunnerDir ;
            SchedulerDir ; TaskflowExe ; AgentExe ; RunnerExe ; SchedulerExe }
#>
function New-FakeEnvironment {
    param([string[]] $Omettre = @())

    $state  = Get-TestState
    $config = $state.Config

    $autoRoot = [IO.Path]::GetFullPath($config.RacineTestsAuto).TrimEnd("\")
    $root     = Join-Path $autoRoot $state.Scenario

    # Garde-fou : on ne travaille que sous RacineTestsAuto, sur D:.
    if (-not $autoRoot.StartsWith("D:\", [StringComparison]::OrdinalIgnoreCase) -or $autoRoot.Length -le 3) {
        throw "PREREQUIS : RacineTestsAuto doit être un sous-dossier de D:\ (valeur : $autoRoot)."
    }

    if (Test-Path -LiteralPath $root) {
        Stop-ProcessesUnderPath -Root $root
        Remove-Item -LiteralPath $root -Recurse -Force
    }

    $state.FakeRoots.Add($root)

    $fake = [pscustomobject] @{
        Root         = $root
        TaskflowDir  = Join-Path $root "taskflow"
        ApiDir       = Join-Path $root "api"
        HpcLiteDir   = Join-Path $root "HpcLite"
        AgentDir     = Join-Path $root "HpcLite\agent"
        RunnerDir    = Join-Path $root "HpcLite\runner"
        SchedulerDir = Join-Path $root "HpcLite\scheduler"
        TaskflowExe  = Join-Path $root "taskflow\$($config.ExecutableTaskflow)"
        AgentExe     = Join-Path $root "HpcLite\agent\$($config.ExecutableAgent)"
        RunnerExe    = Join-Path $root "HpcLite\runner\$($config.ExecutableRunner)"
        SchedulerExe = Join-Path $root "HpcLite\scheduler\$($config.ExecutableScheduler)"
    }

    New-Item -Path $root -ItemType Directory -Force | Out-Null

    $sleeper = Get-SleeperExecutable

    $directories = [ordered] @{
        "taskflow"  = $fake.TaskflowDir
        "api"       = $fake.ApiDir
        "HpcLite"   = $fake.HpcLiteDir
        "agent"     = $fake.AgentDir
        "runner"    = $fake.RunnerDir
        "scheduler" = $fake.SchedulerDir
    }

    foreach ($key in $directories.Keys) {
        $isOmitted = $Omettre -contains $key
        $parentOmitted = ($key -in @("agent", "runner", "scheduler")) -and ($Omettre -contains "HpcLite")

        if (-not $isOmitted -and -not $parentOmitted) {
            New-Item -Path $directories[$key] -ItemType Directory -Force | Out-Null
        }
    }

    $executables = [ordered] @{
        "taskflow.exe"  = $fake.TaskflowExe
        "agent.exe"     = $fake.AgentExe
        "runner.exe"    = $fake.RunnerExe
        "scheduler.exe" = $fake.SchedulerExe
    }

    foreach ($key in $executables.Keys) {
        $path = $executables[$key]

        if ($Omettre -notcontains $key -and (Test-Path -LiteralPath (Split-Path -Parent $path))) {
            Copy-Item -LiteralPath $sleeper -Destination $path -Force
        }
    }

    foreach ($directory in @($fake.TaskflowDir, $fake.ApiDir, $fake.HpcLiteDir)) {
        if (Test-Path -LiteralPath $directory) {
            Set-Content -LiteralPath (Join-Path $directory "version.txt") -Value "ancienne-version" -Encoding ASCII
        }
    }

    if (Test-Path -LiteralPath $fake.ApiDir) {
        Set-Content -LiteralPath (Join-Path $fake.ApiDir "web.config") -Value "<configuration />" -Encoding ASCII
    }

    Write-Host "Environnement factice créé : $root" -ForegroundColor DarkGray

    return $fake
}

<#
.SYNOPSIS
    Démarre un processus factice depuis un exécutable (copie du dormeur).
.OUTPUTS
    Le processus démarré.
#>
function Start-FakeProcess {
    param(
        [Parameter(Mandatory = $true)] [string] $ExecutablePath,
        [int] $Count = 1
    )

    $state = Get-TestState
    $processes = @()

    for ($i = 0; $i -lt $Count; $i++) {
        $process = Start-Process -FilePath $ExecutablePath -WindowStyle Hidden -PassThru
        $state.StartedProcessIds.Add($process.Id)
        $processes += $process
    }

    # Laisse le temps à Win32_Process de voir les nouveaux processus.
    Start-Sleep -Milliseconds 800

    Write-Host "Processus factice(s) démarré(s) : $Count x $ExecutablePath" -ForegroundColor DarkGray

    return $processes
}

<#
.SYNOPSIS
    Nombre de processus lancés depuis exactement ce chemin.
#>
function Get-ProcessCountByPath {
    param([Parameter(Mandatory = $true)] [string] $ExecutablePath)

    $expected = [IO.Path]::GetFullPath($ExecutablePath)

    return @(
        Get-CimInstance -ClassName Win32_Process |
            Where-Object { $null -ne $_.ExecutablePath -and $_.ExecutablePath.Equals($expected, [StringComparison]::OrdinalIgnoreCase) }
    ).Count
}

<#
.SYNOPSIS
    Arrête tous les processus dont l'exécutable est sous ce dossier.
.DESCRIPTION
    Utilisé uniquement sur des dossiers factices créés par le test.
#>
function Stop-ProcessesUnderPath {
    param([Parameter(Mandatory = $true)] [string] $Root)

    $prefix = [IO.Path]::GetFullPath($Root).TrimEnd("\") + "\"

    Get-CimInstance -ClassName Win32_Process |
        Where-Object { $null -ne $_.ExecutablePath -and $_.ExecutablePath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

    Start-Sleep -Milliseconds 300
}

<#
.SYNOPSIS
    Empreinte d'un dossier (chemins, tailles, dates) pour vérifier qu'il
    n'a pas été modifié.
#>
function Get-DirectorySnapshot {
    param([Parameter(Mandatory = $true)] [string] $Path)

    $base = [IO.Path]::GetFullPath($Path).TrimEnd("\").Length + 1

    return (@(
        Get-ChildItem -LiteralPath $Path -File -Recurse -Force |
            Sort-Object FullName |
            ForEach-Object { "$($_.FullName.Substring($base))|$($_.Length)|$($_.LastWriteTimeUtc.Ticks)" }
    ) -join "`n")
}

<#
.SYNOPSIS
    Écrit un marqueur version.txt dans un dossier.
.DESCRIPTION
    Le contenu d'origine (ou l'absence de fichier) est restauré au nettoyage.
#>
function Set-VersionMarker {
    param(
        [Parameter(Mandatory = $true)] [string] $Directory,
        [Parameter(Mandatory = $true)] [string] $Value
    )

    $file = Join-Path $Directory "version.txt"

    # Contenu d'origine mémorisé (une seule fois par dossier) pour restauration.
    $state = Get-TestState
    if (@($state.VersionMarkers | Where-Object { $_.Directory -eq $Directory }).Count -eq 0) {
        $original = $null
        if (Test-Path -LiteralPath $file -PathType Leaf) { $original = [IO.File]::ReadAllBytes($file) }
        $state.VersionMarkers.Add([pscustomobject] @{ Directory = $Directory; Original = $original })
    }

    Set-Content -LiteralPath $file -Value $Value -Encoding ASCII
}

<#
.SYNOPSIS
    Demande la remise du pool IIS dans cet état à la fin du test.
.DESCRIPTION
    Pour les tests qui démarrent ou arrêtent le pool sans
    -EnvironnementReel. Le premier appel seul est retenu.
#>
function Register-PoolRestore {
    param([Parameter(Mandatory = $true)] [ValidateSet("Started", "Stopped")] [string] $State)

    $testState = Get-TestState
    if ($null -eq $testState.PoolRestore) { $testState.PoolRestore = $State }
}

<#
.SYNOPSIS
    Lit le marqueur version.txt d'un dossier ($null s'il est absent).
#>
function Get-VersionMarker {
    param([Parameter(Mandatory = $true)] [string] $Directory)

    $file = Join-Path $Directory "version.txt"

    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        return $null
    }

    return ([IO.File]::ReadAllText($file)).Trim()
}

# ============================================================
# PACKAGES DE TEST
# ============================================================

<#
.SYNOPSIS
    Chemin de l'archive applicative DANS le .nupkg, au format des entrées
    ZIP (séparateur « / »), ex. « content/styx_publish.zip ».
.DESCRIPTION
    Lu dans test-config.psd1 (ArchiveApplicative) ; valeur du script par
    défaut si la clé est absente.
#>
function Get-ApplicationArchiveEntryName {
    $config = Get-TestConfig
    $value  = "content\styx_publish.zip"

    if ($config.ContainsKey("ArchiveApplicative") -and -not [string]::IsNullOrWhiteSpace($config.ArchiveApplicative)) {
        $value = $config.ArchiveApplicative
    }

    return $value.Replace("\", "/").TrimStart("/")
}

<#
.SYNOPSIS
    Écrit une archive ZIP dans un flux à partir d'une liste d'entrées.
.PARAMETER Entries
    Dictionnaire ordonné : nom d'entrée -> contenu (string ou byte[]).
    Un nom terminé par « / » ou « \ » crée une entrée de dossier vide.
#>
function Write-ZipEntries {
    param(
        [Parameter(Mandatory = $true)] [IO.Stream] $Stream,
        [Parameter(Mandatory = $true)] [System.Collections.IDictionary] $Entries
    )

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    # leaveOpen = $true : le flux appartient à l'appelant.
    $zip = New-Object IO.Compression.ZipArchive($Stream, [IO.Compression.ZipArchiveMode]::Create, $true)

    try {
        foreach ($name in $Entries.Keys) {
            $entry = $zip.CreateEntry($name)

            if ($name.EndsWith("/") -or $name.EndsWith("\")) { continue }

            # Affectations dans chaque branche : « $x = if (...) { $octets } »
            # déroulerait le tableau d'octets dans le pipeline.
            $content = $Entries[$name]
            if ($content -is [byte[]]) { $bytes = $content }
            else { $bytes = [Text.Encoding]::UTF8.GetBytes([string] $content) }

            $entryStream = $entry.Open()
            try { $entryStream.Write($bytes, 0, $bytes.Length) } finally { $entryStream.Dispose() }
        }
    }
    finally { $zip.Dispose() }
}

<#
.SYNOPSIS
    Écrit une archive ZIP (fichier) à partir d'une liste d'entrées.
#>
function Write-ZipFile {
    param(
        [Parameter(Mandatory = $true)] [string] $Path,
        [Parameter(Mandatory = $true)] [System.Collections.IDictionary] $Entries
    )

    $stream = [IO.File]::Open($Path, [IO.FileMode]::Create)
    try { Write-ZipEntries -Stream $stream -Entries $Entries }
    finally { $stream.Dispose() }
}

<#
.SYNOPSIS
    Construit une archive ZIP en mémoire et renvoie ses octets.
#>
function Get-ZipBytes {
    param([Parameter(Mandatory = $true)] [System.Collections.IDictionary] $Entries)

    $memory = New-Object IO.MemoryStream
    try {
        Write-ZipEntries -Stream $memory -Entries $Entries
        # La virgule empêche PowerShell de dérouler le tableau d'octets.
        return , $memory.ToArray()
    }
    finally { $memory.Dispose() }
}

<#
.SYNOPSIS
    Construit un package de test (.nupkg) dans le dossier de travail, avec
    la MÊME structure que le vrai package Styx.Publish.

.DESCRIPTION
    Structure du vrai package (reproduite ici) :

        Styx.Publish.nupkg
        ├── Styx.Publish.nuspec, [Content_Types].xml
        └── content/styx_publish.zip          archive applicative
            ├── taskflow\  <ExecutableTaskflow>, appsettings.json, version.txt
            ├── api\       Styx.Api.dll, web.config, version.txt
            ├── hpclite\   version.txt, agent\<ExecutableAgent>,
            │              runner\<ExecutableRunner>, scheduler\<ExecutableScheduler>
            └── app\       index.html (dossier ignoré par le script)

    Comme dans le vrai package, les noms de l'archive applicative utilisent
    le séparateur « \ » (archive créée sous Windows). Les paramètres, eux,
    s'écrivent avec « / » : ils sont convertis.

    Chaque version.txt contient -Version (« nouvelle-version » par défaut).

.PARAMETER Composants
    taskflow, api, hpclite (tous par défaut).

.PARAMETER SansDossierApp
    N'ajoute pas le dossier app\ à l'archive applicative.

.PARAMETER ComposantsVides
    Composants présents uniquement sous forme de dossier vide.

.PARAMETER EntreesOmises
    Entrées de l'archive applicative à retirer
    (ex. 'taskflow/Socgen.TaskFlow.Runner.exe').

.PARAMETER EntreesSupplementaires
    Entrées à ajouter DANS l'archive applicative : nom -> contenu
    (ex. 'api/fichier.txt', '../../evil.txt').

.PARAMETER EntreesNuGetSupplementaires
    Entrées à ajouter dans le .nupkg lui-même, hors archive applicative
    (ex. 'content/mon%20fichier.txt', 'content/../../evil.txt').

.PARAMETER SansArchiveApplicative
    Le .nupkg ne contient pas l'archive applicative.

.PARAMETER ArchiveApplicativeCorrompue
    L'archive applicative est un fichier texte, pas un ZIP.

.PARAMETER ExecutablesLancables
    Les .exe du package sont des copies du dormeur (lançables). Nécessaire
    pour un déploiement complet en mode test (redémarrage des processus).

.PARAMETER ExecutablesInstables
    Composants (taskflow, agent, scheduler) dont l'exécutable démarre puis
    s'arrête après 1 seconde (contrôle de stabilité). Implique
    -ExecutablesLancables pour les autres.

.OUTPUTS
    Chemin complet du package.
#>
function New-TestPackage {
    param(
        [string] $Nom = "package-test.nupkg",
        [string[]] $Composants = @("taskflow", "api", "hpclite"),
        [switch] $SansDossierApp,
        [string[]] $ComposantsVides = @(),
        [string[]] $EntreesOmises = @(),
        [hashtable] $EntreesSupplementaires = @{},
        [hashtable] $EntreesNuGetSupplementaires = @{},
        [switch] $SansArchiveApplicative,
        [switch] $ArchiveApplicativeCorrompue,
        [string] $Version = "nouvelle-version",
        [switch] $ExecutablesLancables,
        [string[]] $ExecutablesInstables = @()
    )

    $state  = Get-TestState
    $config = $state.Config
    $path   = Join-Path $state.WorkDirectory $Nom

    if ($ExecutablesLancables -or $ExecutablesInstables.Count -gt 0) { $exeContent = [IO.File]::ReadAllBytes((Get-SleeperExecutable)) }
    else { $exeContent = "executable factice" }

    if ($ExecutablesInstables.Count -gt 0) { $unstableContent = [IO.File]::ReadAllBytes((Get-ShortLivedExecutable)) }
    else { $unstableContent = $null }

    # Contenu de l'exécutable d'un composant (instable ou non).
    $exeFor = {
        param([string] $Component)
        if ($ExecutablesInstables -contains $Component) { , $unstableContent } else { , $exeContent }
    }

    # --- Archive applicative (noms logiques avec « / ») ---
    $app = [ordered] @{}

    if ($Composants -contains "taskflow") {
        $app["taskflow/$($config.ExecutableTaskflow)"] = (& $exeFor "taskflow")
        $app["taskflow/appsettings.json"] = "{}"
        $app["taskflow/version.txt"] = $Version
    }

    if ($Composants -contains "api") {
        $app["api/Styx.Api.dll"] = "bibliotheque factice"
        $app["api/web.config"] = "<configuration />"
        $app["api/version.txt"] = $Version
    }

    if ($Composants -contains "hpclite") {
        $app["hpclite/version.txt"] = $Version
        $app["hpclite/agent/$($config.ExecutableAgent)"] = (& $exeFor "agent")
        $app["hpclite/runner/$($config.ExecutableRunner)"] = $exeContent
        $app["hpclite/scheduler/$($config.ExecutableScheduler)"] = (& $exeFor "scheduler")
    }

    if (-not $SansDossierApp) {
        $app["app/index.html"] = "<html></html>"
    }

    foreach ($component in $ComposantsVides) {
        foreach ($key in @($app.Keys)) {
            if ($key.StartsWith("$component/")) { $app.Remove($key) }
        }

        $app["$component/"] = ""
    }

    foreach ($name in $EntreesOmises) {
        if (-not $app.Contains($name)) {
            throw "PREPARATION : entrée à omettre inconnue : $name"
        }

        $app.Remove($name)
    }

    foreach ($name in $EntreesSupplementaires.Keys) {
        $app[$name] = $EntreesSupplementaires[$name]
    }

    # Séparateur Windows « \ », comme dans le vrai package.
    $appEntries = [ordered] @{}
    foreach ($name in $app.Keys) { $appEntries[$name.Replace("/", "\")] = $app[$name] }

    # --- Package NuGet ---
    $entries = [ordered] @{
        "Styx.Publish.nuspec"  = "<package><metadata><id>Styx.Publish</id></metadata></package>"
        "[Content_Types].xml"  = "<Types />"
    }

    if ($ArchiveApplicativeCorrompue) {
        $entries[(Get-ApplicationArchiveEntryName)] = "Ceci n'est pas une archive ZIP."
    }
    elseif (-not $SansArchiveApplicative) {
        $appBytes = Get-ZipBytes -Entries $appEntries
        $entries[(Get-ApplicationArchiveEntryName)] = $appBytes
    }

    foreach ($name in $EntreesNuGetSupplementaires.Keys) {
        $entries[$name] = $EntreesNuGetSupplementaires[$name]
    }

    Write-ZipFile -Path $path -Entries $entries

    Write-Host "Package de test créé : $path ($($appEntries.Count) entrées applicatives)" -ForegroundColor DarkGray

    return $path
}

<#
.SYNOPSIS
    Crée un faux package qui n'est pas une archive ZIP.
#>
function New-CorruptPackage {
    param([string] $Nom = "package-corrompu.nupkg")

    $path = Join-Path (Get-TestState).WorkDirectory $Nom
    Set-Content -LiteralPath $path -Value "Ceci n'est pas une archive ZIP." -Encoding ASCII

    return $path
}

<#
.SYNOPSIS
    Copie dans un flux le contenu d'une entrée ZIP.
#>
function Copy-ZipEntryContent {
    param(
        [Parameter(Mandatory = $true)] $Source,
        [Parameter(Mandatory = $true)] $Target
    )

    $in  = $Source.Open()
    $out = $Target.Open()
    try { $in.CopyTo($out) } finally { $in.Dispose(); $out.Dispose() }
}

<#
.SYNOPSIS
    Extrait l'archive applicative d'un .nupkg dans un fichier temporaire
    du dossier de travail et renvoie son chemin.
#>
function Export-ApplicationArchive {
    param([Parameter(Mandatory = $true)] [string] $Package)

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $entryName = Get-ApplicationArchiveEntryName
    $target    = Join-Path (Get-TestState).WorkDirectory ("archive-" + [guid]::NewGuid().ToString("N") + ".zip")
    $zip       = [IO.Compression.ZipFile]::OpenRead($Package)

    try {
        $entry = $zip.Entries | Where-Object {
            [Uri]::UnescapeDataString($_.FullName).Replace("\", "/") -eq $entryName
        } | Select-Object -First 1

        if ($null -eq $entry) {
            throw "PREPARATION : archive applicative '$entryName' introuvable dans le package : $Package"
        }

        [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $target, $true)
    }
    finally { $zip.Dispose() }

    return $target
}

<#
.SYNOPSIS
    Copie le VRAI package (PackageReel) en y ajoutant un marqueur de version.

.DESCRIPTION
    Toutes les entrées du vrai package sont recopiées telles quelles (noms
    encodés compris), sauf l'archive applicative, qui est reconstruite :
    pour chaque composant présent à sa racine (taskflow, api, hpclite), une
    entrée <composant>\version.txt = -Version est ajoutée (ou remplacée),
    avec le même séparateur que les autres entrées. Le vrai package n'est
    jamais modifié. Les copies passent par des fichiers temporaires du
    dossier de travail (pas de chargement complet en mémoire).

.OUTPUTS
    Chemin du package marqué, dans le dossier de travail.
#>
function New-PackageFromReal {
    param(
        [string] $Nom = "package-reel-marque.nupkg",
        [string] $Version = "nouvelle-version"
    )

    $state  = Get-TestState
    $source = $state.Config.PackageReel

    if ([string]::IsNullOrWhiteSpace($source) -or -not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "PREREQUIS : vrai package introuvable (PackageReel dans test-config.psd1) : $source"
    }

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $target       = Join-Path $state.WorkDirectory $Nom
    $archiveName  = Get-ApplicationArchiveEntryName

    # 1. Archive applicative d'origine -> fichier temporaire.
    $originalArchive = Export-ApplicationArchive -Package $source
    $markedArchive   = Join-Path $state.WorkDirectory ("archive-marquee-" + [guid]::NewGuid().ToString("N") + ".zip")

    try {
        # 2. Archive applicative marquée.
        $in  = [IO.Compression.ZipFile]::OpenRead($originalArchive)
        $out = [IO.Compression.ZipFile]::Open($markedArchive, [IO.Compression.ZipArchiveMode]::Create)

        try {
            $components = @()
            $separator  = "/"

            foreach ($entry in $in.Entries) {
                $name = $entry.FullName
                if ($name.Contains("\")) { $separator = "\" }

                $first = ($name -split '[\\/]')[0].ToLowerInvariant()
                if (@("taskflow", "api", "hpclite") -contains $first -and $components -notcontains $first) {
                    $components += $first
                }

                if ($name -match '^(taskflow|api|hpclite)[\\/]version\.txt$') { continue }

                $newEntry = $out.CreateEntry($name)
                if ($name.EndsWith("/") -or $name.EndsWith("\")) { continue }
                Copy-ZipEntryContent -Source $entry -Target $newEntry
            }

            foreach ($component in $components) {
                $marker = $out.CreateEntry("$component$($separator)version.txt")
                $bytes  = [Text.Encoding]::ASCII.GetBytes($Version)
                $stream = $marker.Open()
                try { $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Dispose() }
            }
        }
        finally { $out.Dispose(); $in.Dispose() }

        # 3. Package marqué : entrées d'origine + archive marquée.
        $sourceZip = [IO.Compression.ZipFile]::OpenRead($source)
        $targetZip = [IO.Compression.ZipFile]::Open($target, [IO.Compression.ZipArchiveMode]::Create)

        try {
            foreach ($entry in $sourceZip.Entries) {
                $newEntry = $targetZip.CreateEntry($entry.FullName)

                if ([Uri]::UnescapeDataString($entry.FullName).Replace("\", "/") -eq $archiveName) {
                    $fileStream = [IO.File]::OpenRead($markedArchive)
                    $entryStream = $newEntry.Open()
                    try { $fileStream.CopyTo($entryStream) } finally { $entryStream.Dispose(); $fileStream.Dispose() }
                    continue
                }

                if ($entry.FullName.EndsWith("/")) { continue }
                Copy-ZipEntryContent -Source $entry -Target $newEntry
            }
        }
        finally { $targetZip.Dispose(); $sourceZip.Dispose() }
    }
    finally {
        Remove-Item -LiteralPath $originalArchive, $markedArchive -Force -ErrorAction SilentlyContinue
    }

    Write-Host "Package réel marqué ($Version) : $target" -ForegroundColor DarkGray

    return $target
}

<#
.SYNOPSIS
    Nombre de fichiers d'un composant dans l'archive applicative d'un
    package (<composant>\...).
#>
function Get-PackageFileCount {
    param(
        [Parameter(Mandatory = $true)] [string] $Package,
        [Parameter(Mandatory = $true)] [string] $Component
    )

    $archive = Export-ApplicationArchive -Package $Package

    try {
        $zip = [IO.Compression.ZipFile]::OpenRead($archive)

        try {
            return @(
                $zip.Entries | Where-Object {
                    $name = $_.FullName.Replace("\", "/")
                    $name.StartsWith("$Component/", [StringComparison]::OrdinalIgnoreCase) -and -not $name.EndsWith("/")
                }
            ).Count
        }
        finally { $zip.Dispose() }
    }
    finally {
        Remove-Item -LiteralPath $archive -Force -ErrorAction SilentlyContinue
    }
}

# ============================================================
# ENVIRONNEMENT RÉEL : SERVICES ET IIS
# ============================================================

<#
.SYNOPSIS
    Vérifie que l'environnement réel de test est complet et n'est PAS la
    production. Toute anomalie rend le test « non exécuté ».
#>
function Assert-RealEnvironmentIsSafe {
    $config = Get-TestConfig

    $real = [IO.Path]::GetFullPath($config.RacineReelle).TrimEnd("\")
    $prod = [IO.Path]::GetFullPath($config.RacineProduction).TrimEnd("\")

    if ($real.Equals($prod, [StringComparison]::OrdinalIgnoreCase)) {
        throw "PREREQUIS : RacineReelle et RacineProduction désignent le même dossier. Les tests destructifs sont refusés."
    }

    foreach ($relative in @("taskflow", "api", "HpcLite\agent", "HpcLite\runner", "HpcLite\scheduler")) {
        $path = Join-Path $real $relative

        if (-not (Test-Path -LiteralPath $path -PathType Container)) {
            throw "PREREQUIS : environnement réel incomplet, dossier absent : $path"
        }
    }

    # Chaque service doit exécuter un binaire de RacineReelle.
    foreach ($serviceName in (Get-ConfiguredServiceNames)) {
        $cim = Get-CimInstance -ClassName Win32_Service -Filter "Name = '$($serviceName.Replace("'", "''"))'"

        if ($null -eq $cim) {
            throw "PREREQUIS : service '$serviceName' introuvable."
        }

        $pathName = $cim.PathName.Trim('"', ' ')

        if (-not $pathName.StartsWith($real + "\", [StringComparison]::OrdinalIgnoreCase)) {
            throw "PREREQUIS : le service '$serviceName' n'exécute pas un binaire de $real (PathName : $($cim.PathName)). Les tests réels sont refusés."
        }
    }
}

<#
.SYNOPSIS
    Indique si un pool IIS existe.
#>
function Test-IisPoolExists {
    param([Parameter(Mandatory = $true)] [string] $Name)

    $appcmd = Get-AppCmdPath
    if (-not (Test-Path -LiteralPath $appcmd)) { return $false }

    $output = & $appcmd list apppool "/apppool.name:$Name" 2>&1
    return ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace(($output -join "")))
}

<#
.SYNOPSIS
    Lit la configuration de PRODUCTION dans le download_deploy.ps1 de
    production (racine des tests) : noms des services, du pool IIS et des
    exécutables, tels qu'ils seront utilisés sur le serveur cible.
.DESCRIPTION
    Sert au jalon 19 : la production est contrôlée avec SES noms
    (TaskFlow.Runner, HpcLite.Agent...), jamais avec ceux de test-config.psd1
    (services et pool de TEST). Le script est seulement analysé (AST), pas
    exécuté.
.OUTPUTS
    Hashtable : ServiceTaskflow, ServiceAgent, ServiceScheduler, PoolIis,
    ExecutableTaskflow, ExecutableAgent, ExecutableScheduler,
    DossierAgent, DossierScheduler.
#>
function Get-ProductionSettings {
    $script = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\download_deploy.ps1"))

    if (-not (Test-Path -LiteralPath $script -PathType Leaf)) {
        throw "PREREQUIS : script de production introuvable : $script (lancer _tools\Build-JalonVersions.ps1)."
    }

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($script, [ref] $tokens, [ref] $errors)

    $values = @{}
    foreach ($assignment in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.AssignmentStatementAst] }, $false)) {
        if ($assignment.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
            $assignment.Right -is [System.Management.Automation.Language.CommandExpressionAst] -and
            $assignment.Right.Expression -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
            $name = $assignment.Left.VariablePath.UserPath
            if (-not $values.ContainsKey($name)) { $values[$name] = $assignment.Right.Expression.Value }
        }
    }

    $map = [ordered] @{
        ServiceTaskflow     = "TaskflowServiceName"
        ServiceAgent        = "HpcLiteAgentServiceName"
        ServiceScheduler    = "HpcLiteSchedulerServiceName"
        PoolIis             = "StxApplicationPoolName"
        ExecutableTaskflow  = "TaskflowExecutableRelativePath"
        ExecutableAgent     = "HpcLiteAgentExecutableName"
        ExecutableScheduler = "HpcLiteSchedulerExecutableName"
        DossierAgent        = "HpcLiteAgentFolder"
        DossierScheduler    = "HpcLiteSchedulerFolder"
    }

    $settings = @{}
    foreach ($key in $map.Keys) {
        if (-not $values.ContainsKey($map[$key])) {
            throw "PREREQUIS : `$$($map[$key]) introuvable dans $script."
        }
        $settings[$key] = $values[$map[$key]]
    }

    return $settings
}

<#
.SYNOPSIS
    État des applications de PRODUCTION (noms lus dans le script de
    production), sous forme de texte comparable avant / après.
#>
function Get-ProductionStateText {
    $prod = Get-ProductionSettings
    $parts = foreach ($name in @($prod.ServiceTaskflow, $prod.ServiceAgent, $prod.ServiceScheduler)) {
        $service = Get-Service -Name $name -ErrorAction SilentlyContinue
        if ($null -eq $service) { "$name=Absent" } else { "$name=$($service.Status)" }
    }
    $parts += "Pool $($prod.PoolIis)=$(Get-PoolState -Name $prod.PoolIis)"
    return ($parts -join ", ")
}

<#
.SYNOPSIS
    État d'un pool IIS : Started, Stopped ou Unknown.
#>
function Get-PoolState {
    param([string] $Name = (Get-TestConfig).PoolIis)

    $output = (& (Get-AppCmdPath) list apppool "/apppool.name:$Name" 2>&1) -join " "

    if ($output -match "state:Started") { return "Started" }
    if ($output -match "state:Stopped") { return "Stopped" }
    return "Unknown"
}

<#
.SYNOPSIS
    Démarre ou arrête le pool IIS et attend l'état demandé.
#>
function Set-PoolState {
    param(
        [Parameter(Mandatory = $true)] [ValidateSet("Started", "Stopped")] [string] $State,
        [string] $Name = (Get-TestConfig).PoolIis
    )

    if ((Get-PoolState -Name $Name) -eq $State) { return }

    $verb = if ($State -eq "Started") { "start" } else { "stop" }
    & (Get-AppCmdPath) $verb apppool "/apppool.name:$Name" | Out-Null

    $deadline = (Get-Date).AddSeconds(60)
    while ((Get-PoolState -Name $Name) -ne $State -and (Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 1
    }

    if ((Get-PoolState -Name $Name) -ne $State) {
        throw "Le pool IIS '$Name' n'a pas atteint l'état $State."
    }
}

<#
.SYNOPSIS
    Nombre de processus w3wp.exe du pool.
#>
function Get-W3wpCount {
    param([string] $Name = (Get-TestConfig).PoolIis)

    return @(
        Get-CimInstance -ClassName Win32_Process -Filter "Name = 'w3wp.exe'" |
            Where-Object { $null -ne $_.CommandLine -and $_.CommandLine -like "*-ap `"$Name`"*" }
    ).Count
}

<#
.SYNOPSIS
    État d'un service : Running, Stopped...
#>
function Get-ServiceStatus {
    param([Parameter(Mandatory = $true)] [string] $Name)

    return [string] (Get-Service -Name $Name -ErrorAction Stop).Status
}

<#
.SYNOPSIS
    Démarre ou arrête un service et attend l'état demandé.
#>
function Set-ServiceStatus {
    param(
        [Parameter(Mandatory = $true)] [string] $Name,
        [Parameter(Mandatory = $true)] [ValidateSet("Running", "Stopped")] [string] $Status
    )

    $service = Get-Service -Name $Name -ErrorAction Stop

    if ([string] $service.Status -eq $Status) { return }

    if ($Status -eq "Running") { Start-Service -Name $Name -ErrorAction Stop }
    else { Stop-Service -Name $Name -Force -ErrorAction Stop }

    $service.WaitForStatus($Status, [TimeSpan]::FromSeconds(60))
}

<#
.SYNOPSIS
    Date de démarrage du processus d'un service ($null s'il est arrêté).
.DESCRIPTION
    Permet de vérifier qu'un service n'a PAS été redémarré.
#>
function Get-ServiceProcessStartTime {
    param([Parameter(Mandatory = $true)] [string] $Name)

    $cim = Get-CimInstance -ClassName Win32_Service -Filter "Name = '$($Name.Replace("'", "''"))'"

    if ($null -eq $cim -or $cim.ProcessId -eq 0) { return $null }

    return (Get-Process -Id $cim.ProcessId -ErrorAction SilentlyContinue).StartTime
}

<#
.SYNOPSIS
    État des trois services et du pool IIS.
.OUTPUTS
    Objet { Taskflow ; Agent ; Scheduler ; Pool }.
#>
function Get-ApplicationState {
    $config = Get-TestConfig

    return [pscustomobject] @{
        Taskflow  = Get-ServiceStatus -Name $config.ServiceTaskflow
        Agent     = Get-ServiceStatus -Name $config.ServiceAgent
        Scheduler = Get-ServiceStatus -Name $config.ServiceScheduler
        Pool      = Get-PoolState
    }
}

<#
.SYNOPSIS
    Texte lisible d'un état d'applications.
#>
function Format-ApplicationState {
    param([Parameter(Mandatory = $true)] [object] $State)

    return "Taskflow=$($State.Taskflow), Agent=$($State.Agent), Scheduler=$($State.Scheduler), Pool=$($State.Pool)"
}

<#
.SYNOPSIS
    Remet les services et le pool dans l'état donné.
#>
function Restore-ApplicationState {
    param([Parameter(Mandatory = $true)] [object] $State)

    $config = Get-TestConfig

    # Ordre : Scheduler avant Agent, comme le script de déploiement.
    # Un état transitoire mémorisé (StartPending...) est assimilé à Running.
    foreach ($pair in @(
            @($config.ServiceTaskflow,  $State.Taskflow),
            @($config.ServiceScheduler, $State.Scheduler),
            @($config.ServiceAgent,     $State.Agent))) {
        $target = if ($pair[1] -eq "Stopped") { "Stopped" } else { "Running" }
        Set-ServiceStatus -Name $pair[0] -Status $target
    }

    if ($State.Pool -in @("Started", "Stopped")) {
        Set-PoolState -State $State.Pool
    }

    Write-Host "État des applications restauré : $(Format-ApplicationState -State $State)" -ForegroundColor DarkGray
}

<#
.SYNOPSIS
    Vérifie que l'état actuel des applications est égal à l'état mémorisé
    au début du test.
#>
function Assert-ApplicationStateUnchanged {
    $state = Get-TestState

    if ($null -eq $state.SavedAppState) {
        throw "PREPARATION : Assert-ApplicationStateUnchanged exige Start-Test -EnvironnementReel."
    }

    $now      = Format-ApplicationState -State (Get-ApplicationState)
    $expected = Format-ApplicationState -State $state.SavedAppState

    Add-CheckResult -Success ($now -eq $expected) -Description "état des applications identique à l'état initial ($expected ; obtenu : $now)"
}

<#
.SYNOPSIS
    Noms des sous-dossiers de <racine>\.rollback.
#>
function Get-RollbackDirectoryNames {
    param([Parameter(Mandatory = $true)] [string] $Root)

    $rollbackRoot = Join-Path $Root ".rollback"

    if (-not (Test-Path -LiteralPath $rollbackRoot -PathType Container)) { return @() }

    return @(Get-ChildItem -LiteralPath $rollbackRoot -Directory | ForEach-Object { $_.Name })
}

<#
.SYNOPSIS
    Dossier de sauvegarde créé par le dernier déploiement ($null si aucun).
#>
function Get-LatestRollbackDirectory {
    param([Parameter(Mandatory = $true)] [string] $Root)

    $rollbackRoot = Join-Path $Root ".rollback"

    if (-not (Test-Path -LiteralPath $rollbackRoot -PathType Container)) { return $null }

    return Get-ChildItem -LiteralPath $rollbackRoot -Directory |
        Where-Object { $_.CreationTime -ge (Get-TestState).StartTime.AddSeconds(-2) } |
        Sort-Object CreationTime -Descending |
        Select-Object -First 1
}

<#
.SYNOPSIS
    Pose « ancienne-version » dans taskflow, api et HpcLite de
    l'environnement réel. Retirés au nettoyage.
#>
function Set-RealVersionMarkers {
    $root = (Get-TestConfig).RacineReelle

    foreach ($relative in @("taskflow", "api", "HpcLite")) {
        Set-VersionMarker -Directory (Join-Path $root $relative) -Value "ancienne-version"
    }
}

Export-ModuleMember -Function *
