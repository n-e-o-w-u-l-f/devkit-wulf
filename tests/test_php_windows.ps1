$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$Root = Split-Path -Parent $PSScriptRoot
$Temp = Join-Path ([System.IO.Path]::GetTempPath()) ('devkit-wulf-php-test-' + [guid]::NewGuid().ToString('N'))
$LocalApp = Join-Path $Temp 'localappdata'
$Parent = Join-Path $LocalApp 'devkit-wulf'
$Destination = Join-Path $Parent 'php'
$State = Join-Path $Temp 'state'
$Manifest = Join-Path $Temp 'php-windows.json'
$ReleaseIndex = Join-Path $Temp 'releases.json'
$SourceDir = Join-Path $Temp 'source'
$Archive = Join-Path $Temp 'php.zip'

New-Item -ItemType Directory -Path $Parent, $State, $SourceDir -Force | Out-Null
$oldLocalApp = $env:LOCALAPPDATA
$oldPath = $env:PATH
$oldArch = $env:PROCESSOR_ARCHITECTURE
$oldWow = $env:PROCESSOR_ARCHITEW6432
$oldState = $env:DEVKIT_WULF_STATE_DIR
$env:LOCALAPPDATA = $LocalApp
$env:DEVKIT_WULF_STATE_DIR = $State
$env:PROCESSOR_ARCHITECTURE = 'AMD64'
$env:PROCESSOR_ARCHITEW6432 = $null
$env:PATH = "$Destination;$oldPath"

try {
    Copy-Item -LiteralPath $env:ComSpec -Destination (Join-Path $SourceDir 'php.exe')
    Set-Content -LiteralPath (Join-Path $SourceDir 'php.ini-development') -Value '; fixture' -Encoding ASCII
    Compress-Archive -Path (Join-Path $SourceDir '*') -DestinationPath $Archive
    $ArchiveSha = (Get-FileHash -LiteralPath $Archive -Algorithm SHA256).Hash.ToLowerInvariant()

    @{
        schema_version = 1
        research_date = '2026-08-11'
        publisher = 'PHP Group'
        release_index_url = 'https://windows.php.net/downloads/releases/releases.json'
        download_base_url = 'https://windows.php.net/downloads/releases'
        branch_policy = 'latest-stable-branch'
        version_pattern = '^[0-9]+\.[0-9]+\.[0-9]+$'
        build_pattern = '^nts-vs[0-9]+-x64$'
        target = @{
            platform = 'windows'
            architecture = 'amd64'
            destination_template = '{localappdata}\devkit-wulf\php'
            path_directory_template = '{localappdata}\devkit-wulf\php'
            marker_name = '.devkit-wulf-artifact.json'
            archive_format = 'zip'
            php_executable = 'php.exe'
            integrity = 'sha256-release-metadata'
            thread_safety = 'nts'
            privileged = $false
        }
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Manifest -Encoding UTF8

    @{
        '8.4' = @{
            version = '8.4.99'
            'nts-vs17-x64' = @{
                zip = @{ path = 'php-8.4.99-nts-Win32-vs17-x64.zip'; sha256 = $ArchiveSha }
            }
        }
        '8.3' = @{
            version = '8.3.99'
            'nts-vs16-x64' = @{
                zip = @{ path = 'php-8.3.99-nts-Win32-vs16-x64.zip'; sha256 = ('0' * 64) }
            }
        }
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ReleaseIndex -Encoding UTF8

    function Invoke-DevkitPhpDownload {
        param([string]$Url, [string]$Destination)
        switch ($Url) {
            'https://windows.php.net/downloads/releases/releases.json' { Copy-Item -LiteralPath $ReleaseIndex -Destination $Destination; break }
            'https://windows.php.net/downloads/releases/php-8.4.99-nts-Win32-vs17-x64.zip' { Copy-Item -LiteralPath $Archive -Destination $Destination; break }
            default { throw "Unexpected fixture URL: $Url" }
        }
    }

    . (Join-Path $Root 'lib\php-windows.ps1')

    if ((Get-DevkitPhpWindowsArchitecture) -ne 'amd64') { throw 'Architecture fixture failed' }
    $release = Resolve-DevkitPhpWindowsRelease -ManifestPath $Manifest
    if ($release.Version -ne '8.4.99' -or $release.Build -ne 'nts-vs17-x64') { throw 'Latest stable branch/build resolution failed' }
    if ($release.Sha256 -ne $ArchiveSha) { throw 'Release SHA resolution failed' }

    $plan = Get-DevkitPhpWindowsPlan -ManifestPath $Manifest
    if ($plan.MutatesHost -ne $false -or $plan.ComposerIncluded -ne $false -or $plan.PathMutation -ne $false) { throw 'Plan contract failed' }

    Install-DevkitPhpWindowsRuntime -ManifestPath $Manifest
    $phpExe = Join-Path $Destination 'php.exe'
    $marker = Join-Path $Destination '.devkit-wulf-artifact.json'
    if (-not (Test-Path -LiteralPath $phpExe -PathType Leaf)) { throw 'php.exe was not installed' }
    if (-not (Test-Path -LiteralPath $marker -PathType Leaf)) { throw 'Ownership marker was not installed' }
    $markerData = Get-Content -LiteralPath $marker -Raw | ConvertFrom-Json
    if ($markerData.version -ne '8.4.99' -or $markerData.archive_sha256 -ne $ArchiveSha) { throw 'Marker content mismatch' }

    # Second install must be exact/idempotent.
    Install-DevkitPhpWindowsRuntime -ManifestPath $Manifest
    if (-not (Select-String -LiteralPath (Join-Path $State 'php-windows.jsonl') -Pattern 'observed-exact-artifact' -Quiet)) { throw 'Idempotent observation was not recorded' }

    # Losing ownership marker makes an existing directory a conflict.
    Remove-Item -LiteralPath $marker -Force
    $blocked = $false
    try { Install-DevkitPhpWindowsRuntime -ManifestPath $Manifest } catch { $blocked = $true }
    if (-not $blocked) { throw 'Unowned existing PHP directory was unexpectedly accepted' }

    # Unsupported ARM64 host must fail before install.
    Remove-Item -LiteralPath $Destination -Recurse -Force
    $env:PROCESSOR_ARCHITECTURE = 'ARM64'
    $blocked = $false
    try { Install-DevkitPhpWindowsRuntime -ManifestPath $Manifest } catch { $blocked = $true }
    if (-not $blocked) { throw 'ARM64 host was unexpectedly accepted' }
    $env:PROCESSOR_ARCHITECTURE = 'AMD64'

    # Checksum mismatch must hard fail before destination creation.
    $bad = Get-Content -LiteralPath $ReleaseIndex -Raw | ConvertFrom-Json
    $bad.'8.4'.'nts-vs17-x64'.zip.sha256 = ('f' * 64)
    $bad | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ReleaseIndex -Encoding UTF8
    $blocked = $false
    try { Install-DevkitPhpWindowsRuntime -ManifestPath $Manifest } catch { $blocked = $true }
    if (-not $blocked -or (Test-Path -LiteralPath $Destination)) { throw 'Checksum mismatch did not fail closed' }

    Write-Host 'PHP Windows offline artifact tests passed'
}
finally {
    $env:LOCALAPPDATA = $oldLocalApp
    $env:PATH = $oldPath
    $env:PROCESSOR_ARCHITECTURE = $oldArch
    $env:PROCESSOR_ARCHITEW6432 = $oldWow
    $env:DEVKIT_WULF_STATE_DIR = $oldState
    Remove-Item -LiteralPath $Temp -Recurse -Force -ErrorAction SilentlyContinue
}
