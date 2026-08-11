Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$PhpRuntimeHelper = Join-Path $PSScriptRoot 'php-windows.ps1'
$ComposerHelper = Join-Path $PSScriptRoot 'composer-windows.ps1'
if (-not (Get-Command Install-DevkitPhpWindowsRuntime -CommandType Function -ErrorAction SilentlyContinue)) { . $PhpRuntimeHelper }
if (-not (Get-Command Install-DevkitComposerWindows -CommandType Function -ErrorAction SilentlyContinue)) { . $ComposerHelper }

function Get-DevkitPhpWindowsEnvironmentStateFile {
    if ($env:DEVKIT_WULF_STATE_DIR) { $stateDir = [System.IO.Path]::GetFullPath($env:DEVKIT_WULF_STATE_DIR) }
    else {
        if (-not $env:LOCALAPPDATA) { throw 'LOCALAPPDATA is required for the default devkit-wulf state directory.' }
        $stateDir = [System.IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'devkit-wulf\state'))
    }
    if (Test-DevkitPhpReparsePoint -Path $stateDir) { throw "GATE-10 refuses PHP environment state-directory reparse point: $stateDir" }
    if (-not (Test-Path -LiteralPath $stateDir)) { New-Item -ItemType Directory -Path $stateDir -Force | Out-Null }
    if (-not (Test-Path -LiteralPath $stateDir -PathType Container)) { throw "PHP environment state path is not a directory: $stateDir" }
    $stateFile = Join-Path $stateDir 'php-windows-environment.jsonl'
    if (Test-DevkitPhpReparsePoint -Path $stateFile) { throw "GATE-10 refuses PHP environment state-file reparse point: $stateFile" }
    if ((Test-Path -LiteralPath $stateFile) -and -not (Test-Path -LiteralPath $stateFile -PathType Leaf)) { throw "PHP environment state path is not a regular file: $stateFile" }
    return $stateFile
}

function Add-DevkitPhpWindowsEnvironmentState {
    param(
        [Parameter(Mandatory = $true)][string]$Action,
        [Parameter(Mandatory = $true)][string]$Destination,
        [string]$Detail = ''
    )
    $stateFile = Get-DevkitPhpWindowsEnvironmentStateFile
    [ordered]@{
        timestamp     = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
        environment   = 'php'
        platform      = 'windows'
        action        = $Action
        destination   = $Destination
        detail        = $Detail
        path_mutation = $false
    } | ConvertTo-Json -Compress | Add-Content -LiteralPath $stateFile -Encoding UTF8
}

