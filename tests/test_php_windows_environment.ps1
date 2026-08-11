$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$Root = Split-Path -Parent $PSScriptRoot
$Temp = Join-Path ([System.IO.Path]::GetTempPath()) ('devkit-wulf-php-env-test-' + [guid]::NewGuid().ToString('N'))
$State = Join-Path $Temp 'state'
$Destination = Join-Path $Temp 'php'
New-Item -ItemType Directory -Path $State -Force | Out-Null
$oldState = $env:DEVKIT_WULF_STATE_DIR
$env:DEVKIT_WULF_STATE_DIR = $State

$script:events = New-Object System.Collections.Generic.List[string]
$script:failComposer = $false
$script:failVerify = $false

function Test-DevkitPhpReparsePoint { param([string]$Path) return $false }
function Get-DevkitPhpWindowsArchitecture { return 'amd64' }
function Resolve-DevkitPhpLocalAppDataTemplate { param([string]$Template) return $Destination }
function Get-DevkitPhpWindowsManifest {
    param([string]$ManifestPath)
    return [pscustomobject]@{ target = [pscustomobject]@{ destination_template = '{localappdata}\devkit-wulf\php' } }
}
function Get-DevkitComposerWindowsManifest {
    param([string]$ManifestPath)
    return [pscustomobject]@{
        phar_url = 'https://getcomposer.org/download/latest-stable/composer.phar'
        checksum_url = 'https://getcomposer.org/download/latest-stable/composer.phar.sha256sum'
        target = [pscustomobject]@{ php_directory_template = '{localappdata}\devkit-wulf\php' }
    }
}
function Get-DevkitPhpWindowsPlan {
    param([string]$ManifestPath)
    return [pscustomobject]@{
        Version = '8.4.99'
        Build = 'nts-vs17-x64'
        ArchiveUrl = 'https://windows.php.net/downloads/releases/php.zip'
        ExpectedSha256 = ('a' * 64)
    }
}
function Install-DevkitPhpWindowsRuntime {
    param([string]$ManifestPath)
    $script:events.Add('runtime')
}
function Install-DevkitComposerWindows {
    param([string]$ManifestPath)
    $script:events.Add('composer')
    if ($script:failComposer) { throw 'fixture Composer failure' }
}
function Invoke-DevkitPhpWindowsEnvironmentVerify {
    param([string]$Destination)
    $script:events.Add('verify')
    if ($script:failVerify) { throw 'fixture verification failure' }
    return [pscustomobject]@{ PhpOutput = 'PHP 8.4.99'; ComposerOutput = 'Composer version 2.9.99' }
}

try {
    . (Join-Path $Root 'lib\php-windows-environment.ps1')

    $plan = Get-DevkitPhpWindowsEnvironmentPlan -PhpManifestPath 'php.json' -ComposerManifestPath 'composer.json'
    if ($plan.Support -ne 'experimental') { throw 'Combined plan promoted support unexpectedly' }
    if ($plan.MutatesHost -ne $false -or $plan.PathMutation -ne $false -or $plan.Privilege -ne 'none') { throw 'Combined plan mutation/privilege contract failed' }
    if (($plan.InstallOrder -join ',') -ne 'php-windows-runtime,composer,verify-environment') { throw 'Combined install order is incorrect' }
    if (($plan.Verification -join ',') -ne 'php --version,composer --version') { throw 'Combined verification contract is incorrect' }

    $result = Install-DevkitPhpWindowsEnvironment -PhpManifestPath 'php.json' -ComposerManifestPath 'composer.json'
    if (($script:events -join ',') -ne 'runtime,composer,verify') { throw "Unexpected orchestration order: $($script:events -join ',')" }
    if ($result.PhpOutput -ne 'PHP 8.4.99') { throw 'Combined verification result was not returned' }
    $stateFile = Join-Path $State 'php-windows-environment.jsonl'
    if (-not (Select-String -LiteralPath $stateFile -Pattern 'environment-verified' -Quiet)) { throw 'Verified environment state missing' }

    # Composer failure after runtime must be recorded as incomplete and must not verify.
    Remove-Item -LiteralPath $stateFile -Force
    $script:events.Clear()
    $script:failComposer = $true
    $blocked = $false
    try { Install-DevkitPhpWindowsEnvironment -PhpManifestPath 'php.json' -ComposerManifestPath 'composer.json' } catch { $blocked = $true }
    if (-not $blocked) { throw 'Composer component failure unexpectedly succeeded' }
    if (($script:events -join ',') -ne 'runtime,composer') { throw 'Verification ran after Composer failure' }
    if (-not (Select-String -LiteralPath $stateFile -Pattern 'environment-incomplete' -Quiet)) { throw 'Incomplete environment state missing after Composer failure' }

    # Final verification failure must be distinct from component failure.
    Remove-Item -LiteralPath $stateFile -Force
    $script:events.Clear()
    $script:failComposer = $false
    $script:failVerify = $true
    $blocked = $false
    try { Install-DevkitPhpWindowsEnvironment -PhpManifestPath 'php.json' -ComposerManifestPath 'composer.json' } catch { $blocked = $true }
    if (-not $blocked) { throw 'Environment verification failure unexpectedly succeeded' }
    if (($script:events -join ',') -ne 'runtime,composer,verify') { throw 'Unexpected sequence for verification failure' }
    if (-not (Select-String -LiteralPath $stateFile -Pattern 'environment-verification-failed' -Quiet)) { throw 'Verification failure state missing' }

    Write-Host 'Combined PHP Windows orchestration tests passed'
}
finally {
    $env:DEVKIT_WULF_STATE_DIR = $oldState
    Remove-Item -LiteralPath $Temp -Recurse -Force -ErrorAction SilentlyContinue
}
