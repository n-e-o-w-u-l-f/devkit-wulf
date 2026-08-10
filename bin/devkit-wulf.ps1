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

$RootDir = Split-Path -Parent $PSScriptRoot
$EnvironmentManifestPath = Join-Path $RootDir 'manifests\environments.json'
$PlatformManifestPath = Join-Path $RootDir 'manifests\platforms.json'
$ProfileManifestPath = Join-Path $RootDir 'profiles\profiles.json'
$StateDir = if ($env:DEVKIT_WULF_STATE_DIR) { $env:DEVKIT_WULF_STATE_DIR } else { Join-Path $env:LOCALAPPDATA 'devkit-wulf' }
$StateFile = Join-Path $StateDir 'state.jsonl'

function Write-Log([string]$Message) { Write-Host "[devkit-wulf] $Message" }
function Write-Warn([string]$Message) { Write-Warning "[devkit-wulf] $Message" }
function Fail([string]$Message) { throw "[devkit-wulf] $Message" }

function Load-Json([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { Fail "Required manifest not found: $Path" }
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

$EnvironmentCatalog = Load-Json $EnvironmentManifestPath
$PlatformCatalog = Load-Json $PlatformManifestPath
$ProfileCatalog = Load-Json $ProfileManifestPath

function Get-NormalizedArchitecture {
    $arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLowerInvariant()
    switch ($arch) {
        'x64' { 'amd64' }
        'arm64' { 'arm64' }
        'x86' { '386' }
        default { $arch }
    }
}

function Get-WslInfo {
    $wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
    if (-not $wsl) { return [pscustomobject]@{ Available = $false; Distributions = @() } }
    $raw = & wsl.exe --list --verbose 2>$null
    if ($LASTEXITCODE -ne 0) { return [pscustomobject]@{ Available = $true; Distributions = @() } }
    $lines = @($raw | Where-Object { $_ -and $_ -notmatch '^\s*NAME\s+STATE\s+VERSION' })
    return [pscustomobject]@{ Available = $true; Distributions = $lines }
}

function Get-Detection {
    if (-not $IsWindows -and $PSVersionTable.PSVersion.Major -ge 6) { Fail 'Use bin/devkit-wulf on non-Windows hosts.' }
    $os = Get-CimInstance Win32_OperatingSystem
    $cs = Get-CimInstance Win32_ComputerSystem
    $wsl = Get-WslInfo
    $winget = [bool](Get-Command winget.exe -ErrorAction SilentlyContinue)
    $free = $null
    try {
        $systemDrive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'"
        $free = [math]::Round($systemDrive.FreeSpace / 1GB, 2)
    } catch { }
    [pscustomobject]@{
        platform = 'windows'
        family = 'windows'
        domain = 'native'
        caption = $os.Caption
        version = $os.Version
        build = $os.BuildNumber
        architecture = Get-NormalizedArchitecture
        package_manager = if ($winget) { 'winget' } else { 'none' }
        is_admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        virtualization_firmware_enabled = $cs.HypervisorPresent -or $cs.VirtualizationFirmwareEnabled
        wsl_available = $wsl.Available
        wsl_distributions = $wsl.Distributions
        available_disk_gb = $free
    }
}

function Get-Environment([string]$Id) {
    $property = $EnvironmentCatalog.environments.PSObject.Properties[$Id]
    if (-not $property) { Fail "Unknown environment: $Id" }
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

function Get-Packages([object]$Environment, [string]$PackageManager) {
    if (-not $Environment.PSObject.Properties['packages']) { return @() }
    $p = $Environment.packages.PSObject.Properties[$PackageManager]
    if (-not $p) { return @() }
    return @($p.Value)
}

function Get-RemoteScript([object]$Environment) {
    if (-not $Environment.PSObject.Properties['remote_scripts']) { return $null }
    $p = $Environment.remote_scripts.PSObject.Properties['windows']
    if (-not $p) { return $null }
    return $p.Value
}

function Show-Detection {
    $d = Get-Detection
    $d | Format-List
    if ($d.wsl_available) {
        Write-Log 'WSL is available. Creating a distro or converting WSL1 to WSL2 remains an explicit, separately planned system change.'
    }
}

function Get-EffectiveEntry([string]$EnvironmentId) {
    $envDef = Get-Environment $EnvironmentId
    $entry = Get-PlatformEntry $envDef 'windows'
    $arch = Get-NormalizedArchitecture
    if (-not (Test-ArchitectureAllowed $entry $arch)) {
        return [pscustomobject]@{ Definition = $envDef; Support = 'unsupported'; Strategy = 'unsupported'; Architecture = $arch; Entry = $entry }
    }
    return [pscustomobject]@{ Definition = $envDef; Support = $entry.support; Strategy = $entry.strategy; Architecture = $arch; Entry = $entry }
}

function Show-Plan([string]$EnvironmentId) {
    $effective = Get-EffectiveEntry $EnvironmentId
    $d = Get-Detection
    Write-Output "environment=$EnvironmentId"
    Write-Output "platform=windows"
    Write-Output "domain=native"
    Write-Output "architecture=$($effective.Architecture)"
    Write-Output "support=$($effective.Support)"
    Write-Output "strategy=$($effective.Strategy)"
    Write-Output "package_manager=$($d.package_manager)"
    if ($effective.Entry.PSObject.Properties['notes']) { Write-Output "notes=$($effective.Entry.notes)" }
    Write-Output 'packages:'
    $packages = Get-Packages $effective.Definition $d.package_manager
    if ($packages.Count) { $packages | ForEach-Object { Write-Output "  - $_" } } else { Write-Output "  - none mapped for $($d.package_manager)" }
    $script = Get-RemoteScript $effective.Definition
    if ($script) {
        Write-Output 'remote_script:'
        Write-Output "  url: $($script.url)"
        Write-Output "  integrity: $($script.integrity)"
    }
    Write-Output 'verification:'
    @($effective.Definition.verify) | ForEach-Object { Write-Output "  - $_" }
    Write-Output 'sources:'
    @($effective.Definition.sources) | ForEach-Object { Write-Output "  - $_" }
    Write-Output 'mutates_host=false'
}

function Invoke-Verify([string]$EnvironmentId, [switch]$Quiet) {
    $envDef = Get-Environment $EnvironmentId
    $failed = 0
    foreach ($line in @($envDef.verify)) {
        if (-not $Quiet) { Write-Host "[verify] $line" }
        & cmd.exe /d /s /c $line
        if ($LASTEXITCODE -ne 0) { $failed++ }
    }
    if ($failed -gt 0) {
        if (-not $Quiet) { Write-Warn "$failed verification command(s) failed for $EnvironmentId" }
        return $false
    }
    return $true
}

function Record-State([string]$EnvironmentId, [string]$Strategy, [string]$Action) {
    New-Item -ItemType Directory -Path $StateDir -Force | Out-Null
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

function Install-WinGetPackages([string[]]$Packages) {
    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) { Fail 'WinGet is required for this strategy.' }
    foreach ($id in $Packages) {
        Write-Log "winget install --id $id"
        & winget.exe install --exact --id $id --accept-package-agreements --accept-source-agreements --disable-interactivity
        if ($LASTEXITCODE -ne 0) { Fail "WinGet failed for package $id" }
    }
}

function Test-RemoteScript([string]$Path) {
    $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($text)) { Fail 'Downloaded script is empty.' }
    $destructive = @(
        '(?i)\bformat\s+[a-z]:',
        '(?i)\bdiskpart\b',
        '(?i)\bClear-Disk\b',
        '(?i)\bRemove-Item\s+[^\r\n]*-Recurse[^\r\n]*\b[A-Z]:\\\s*($|["''])',
        '(?i)\brm\s+-rf\s+/($|\s)'
    )
    foreach ($pattern in $destructive) {
        if ($text -match $pattern) { Fail 'GATE-06 blocked remote script: destructive command pattern detected.' }
    }
    if ($text -match '(?is)(Invoke-WebRequest|Invoke-RestMethod|\birm\b|curl|wget).{0,160}(Invoke-Expression|\biex\b|\|\s*(powershell|pwsh|cmd|sh|bash))') {
        Fail 'GATE-06 blocked automatic execution because nested download-to-execution behavior was detected.'
    }
}

function Install-OfficialScript([string]$EnvironmentId, [object]$Environment, [switch]$Accepted) {
    if (-not $Accepted) { Fail 'official-script strategy requires -AcceptRemoteScript after reviewing the plan.' }
    $script = Get-RemoteScript $Environment
    if (-not $script) { Fail "No Windows remote script metadata for $EnvironmentId" }
    $uri = [Uri]$script.url
    if ($uri.Scheme -ne 'https') { Fail "GATE-04 blocked non-HTTPS URL: $uri" }
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("devkit-wulf-{0}.ps1" -f [guid]::NewGuid())
    try {
        Invoke-WebRequest -Uri $uri -OutFile $tmp -UseBasicParsing
        $hash = (Get-FileHash -LiteralPath $tmp -Algorithm SHA256).Hash.ToLowerInvariant()
        Write-Log "GATE-04 source: $uri"
        Write-Log "GATE-05/06 downloaded SHA-256: $hash; integrity policy: $($script.integrity)"
        Test-RemoteScript $tmp
        $args = @()
        if ($script.PSObject.Properties['arguments']) { $args = @($script.arguments) }
        if ($PSVersionTable.PSEdition -eq 'Core' -and (Get-Command pwsh.exe -ErrorAction SilentlyContinue)) {
            & pwsh.exe -NoProfile -File $tmp @args
        } else {
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $tmp @args
        }
        if ($LASTEXITCODE -ne 0) { Fail "Official installer exited with code $LASTEXITCODE" }
    } finally {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
}

function Install-Environment([string]$EnvironmentId, [switch]$AllowExperimental, [switch]$AllowRemoteScript) {
    $effective = Get-EffectiveEntry $EnvironmentId
    switch ($effective.Support) {
        'unsupported' { Fail "$EnvironmentId is unsupported on Windows/$($effective.Architecture)" }
        'target-only' { Fail "$EnvironmentId is target-only and is not a Windows host installation" }
        'experimental' { if (-not $AllowExperimental) { Fail "$EnvironmentId on Windows is experimental; inspect plan and pass -Experimental to opt in" } }
    }
    if (Invoke-Verify $EnvironmentId -Quiet) {
        Write-Log "$EnvironmentId already passes verification; no mutation performed"
        Record-State $EnvironmentId $effective.Strategy 'observed-existing'
        return
    }
    switch ($effective.Strategy) {
        'winget' {
            $packages = Get-Packages $effective.Definition 'winget'
            if (-not $packages.Count) { Fail "No WinGet package mapping for $EnvironmentId; refusing to guess." }
            Install-WinGetPackages $packages
        }
        'official-script' { Install-OfficialScript $EnvironmentId $effective.Definition -Accepted:$AllowRemoteScript }
        'wsl2' { Fail 'WSL creation/conversion requires a dedicated explicit system-change workflow and is never implicit.' }
        { $_ -in @('official-archive','manual','source','vm','container','xcode') } { Fail "Strategy '$($effective.Strategy)' requires a dedicated adapter that is not yet safe to automate for $EnvironmentId." }
        default { Fail "Strategy '$($effective.Strategy)' is not installable." }
    }
    if (-not (Invoke-Verify $EnvironmentId)) { Fail 'GATE-12 verification failed after installation.' }
    Record-State $EnvironmentId $effective.Strategy 'installed-and-verified'
    Write-Log "$EnvironmentId installed and verified"
}

function Install-Profile([string]$Name, [switch]$AllowExperimental, [switch]$AllowRemoteScript) {
    $property = $ProfileCatalog.profiles.PSObject.Properties[$Name]
    if (-not $property) { Fail "Unknown profile: $Name" }
    $failed = 0
    $skipped = 0
    foreach ($id in @($property.Value.environments)) {
        $effective = Get-EffectiveEntry $id
        if ($effective.Support -in @('unsupported','target-only')) {
            Write-Log "profile:$Name -> $id skipped ($($effective.Support))"
            $skipped++
            continue
        }
        if ($effective.Support -eq 'experimental' -and -not $AllowExperimental) {
            Write-Log "profile:$Name -> $id skipped (experimental; opt in with -Experimental)"
            $skipped++
            continue
        }
        Write-Log "profile:$Name -> $id"
        try { Install-Environment $id -AllowExperimental:$AllowExperimental -AllowRemoteScript:$AllowRemoteScript }
        catch { Write-Warn $_.Exception.Message; $failed++ }
    }
    Write-Log "profile:$Name completed: skipped=$skipped failed=$failed"
    if ($failed -gt 0) { Fail "$failed environment(s) failed in profile:$Name" }
}

function List-Environments([switch]$OnlySupported, [string]$ForPlatform) {
    $p = if ($ForPlatform) { $ForPlatform } else { 'windows' }
    foreach ($prop in $EnvironmentCatalog.environments.PSObject.Properties | Sort-Object Name) {
        $entryProp = $prop.Value.platforms.PSObject.Properties[$p]
        $entry = if ($entryProp) { $entryProp.Value } else { [pscustomobject]@{support='unsupported';strategy='unsupported'} }
        $support = $entry.support
        $strategy = $entry.strategy
        if ($p -eq 'windows' -and -not (Test-ArchitectureAllowed $entry (Get-NormalizedArchitecture))) { $support='unsupported'; $strategy='unsupported' }
        if ($OnlySupported -and $support -in @('experimental','unsupported','target-only')) { continue }
        '{0,-14} {1,-13} {2}' -f $prop.Name, $support, $strategy
    }
}

function Remove-Environment([string]$EnvironmentId) {
    $envDef = Get-Environment $EnvironmentId
    $safe = $false
    if ($envDef.PSObject.Properties['safe_remove']) { $safe = [bool]$envDef.safe_remove }
    if (-not $safe) { Fail "Safe removal is not established for $EnvironmentId; GATE-15 refuses destructive uninstall." }
    Fail 'Safe removal adapter is not implemented yet.'
}

function Invoke-Doctor {
    $d = Get-Detection
    $d | Format-List
    if ($d.package_manager -eq 'none') { Write-Warn 'WinGet is unavailable; winget-backed environments cannot be installed.' }
    New-Item -ItemType Directory -Path $StateDir -Force | Out-Null
    $test = Join-Path $StateDir '.write-test'
    'ok' | Set-Content -LiteralPath $test -Encoding ASCII
    Remove-Item -LiteralPath $test -Force
    Write-Log 'manifest JSON parse: PASS'
    Write-Log "state directory: PASS ($StateDir)"
    if ($d.wsl_available) { Write-Log 'WSL capability detected; distribution mutation remains separately gated.' }
    Write-Log 'doctor completed'
}

function Usage {
@'
Usage:
  .\bin\devkit-wulf.ps1 detect
  .\bin\devkit-wulf.ps1 list [-Supported] [-Platform windows]
  .\bin\devkit-wulf.ps1 plan ENVIRONMENT
  .\bin\devkit-wulf.ps1 install ENVIRONMENT|profile:NAME [-Experimental] [-AcceptRemoteScript]
  .\bin\devkit-wulf.ps1 verify ENVIRONMENT
  .\bin\devkit-wulf.ps1 remove ENVIRONMENT
  .\bin\devkit-wulf.ps1 doctor
'@
}

if (-not $Command) { Usage; exit 2 }

switch ($Command.ToLowerInvariant()) {
    'detect' { Show-Detection }
    'list' { List-Environments -OnlySupported:$Supported -ForPlatform $Platform }
    'plan' { if (-not $Target) { Fail 'plan requires an environment' }; Show-Plan $Target }
    'verify' { if (-not $Target) { Fail 'verify requires an environment' }; if (-not (Invoke-Verify $Target)) { exit 1 } }
    'remove' { if (-not $Target) { Fail 'remove requires an environment' }; Remove-Environment $Target }
    'install' {
        if (-not $Target) { Fail 'install requires an environment or profile' }
        if ($Target.StartsWith('profile:')) { Install-Profile $Target.Substring(8) -AllowExperimental:$Experimental -AllowRemoteScript:$AcceptRemoteScript }
        else { Install-Environment $Target -AllowExperimental:$Experimental -AllowRemoteScript:$AcceptRemoteScript }
    }
    'doctor' { Invoke-Doctor }
    'help' { Usage }
    default { Usage; Fail "Unknown command: $Command" }
}