function Get-DevkitPhpWindowsEnvironmentPlan {
    param(
        [Parameter(Mandatory = $true)][string]$PhpManifestPath,
        [Parameter(Mandatory = $true)][string]$ComposerManifestPath
    )
    $phpManifest = Get-DevkitPhpWindowsManifest -ManifestPath $PhpManifestPath
    $composerManifest = Get-DevkitComposerWindowsManifest -ManifestPath $ComposerManifestPath
    $architecture = Get-DevkitPhpWindowsArchitecture
    if ($architecture -ne 'amd64') { throw "GATE-02 combined PHP Windows environment supports amd64 only, detected $architecture" }
    $phpPlan = Get-DevkitPhpWindowsPlan -ManifestPath $PhpManifestPath
    $destination = Resolve-DevkitPhpLocalAppDataTemplate -Template $phpManifest.target.destination_template
    $composerDirectory = Resolve-DevkitPhpLocalAppDataTemplate -Template $composerManifest.target.php_directory_template
    if (-not [string]::Equals($destination, $composerDirectory, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'GATE-03 PHP runtime and Composer manifests disagree about the managed PHP directory.'
    }
    [pscustomobject]@{
        Environment          = 'php'
        Platform             = 'windows'
        Architecture         = $architecture
        Support              = 'experimental'
        Destination          = $destination
        PhpVersion           = $phpPlan.Version
        PhpBuild             = $phpPlan.Build
        PhpArchiveUrl        = $phpPlan.ArchiveUrl
        PhpExpectedSha256    = $phpPlan.ExpectedSha256
        ComposerPharUrl      = [string]$composerManifest.phar_url
        ComposerChecksumUrl  = [string]$composerManifest.checksum_url
        Components           = @('php-windows-runtime', 'composer')
        InstallOrder         = @('php-windows-runtime', 'composer', 'verify-environment')
        Verification         = @('php --version', 'composer --version')
        PathMutation         = $false
        Privilege            = 'none'
        MutatesHost          = $false
        Rollback             = 'partial component install is recorded; automatic destructive rollback is not promised'
    }
}

if (-not (Get-Command Invoke-DevkitPhpWindowsEnvironmentVerify -CommandType Function -ErrorAction SilentlyContinue)) {
    function Invoke-DevkitPhpWindowsEnvironmentVerify {
        param([Parameter(Mandatory = $true)][string]$Destination)
        $phpExe = Join-Path $Destination 'php.exe'
        $composerBat = Join-Path $Destination 'composer.bat'
        if (-not (Test-Path -LiteralPath $phpExe -PathType Leaf) -or (Test-DevkitPhpReparsePoint -Path $phpExe)) { throw 'GATE-12 php.exe is missing or unsafe after combined installation.' }
        if (-not (Test-Path -LiteralPath $composerBat -PathType Leaf) -or (Test-DevkitPhpReparsePoint -Path $composerBat)) { throw 'GATE-12 composer.bat is missing or unsafe after combined installation.' }
        $phpOutput = & $phpExe '--version' 2>&1
        if ($LASTEXITCODE -ne 0) { throw "GATE-12 php --version failed: $phpOutput" }
        $composerOutput = & $composerBat '--version' '--no-ansi' 2>&1
        if ($LASTEXITCODE -ne 0) { throw "GATE-12 composer --version failed: $composerOutput" }
        [pscustomobject]@{
            PhpOutput      = ($phpOutput -join "`n")
            ComposerOutput = ($composerOutput -join "`n")
        }
    }
}

function Install-DevkitPhpWindowsEnvironment {
    param(
        [Parameter(Mandatory = $true)][string]$PhpManifestPath,
        [Parameter(Mandatory = $true)][string]$ComposerManifestPath
    )
    $plan = Get-DevkitPhpWindowsEnvironmentPlan -PhpManifestPath $PhpManifestPath -ComposerManifestPath $ComposerManifestPath
    $destination = $plan.Destination
    Add-DevkitPhpWindowsEnvironmentState -Action 'environment-install-intent' -Destination $destination -Detail 'php-windows-runtime -> composer -> verify-environment'

    try {
        Install-DevkitPhpWindowsRuntime -ManifestPath $PhpManifestPath
        Add-DevkitPhpWindowsEnvironmentState -Action 'runtime-component-ready' -Destination $destination
    } catch {
        Add-DevkitPhpWindowsEnvironmentState -Action 'runtime-component-failed' -Destination $destination -Detail $_.Exception.Message
        throw
    }

    try {
        Install-DevkitComposerWindows -ManifestPath $ComposerManifestPath
        Add-DevkitPhpWindowsEnvironmentState -Action 'composer-component-ready' -Destination $destination
    } catch {
        Add-DevkitPhpWindowsEnvironmentState -Action 'environment-incomplete' -Destination $destination -Detail ('Composer failed after PHP runtime became ready: ' + $_.Exception.Message)
        throw
    }

    try {
        $verification = Invoke-DevkitPhpWindowsEnvironmentVerify -Destination $destination
        Add-DevkitPhpWindowsEnvironmentState -Action 'environment-verified' -Destination $destination
        return $verification
    } catch {
        Add-DevkitPhpWindowsEnvironmentState -Action 'environment-verification-failed' -Destination $destination -Detail $_.Exception.Message
        throw
    }
}
