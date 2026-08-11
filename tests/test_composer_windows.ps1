$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$Root = Split-Path -Parent $PSScriptRoot
$Temp = Join-Path ([System.IO.Path]::GetTempPath()) ('devkit-wulf-composer-test-' + [guid]::NewGuid().ToString('N'))
$LocalApp = Join-Path $Temp 'localappdata'
$PhpDir = Join-Path $LocalApp 'devkit-wulf\php'
$State = Join-Path $Temp 'state'
$Manifest = Join-Path $Temp 'composer-windows.json'
$PharSource = Join-Path $Temp 'composer.phar'

New-Item -ItemType Directory -Path $PhpDir, $State -Force | Out-Null
$oldLocalApp = $env:LOCALAPPDATA
$oldPath = $env:PATH
$oldArch = $env:PROCESSOR_ARCHITECTURE
$oldWow = $env:PROCESSOR_ARCHITEW6432
$oldState = $env:DEVKIT_WULF_STATE_DIR
$env:LOCALAPPDATA = $LocalApp
$env:DEVKIT_WULF_STATE_DIR = $State
$env:PROCESSOR_ARCHITECTURE = 'AMD64'
$env:PROCESSOR_ARCHITEW6432 = $null
$env:PATH = "$PhpDir;$oldPath"

