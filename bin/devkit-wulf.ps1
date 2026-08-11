[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Command,
    [Parameter(Position = 1)]
    [string]$Target,
    [switch]$Experimental,
    [switch]$AcceptRemoteScript,
    [switch]$Supported,
    [string]$Platform
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT') {
    throw '[devkit-wulf] Use bin/devkit-wulf on non-Windows hosts.'
}

$RootDir = Split-Path -Parent $PSScriptRoot
$EnvironmentManifestPath = Join-Path $RootDir 'manifests\environments.json'
$PlatformManifestPath = Join-Path $RootDir 'manifests\platforms.json'
$ProfileManifestPath = Join-Path $RootDir 'profiles\profiles.json'
$PhpWindowsManifestPath = Join-Path $RootDir 'manifests\php-windows.json'
$ComposerWindowsManifestPath = Join-Path $RootDir 'manifests\composer-windows.json'
$PhpWindowsEnvironmentHelperPath = Join-Path $RootDir 'lib\php-windows-environment.ps1'
$StateDir = if ($env:DEVKIT_WULF_STATE_DIR) { $env:DEVKIT_WULF_STATE_DIR } else { Join-Path $env:LOCALAPPDATA 'devkit-wulf' }
$StateFile = Join-Path $StateDir 'state.jsonl'

function Write-DevkitLog([string]$Message) {
    Write-Information "[devkit-wulf] $Message" -InformationAction Continue
}

function Stop-Devkit([string]$Message) {
    throw "[devkit-wulf] $Message"
}

function Import-DevkitJson([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { Stop-Devkit "Required manifest not found: $Path" }
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

$EnvironmentCatalog = Import-DevkitJson $EnvironmentManifestPath
$PlatformCatalog = Import-DevkitJson $PlatformManifestPath
$ProfileCatalog = Import-DevkitJson $ProfileManifestPath

function Test-DevkitReparsePoint([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $item = Get-Item -LiteralPath $Path -Force
    return (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
}

function Assert-DevkitStateReady {
    if (Test-DevkitReparsePoint $StateDir) { Stop-Devkit "GATE-10 refuses state-directory reparse point: $StateDir" }
    if (-not (Test-Path -LiteralPath $StateDir)) { New-Item -ItemType Directory -Path $StateDir -Force | Out-Null }
    if (-not (Test-Path -LiteralPath $StateDir -PathType Container)) { Stop-Devkit "State path is not a directory: $StateDir" }
    if (Test-DevkitReparsePoint $StateFile) { Stop-Devkit "GATE-10 refuses state-file reparse point: $StateFile" }
    if ((Test-Path -LiteralPath $StateFile) -and -not (Test-Path -LiteralPath $StateFile -PathType Leaf)) {
        Stop-Devkit "State path is not a regular file: $StateFile"
    }
}

function Get-NormalizedArchitecture {
    $arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLowerInvariant()
    switch ($arch) {
        'x64' { return 'amd64' }
        'arm64' { return 'arm64' }
        'x86' { return '386' }
        default { return $arch }
    }
}

function Get-WslInfo {
    $wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
    if (-not $wsl) {
        return [pscustomobject]@{ Available = $false; Distributions = @() }
    }

    $raw = @(& wsl.exe --list --verbose 2>$null)
    if ($LASTEXITCODE -ne 0) {
        return [pscustomobject]@{ Available = $true; Distributions = @() }
    }

    $lines = @($raw | Where-Object { $_ -and $_ -notmatch '^\s*NAME\s+STATE\s+VERSION' })
    return [pscustomobject]@{ Available = $true; Distributions = $lines }
}

function Get-HostDetection {
    $os = Get-CimInstance Win32_OperatingSystem
    $computer = Get-CimInstance Win32_ComputerSystem
    $processor = Get-CimInstance Win32_Processor | Select-Object -First 1
    $wsl = Get-WslInfo
    $winget = [bool](Get-Command winget.exe -ErrorAction SilentlyContinue)

    $virtualizationFirmware = $false
    if ($computer.PSObject.Properties['HypervisorPresent']) {
        $virtualizationFirmware = [bool]$computer.HypervisorPresent
    }
    if ($processor -and $processor.PSObject.Properties['VirtualizationFirmwareEnabled']) {
        $virtualizationFirmware = $virtualizationFirmware -or [bool]$processor.VirtualizationFirmwareEnabled
    }

    $free = $null
    try {
        $systemDrive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'"
        if ($systemDrive -and $systemDrive.FreeSpace) {
            $free = [math]::Round($systemDrive.FreeSpace / 1GB, 2)
        }
    } catch {
        Write-Verbose "Disk-space detection failed: $($_.Exception.Message)"
    }

    return [pscustomobject]@{
        platform = 'windows'
        family = 'windows'
        domain = 'native'
        caption = $os.Caption
        version = $os.Version
        build = $os.BuildNumber
        architecture = Get-NormalizedArchitecture
        package_manager = if ($winget) { 'winget' } else { 'none' }
        is_admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        virtualization_firmware_enabled = $virtualizationFirmware
        wsl_available = $wsl.Available
        wsl_distributions = $wsl.Distributions
        available_disk_gb = $free
    }
}

function Get-EnvironmentDefinition([string]$Id) {
    $property = $EnvironmentCatalog.environments.PSObject.Properties[$Id]
    if (-not $property) { Stop-Devkit "Unknown environment: $Id" }
    return $property.Value
}

function Get-PlatformEntry([object]$Environment, [string]$PlatformId = 'windows') {
    $property = $Environment.platforms.PSObject.Properties[$PlatformId]
    if ($property) { return $property.Value }
    return [pscustomobject]@{ support = 'unsupported'; strategy = 'unsupported' }
}

function Test-ArchitectureAllowed([object]$Entry, [string]$Arch) {
    if (-not $Entry.PSObject.Properties['architectures'] -or -not $Entry.architectures) { return $true }
    return @($Entry.architectures) -contains $Arch
}

function Get-EnvironmentPackages([object]$Environment, [string]$PackageManager) {
    if (-not $Environment.PSObject.Properties['packages']) { return @() }
    $property = $Environment.packages.PSObject.Properties[$PackageManager]
    if (-not $property) { return @() }
    return @($property.Value)
}

function Get-RemoteScriptDefinition([object]$Environment) {
    if (-not $Environment.PSObject.Properties['remote_scripts']) { return $null }
    $property = $Environment.remote_scripts.PSObject.Properties['windows']
    if (-not $property) { return $null }
    return $property.Value
}

function Get-EffectiveEnvironment([string]$EnvironmentId) {
    $definition = Get-EnvironmentDefinition $EnvironmentId
    $entry = Get-PlatformEntry $definition 'windows'
    $arch = Get-NormalizedArchitecture
    $detection = Get-HostDetection

    if (-not (Test-ArchitectureAllowed $entry $arch)) {
        return [pscustomobject]@{
            Definition = $definition
            Support = 'unsupported'
            Strategy = 'unsupported'
            Architecture = $arch
            Entry = $entry
            Reason = "architecture '$arch' is not listed for this environment"
        }
    }

    if ($detection.caption -match 'Server' -and $EnvironmentId -in @('vscode', 'docker')) {
        return [pscustomobject]@{
            Definition = $definition
            Support = 'unsupported'
            Strategy = 'unsupported'
            Architecture = $arch
            Entry = $entry
            Reason = "$EnvironmentId desktop is not supported on Windows Server by its upstream vendor"
        }
    }

    $strategy = [string]$entry.strategy
    if ($EnvironmentId -eq 'php' -and $strategy -eq 'official-archive' -and $arch -eq 'amd64') {
        $strategy = 'php-windows'
    }

    return [pscustomobject]@{
        Definition = $definition
        Support = $entry.support
        Strategy = $strategy
        Architecture = $arch
        Entry = $entry
        Reason = $null
    }
}

function Invoke-DevkitPhpWindowsPlanFromCli {
    . $PhpWindowsEnvironmentHelperPath
    return Get-DevkitPhpWindowsEnvironmentPlan -PhpManifestPath $PhpWindowsManifestPath -ComposerManifestPath $ComposerWindowsManifestPath
}

function Test-DevkitPhpWindowsManagedVerification([switch]$Quiet) {
    try {
        . $PhpWindowsEnvironmentHelperPath
        $manifest = Get-DevkitPhpWindowsManifest -ManifestPath $PhpWindowsManifestPath
        if ((Get-DevkitPhpWindowsArchitecture) -ne 'amd64') { return $false }
        $destination = Resolve-DevkitPhpLocalAppDataTemplate -Template $manifest.target.destination_template
        if (-not $Quiet) { Write-Information '[verify] managed php --version and composer --version' -InformationAction Continue }
        Invoke-DevkitPhpWindowsEnvironmentVerify -Destination $destination | Out-Null
        return $true
    } catch {
        if (-not $Quiet) { Write-Warning "[devkit-wulf] managed PHP Windows verification failed: $($_.Exception.Message)" }
        return $false
    }
}

function Install-DevkitPhpWindowsManagedEnvironmentFromCli {
    $hadStateOverride = Test-Path Env:DEVKIT_WULF_STATE_DIR
    $oldStateOverride = $env:DEVKIT_WULF_STATE_DIR
    try {
        $env:DEVKIT_WULF_STATE_DIR = $StateDir
        . $PhpWindowsEnvironmentHelperPath
        return Install-DevkitPhpWindowsEnvironment -PhpManifestPath $PhpWindowsManifestPath -ComposerManifestPath $ComposerWindowsManifestPath
    } finally {
        if ($hadStateOverride) { $env:DEVKIT_WULF_STATE_DIR = $oldStateOverride }
        else { Remove-Item Env:DEVKIT_WULF_STATE_DIR -ErrorAction SilentlyContinue }
    }
}

function Write-Detection {
    $detection = Get-HostDetection
    $detection | Format-List
    if ($detection.wsl_available) {
        Write-DevkitLog 'WSL is available. Creating a distro or converting WSL1 to WSL2 remains an explicit, separately planned system change.'
    }
}

function Write-EnvironmentPlan([string]$EnvironmentId) {
    $effective = Get-EffectiveEnvironment $EnvironmentId
    $detection = Get-HostDetection

    Write-Output "environment=$EnvironmentId"
    Write-Output 'platform=windows'
    Write-Output 'domain=native'
    Write-Output "architecture=$($effective.Architecture)"
    Write-Output "support=$($effective.Support)"
    Write-Output "strategy=$($effective.Strategy)"
    Write-Output "package_manager=$($detection.package_manager)"

    if ($effective.Reason) { Write-Output "reason=$($effective.Reason)" }
    if ($effective.Entry.PSObject.Properties['notes']) { Write-Output "notes=$($effective.Entry.notes)" }

    Write-Output 'packages:'
    $packages = Get-EnvironmentPackages $effective.Definition $detection.package_manager
    if ($packages.Count -gt 0) {
        $packages | ForEach-Object { Write-Output "  - $_" }
    } else {
        Write-Output "  - none mapped for $($detection.package_manager)"
    }

    $script = Get-RemoteScriptDefinition $effective.Definition
    if ($script) {
        Write-Output 'remote_script:'
        Write-Output "  url: $($script.url)"
        Write-Output "  integrity: $($script.integrity)"
    }

    if ($effective.Strategy -eq 'php-windows') {
        $phpPlan = Invoke-DevkitPhpWindowsPlanFromCli
        Write-Output 'php_windows:'
        Write-Output "  support: $($phpPlan.Support)"
        Write-Output "  php_version: $($phpPlan.PhpVersion)"
        Write-Output "  php_build: $($phpPlan.PhpBuild)"
        Write-Output "  php_archive: $($phpPlan.PhpArchiveUrl)"
        Write-Output "  php_sha256: $($phpPlan.PhpExpectedSha256)"
        Write-Output "  composer_phar: $($phpPlan.ComposerPharUrl)"
        Write-Output "  composer_checksum: $($phpPlan.ComposerChecksumUrl)"
        Write-Output "  destination: $($phpPlan.Destination)"
        Write-Output "  install_order: $($phpPlan.InstallOrder -join ' -> ')"
        Write-Output '  privilege: none'
        Write-Output '  path_mutation: none'
    }

    Write-Output 'verification:'
    @($effective.Definition.verify) | ForEach-Object { Write-Output "  - $_" }
    Write-Output 'sources:'
    @($effective.Definition.sources) | ForEach-Object { Write-Output "  - $_" }
    Write-Output 'mutates_host=false'
}

function Test-EnvironmentVerification([string]$EnvironmentId, [switch]$Quiet) {
    $effective = Get-EffectiveEnvironment $EnvironmentId
    if ($EnvironmentId -eq 'php' -and $effective.Strategy -eq 'php-windows') {
        return Test-DevkitPhpWindowsManagedVerification -Quiet:$Quiet
    }

    $definition = $effective.Definition
    $failed = 0
    foreach ($line in @($definition.verify)) {
        if (-not $Quiet) { Write-Information "[verify] $line" -InformationAction Continue }
        & cmd.exe /d /s /c $line
        if ($LASTEXITCODE -ne 0) { $failed++ }
    }
    if ($failed -gt 0) {
        if (-not $Quiet) { Write-Warning "[devkit-wulf] $failed verification command(s) failed for $EnvironmentId" }
        return $false
    }
    return $true
}

function Add-StateRecord([string]$EnvironmentId, [string]$Strategy, [string]$Action) {
    Assert-DevkitStateReady
    $record = [ordered]@{
        timestamp = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
        environment = $EnvironmentId
        strategy = $Strategy
        platform = 'windows'
        architecture = Get-NormalizedArchitecture
        domain = 'native'
        action = $Action
    }
    ($record | ConvertTo-Json -Compress) | Add-Content -LiteralPath $StateFile -Encoding UTF8
}

function Test-WinGetPackageInstalled([string]$PackageId) {
    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) { return $false }
    & winget.exe list --exact --id $PackageId --accept-source-agreements --disable-interactivity *> $null
    return $LASTEXITCODE -eq 0
}

function Install-WinGetPackages([string[]]$Packages) {
    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        Stop-Devkit 'WinGet is required for this strategy.'
    }
    foreach ($id in $Packages) {
        if (Test-WinGetPackageInstalled $id) {
            Write-DevkitLog "WinGet package already installed: $id"
            continue
        }
        Write-DevkitLog "winget install --id $id"
        & winget.exe install --exact --id $id --accept-package-agreements --accept-source-agreements --disable-interactivity
        if ($LASTEXITCODE -ne 0) { Stop-Devkit "WinGet failed for package $id" }
    }
}

function Test-DownloadedScript([string]$Path) {
    $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($text)) { Stop-Devkit 'Downloaded script is empty.' }
    $destructive = @(
        '(?i)\bformat\s+[a-z]:',
        '(?i)\bdiskpart\b',
        '(?i)\bClear-Disk\b',
        '(?i)\bRemove-Item\s+[^\r\n]*-Recurse[^\r\n]*\b[A-Z]:\\\s*($|["''])',
        '(?i)\brm\s+-rf\s+/($|\s)'
    )
    foreach ($pattern in $destructive) {
        if ($text -match $pattern) { Stop-Devkit 'GATE-06 blocked remote script: destructive command pattern detected.' }
    }
    if ($text -match '(?is)(Invoke-WebRequest|Invoke-RestMethod|\birm\b|curl|wget).{0,160}(Invoke-Expression|\biex\b|\|\s*(powershell|pwsh|cmd|sh|bash))') {
        Stop-Devkit 'GATE-06 blocked automatic execution because nested download-to-execution behavior was detected.'
    }
}

function Install-OfficialScript([string]$EnvironmentId, [object]$Environment, [switch]$Accepted) {
    if (-not $Accepted) { Stop-Devkit 'official-script strategy requires -AcceptRemoteScript after reviewing the plan.' }
    $script = Get-RemoteScriptDefinition $Environment
    if (-not $script) { Stop-Devkit "No Windows remote script metadata for $EnvironmentId" }
    $uri = [Uri]$script.url
    if ($uri.Scheme -ne 'https') { Stop-Devkit "GATE-04 blocked non-HTTPS URL: $uri" }
    $temporaryScript = Join-Path ([IO.Path]::GetTempPath()) ("devkit-wulf-{0}.ps1" -f [guid]::NewGuid())
    try {
        Invoke-WebRequest -Uri $uri -OutFile $temporaryScript -UseBasicParsing
        $hash = (Get-FileHash -LiteralPath $temporaryScript -Algorithm SHA256).Hash.ToLowerInvariant()
        Write-DevkitLog "GATE-04 source: $uri"
        Write-DevkitLog "GATE-05/06 downloaded SHA-256: $hash; integrity policy: $($script.integrity)"
        Test-DownloadedScript $temporaryScript
        $arguments = @()
        if ($script.PSObject.Properties['arguments']) { $arguments = @($script.arguments) }
        $pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
        if ($pwsh) { & $pwsh.Source -NoProfile -File $temporaryScript @arguments }
        else { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $temporaryScript @arguments }
        if ($LASTEXITCODE -ne 0) { Stop-Devkit "Official installer exited with code $LASTEXITCODE" }
    } finally {
        Remove-Item -LiteralPath $temporaryScript -Force -ErrorAction SilentlyContinue
    }
}

function Install-Environment([string]$EnvironmentId, [switch]$AllowExperimental, [switch]$AllowRemoteScript) {
    $effective = Get-EffectiveEnvironment $EnvironmentId
    switch ($effective.Support) {
        'unsupported' { Stop-Devkit "$EnvironmentId is unsupported on Windows/$($effective.Architecture): $($effective.Reason)" }
        'target-only' { Stop-Devkit "$EnvironmentId is target-only and is not a Windows host installation" }
        'experimental' {
            if (-not $AllowExperimental) { Stop-Devkit "$EnvironmentId on Windows is experimental; inspect plan and pass -Experimental to opt in" }
        }
    }

    if (Test-EnvironmentVerification $EnvironmentId -Quiet) {
        Write-DevkitLog "$EnvironmentId already passes verification; no mutation performed"
        Add-StateRecord $EnvironmentId $effective.Strategy 'observed-existing'
        return
    }

    switch ($effective.Strategy) {
        'winget' {
            $packages = Get-EnvironmentPackages $effective.Definition 'winget'
            if ($packages.Count -eq 0) { Stop-Devkit "No WinGet package mapping for $EnvironmentId; refusing to guess." }
            Install-WinGetPackages $packages
        }
        'official-script' { Install-OfficialScript $EnvironmentId $effective.Definition -Accepted:$AllowRemoteScript }
        'php-windows' { Install-DevkitPhpWindowsManagedEnvironmentFromCli | Out-Null }
        'wsl2' { Stop-Devkit 'WSL creation/conversion requires a dedicated explicit system-change workflow and is never implicit.' }
        { $_ -in @('official-archive', 'manual', 'source', 'vm', 'container', 'xcode') } {
            Stop-Devkit "Strategy '$($effective.Strategy)' requires a dedicated adapter that is not yet safe to automate for $EnvironmentId."
        }
        default { Stop-Devkit "Strategy '$($effective.Strategy)' is not installable." }
    }

    if (-not (Test-EnvironmentVerification $EnvironmentId)) { Stop-Devkit 'GATE-12 verification failed after installation.' }
    Add-StateRecord $EnvironmentId $effective.Strategy 'installed-and-verified'
    Write-DevkitLog "$EnvironmentId installed and verified"
}

function Install-Profile([string]$Name, [switch]$AllowExperimental, [switch]$AllowRemoteScript) {
    $property = $ProfileCatalog.profiles.PSObject.Properties[$Name]
    if (-not $property) { Stop-Devkit "Unknown profile: $Name" }
    $failed = 0
    $skipped = 0
    foreach ($id in @($property.Value.environments)) {
        $effective = Get-EffectiveEnvironment $id
        if ($effective.Support -in @('unsupported', 'target-only')) {
            Write-DevkitLog "profile:$Name -> $id skipped ($($effective.Support))"
            $skipped++
            continue
        }
        if ($effective.Support -eq 'experimental' -and -not $AllowExperimental) {
            Write-DevkitLog "profile:$Name -> $id skipped (experimental; opt in with -Experimental)"
            $skipped++
            continue
        }
        Write-DevkitLog "profile:$Name -> $id"
        try { Install-Environment $id -AllowExperimental:$AllowExperimental -AllowRemoteScript:$AllowRemoteScript }
        catch {
            Write-Warning "[devkit-wulf] $($_.Exception.Message)"
            $failed++
        }
    }
    Write-DevkitLog "profile:$Name completed: skipped=$skipped failed=$failed"
    if ($failed -gt 0) { Stop-Devkit "$failed environment(s) failed in profile:$Name" }
}

function Get-EnvironmentList([switch]$OnlySupported, [string]$ForPlatform) {
    $platformId = if ($ForPlatform) { $ForPlatform } else { 'windows' }
    $currentArch = Get-NormalizedArchitecture
    foreach ($property in $EnvironmentCatalog.environments.PSObject.Properties | Sort-Object Name) {
        $entryProperty = $property.Value.platforms.PSObject.Properties[$platformId]
        $entry = if ($entryProperty) { $entryProperty.Value } else { [pscustomobject]@{ support = 'unsupported'; strategy = 'unsupported' } }
        $support = $entry.support
        $strategy = $entry.strategy
        if ($platformId -eq 'windows' -and -not (Test-ArchitectureAllowed $entry $currentArch)) {
            $support = 'unsupported'
            $strategy = 'unsupported'
        } elseif ($platformId -eq 'windows' -and $property.Name -eq 'php' -and $strategy -eq 'official-archive' -and $currentArch -eq 'amd64') {
            $strategy = 'php-windows'
        }
        if ($OnlySupported -and $support -in @('experimental', 'unsupported', 'target-only')) { continue }
        '{0,-14} {1,-13} {2}' -f $property.Name, $support, $strategy
    }
}

function Remove-Environment([string]$EnvironmentId) {
    $definition = Get-EnvironmentDefinition $EnvironmentId
    $safe = $false
    if ($definition.PSObject.Properties['safe_remove']) { $safe = [bool]$definition.safe_remove }
    if (-not $safe) { Stop-Devkit "Safe removal is not established for $EnvironmentId; GATE-15 refuses destructive uninstall." }
    Stop-Devkit 'Safe removal adapter is not implemented yet.'
}

function Invoke-DevkitDoctor {
    $detection = Get-HostDetection
    $detection | Format-List
    if ($detection.package_manager -eq 'none') {
        Write-Warning '[devkit-wulf] WinGet is unavailable; winget-backed environments cannot be installed.'
    }
    Assert-DevkitStateReady
    $testPath = Join-Path $StateDir '.write-test'
    'ok' | Set-Content -LiteralPath $testPath -Encoding ASCII
    Remove-Item -LiteralPath $testPath -Force
    Import-DevkitJson $PhpWindowsManifestPath | Out-Null
    Import-DevkitJson $ComposerWindowsManifestPath | Out-Null
    Write-DevkitLog 'manifest JSON parse: PASS'
    Write-DevkitLog 'PHP Windows manifest JSON parse: PASS'
    Write-DevkitLog 'Composer Windows manifest JSON parse: PASS'
    Write-DevkitLog "state directory: PASS ($StateDir)"
    if ($detection.wsl_available) { Write-DevkitLog 'WSL capability detected; distribution mutation remains separately gated.' }
    Write-DevkitLog 'doctor completed'
}

function Write-Usage {
    @'
Usage:
  .\bin\devkit-wulf.ps1 detect
  .\bin\devkit-wulf.ps1 list [-Supported] [-Platform windows]
  .\bin\devkit-wulf.ps1 plan ENVIRONMENT
  .\bin\devkit-wulf.ps1 install ENVIRONMENT|profile:NAME [-Experimental] [-AcceptRemoteScript]
  .\bin\devkit-wulf.ps1 verify ENVIRONMENT
  .\bin\devkit-wulf.ps1 remove ENVIRONMENT
  .\bin\devkit-wulf.ps1 doctor
'@ | Write-Output
}

if (-not $Command) {
    Write-Usage
    exit 2
}

switch ($Command.ToLowerInvariant()) {
    'detect' { Write-Detection }
    'list' { Get-EnvironmentList -OnlySupported:$Supported -ForPlatform $Platform }
    'plan' {
        if (-not $Target) { Stop-Devkit 'plan requires an environment' }
        Write-EnvironmentPlan $Target
    }
    'verify' {
        if (-not $Target) { Stop-Devkit 'verify requires an environment' }
        if (-not (Test-EnvironmentVerification $Target)) { exit 1 }
    }
    'remove' {
        if (-not $Target) { Stop-Devkit 'remove requires an environment' }
        Remove-Environment $Target
    }
    'install' {
        if (-not $Target) { Stop-Devkit 'install requires an environment or profile' }
        if ($Target.StartsWith('profile:')) {
            Install-Profile $Target.Substring(8) -AllowExperimental:$Experimental -AllowRemoteScript:$AcceptRemoteScript
        } else {
            Install-Environment $Target -AllowExperimental:$Experimental -AllowRemoteScript:$AcceptRemoteScript
        }
    }
    'doctor' { Invoke-DevkitDoctor }
    'help' { Write-Usage }
    default {
        Write-Usage
        Stop-Devkit "Unknown command: $Command"
    }
}