try {
    $phpExe = Join-Path $PhpDir 'php.exe'
    Copy-Item -LiteralPath $env:ComSpec -Destination $phpExe
    $phpSha = (Get-FileHash -LiteralPath $phpExe -Algorithm SHA256).Hash.ToLowerInvariant()
    [ordered]@{
        environment = 'php'
        component = 'php-windows-runtime'
        version = '8.4.99'
        build = 'nts-vs17-x64'
        source_url = 'https://windows.php.net/downloads/releases/php-8.4.99-nts-Win32-vs17-x64.zip'
        archive_sha256 = ('a' * 64)
        php_sha256 = $phpSha
    } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PhpDir '.devkit-wulf-artifact.json') -Encoding UTF8

    Set-Content -LiteralPath $PharSource -Value 'fixture composer phar bytes' -Encoding ASCII
    $pharSha = (Get-FileHash -LiteralPath $PharSource -Algorithm SHA256).Hash.ToLowerInvariant()

    @{
        schema_version = 1
        research_date = '2026-08-11'
        publisher = 'Composer'
        phar_url = 'https://getcomposer.org/download/latest-stable/composer.phar'
        checksum_url = 'https://getcomposer.org/download/latest-stable/composer.phar.sha256sum'
        version_pattern = '^[0-9]+\.[0-9]+\.[0-9]+$'
        target = @{
            platform = 'windows'
            architecture = 'amd64'
            php_directory_template = '{localappdata}\devkit-wulf\php'
            php_executable = 'php.exe'
            php_marker = '.devkit-wulf-artifact.json'
            phar_name = 'composer.phar'
            wrapper_name = 'composer.bat'
            marker_name = '.devkit-wulf-composer.json'
            integrity = 'sha256-double-read'
            privileged = $false
            path_mutation = $false
        }
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Manifest -Encoding UTF8

    $script:checksumCalls = 0
    function Invoke-DevkitComposerDownload {
        param([string]$Url, [string]$Destination)
        switch ($Url) {
            'https://getcomposer.org/download/latest-stable/composer.phar.sha256sum' {
                $script:checksumCalls++
                Set-Content -LiteralPath $Destination -Value "$pharSha  composer.phar" -Encoding ASCII
                break
            }
            'https://getcomposer.org/download/latest-stable/composer.phar' {
                Copy-Item -LiteralPath $PharSource -Destination $Destination
                break
            }
            default { throw "Unexpected Composer fixture URL: $Url" }
        }
    }
    function Invoke-DevkitComposerVersion {
        param([string]$PhpExe, [string]$ComposerPhar)
        if (-not (Test-Path -LiteralPath $PhpExe -PathType Leaf)) { throw 'Fixture managed PHP missing' }
        if (-not (Test-Path -LiteralPath $ComposerPhar -PathType Leaf)) { throw 'Fixture Composer PHAR missing' }
        return 'Composer version 2.9.99 2026-08-11 00:00:00'
    }

    . (Join-Path $Root 'lib\composer-windows.ps1')

    $plan = Get-DevkitComposerWindowsPlan -ManifestPath $Manifest
    if ($plan.MutatesHost -ne $false -or $plan.PathMutation -ne $false -or $plan.Privilege -ne 'none') { throw 'Composer plan contract failed' }
    if ($plan.PhpSha256 -ne $phpSha) { throw 'Composer plan did not bind to managed PHP hash' }

    Install-DevkitComposerWindows -ManifestPath $Manifest
    $phar = Join-Path $PhpDir 'composer.phar'
    $wrapper = Join-Path $PhpDir 'composer.bat'
    $marker = Join-Path $PhpDir '.devkit-wulf-composer.json'
    foreach ($path in @($phar, $wrapper, $marker)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Composer install artifact missing: $path" }
    }
    if ((Get-FileHash -LiteralPath $phar -Algorithm SHA256).Hash.ToLowerInvariant() -ne $pharSha) { throw 'Installed Composer PHAR hash mismatch' }
    if (-not (Select-String -LiteralPath $wrapper -Pattern '%~dp0php.exe' -Quiet)) { throw 'Composer wrapper does not bind to adjacent managed php.exe' }
    $markerData = Get-Content -LiteralPath $marker -Raw | ConvertFrom-Json
    if ($markerData.version -ne '2.9.99' -or $markerData.sha256 -ne $pharSha -or $markerData.php_sha256 -ne $phpSha) { throw 'Composer marker mismatch' }
    if ($script:checksumCalls -ne 2) { throw 'Composer checksum was not double-read' }

    # Exact second install must be idempotent.
    Install-DevkitComposerWindows -ManifestPath $Manifest
    if (-not (Select-String -LiteralPath (Join-Path $State 'composer-windows.jsonl') -Pattern 'observed-exact-artifact' -Quiet)) { throw 'Composer idempotent observation missing' }

    # Mutating the managed PHP runtime invalidates Composer ownership binding.
    Add-Content -LiteralPath $phpExe -Value 'changed'
    $blocked = $false
    try { Install-DevkitComposerWindows -ManifestPath $Manifest } catch { $blocked = $true }
    if (-not $blocked) { throw 'Composer unexpectedly accepted modified managed PHP runtime' }

    # Restore PHP ownership, remove Composer, then simulate stable-release checksum rotation.
    Copy-Item -LiteralPath $env:ComSpec -Destination $phpExe -Force
    $phpSha = (Get-FileHash -LiteralPath $phpExe -Algorithm SHA256).Hash.ToLowerInvariant()
    $phpMarker = Get-Content -LiteralPath (Join-Path $PhpDir '.devkit-wulf-artifact.json') -Raw | ConvertFrom-Json
    $phpMarker.php_sha256 = $phpSha
    $phpMarker | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PhpDir '.devkit-wulf-artifact.json') -Encoding UTF8
    Remove-Item -LiteralPath $phar, $wrapper, $marker -Force

    $script:checksumCalls = 0
    function Invoke-DevkitComposerDownload {
        param([string]$Url, [string]$Destination)
        switch ($Url) {
            'https://getcomposer.org/download/latest-stable/composer.phar.sha256sum' {
                $script:checksumCalls++
                if ($script:checksumCalls -eq 1) { $value = $pharSha } else { $value = ('f' * 64) }
                Set-Content -LiteralPath $Destination -Value "$value  composer.phar" -Encoding ASCII
                break
            }
            'https://getcomposer.org/download/latest-stable/composer.phar' { Copy-Item -LiteralPath $PharSource -Destination $Destination; break }
            default { throw "Unexpected Composer fixture URL: $Url" }
        }
    }
    $blocked = $false
    try { Install-DevkitComposerWindows -ManifestPath $Manifest } catch { $blocked = $true }
    if (-not $blocked -or (Test-Path -LiteralPath $phar)) { throw 'Composer stable checksum rotation did not fail closed' }

    # Unowned Composer files must not be adopted.
    Set-Content -LiteralPath $phar -Value 'foreign composer' -Encoding ASCII
    $blocked = $false
    try { Install-DevkitComposerWindows -ManifestPath $Manifest } catch { $blocked = $true }
    if (-not $blocked) { throw 'Unowned Composer file was unexpectedly adopted' }

    Write-Host 'Composer Windows offline PHAR tests passed'
}
finally {
    $env:LOCALAPPDATA = $oldLocalApp
    $env:PATH = $oldPath
    $env:PROCESSOR_ARCHITECTURE = $oldArch
    $env:PROCESSOR_ARCHITEW6432 = $oldWow
    $env:DEVKIT_WULF_STATE_DIR = $oldState
    Remove-Item -LiteralPath $Temp -Recurse -Force -ErrorAction SilentlyContinue
}
