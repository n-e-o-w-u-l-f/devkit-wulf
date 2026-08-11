Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$PhpHelper = Join-Path $PSScriptRoot 'php-windows.ps1'
if (-not (Get-Command Get-DevkitPhpSha256 -CommandType Function -ErrorAction SilentlyContinue)) {
    if (-not (Test-Path -LiteralPath $PhpHelper -PathType Leaf)) { throw "Required PHP Windows helper not found: $PhpHelper" }
    . $PhpHelper
}

function Get-DevkitComposerWindowsManifest {
    param([Parameter(Mandatory = $true)][string]$ManifestPath)
    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) { throw "Composer Windows manifest not found: $ManifestPath" }
    return (Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json)
}

if (-not (Get-Command Invoke-DevkitComposerDownload -CommandType Function -ErrorAction SilentlyContinue)) {
    function Invoke-DevkitComposerDownload {
        param(
            [Parameter(Mandatory = $true)][string]$Url,
            [Parameter(Mandatory = $true)][string]$Destination
        )
        $uri = [Uri]$Url
        if ($uri.Scheme -ne 'https' -or $uri.Host -ne 'getcomposer.org') { throw "GATE-04 blocked non-official Composer URL: $Url" }
        if ($PSVersionTable.PSVersion.Major -lt 6) {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing
        } else {
            Invoke-WebRequest -Uri $Url -OutFile $Destination
        }
    }
}

if (-not (Get-Command Invoke-DevkitComposerVersion -CommandType Function -ErrorAction SilentlyContinue)) {
    function Invoke-DevkitComposerVersion {
        param(
            [Parameter(Mandatory = $true)][string]$PhpExe,
            [Parameter(Mandatory = $true)][string]$ComposerPhar
        )
        $output = & $PhpExe $ComposerPhar '--version' '--no-ansi' 2>&1
        if ($LASTEXITCODE -ne 0) { throw "GATE-12 Composer PHAR failed to execute with managed PHP runtime: $output" }
        return ($output -join "`n")
    }
}

function Get-DevkitComposerExpectedSha {
    param([Parameter(Mandatory = $true)][string]$ChecksumFile)
    $text = (Get-Content -LiteralPath $ChecksumFile -Raw).Trim()
    $token = ($text -split '\s+')[0].ToLowerInvariant()
    if ($token -notmatch '^[0-9a-f]{64}$') { throw 'GATE-05 Composer checksum endpoint returned malformed SHA-256.' }
    return $token
}

function Get-DevkitComposerVersionFromOutput {
    param(
        [Parameter(Mandatory = $true)][string]$Output,
        [Parameter(Mandatory = $true)][string]$Pattern
    )
    if ($Output -notmatch 'Composer version\s+([0-9]+\.[0-9]+\.[0-9]+)') { throw "GATE-12 unable to parse Composer version output: $Output" }
    $version = $Matches[1]
    if ($version -notmatch $Pattern) { throw "GATE-03 Composer version does not satisfy manifest policy: $version" }
    return $version
}

function Assert-DevkitManagedPhpRuntime {
    param(
        [Parameter(Mandatory = $true)][string]$Directory,
        [Parameter(Mandatory = $true)]$Manifest
    )
    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) { throw "GATE-08 managed PHP runtime directory is missing: $Directory" }
    if (Test-DevkitPhpReparsePoint -Path $Directory) { throw "GATE-08 PHP runtime directory is a reparse point: $Directory" }
    $phpExe = Join-Path $Directory ([string]$Manifest.target.php_executable)
    $phpMarker = Join-Path $Directory ([string]$Manifest.target.php_marker)
    if (-not (Test-Path -LiteralPath $phpExe -PathType Leaf) -or (Test-DevkitPhpReparsePoint -Path $phpExe)) { throw 'GATE-08 managed php.exe is missing or unsafe.' }
    if (-not (Test-Path -LiteralPath $phpMarker -PathType Leaf) -or (Test-DevkitPhpReparsePoint -Path $phpMarker)) { throw 'GATE-08 PHP runtime ownership marker is missing or unsafe.' }
    try { $marker = Get-Content -LiteralPath $phpMarker -Raw | ConvertFrom-Json } catch { throw 'GATE-08 PHP runtime ownership marker is invalid JSON.' }
    $phpSha = Get-DevkitPhpSha256 -Path $phpExe
    if ($marker.environment -ne 'php' -or $marker.component -ne 'php-windows-runtime' -or $marker.php_sha256 -ne $phpSha) {
        throw 'GATE-08 PHP runtime marker does not prove ownership of the current php.exe.'
    }
    [pscustomobject]@{ PhpExe = $phpExe; PhpSha256 = $phpSha; PhpVersion = [string]$marker.version }
}

function Get-DevkitComposerStateDirectory {
    if ($env:DEVKIT_WULF_STATE_DIR) { return [System.IO.Path]::GetFullPath($env:DEVKIT_WULF_STATE_DIR) }
    if (-not $env:LOCALAPPDATA) { throw 'LOCALAPPDATA is required for the default devkit-wulf state directory.' }
    return [System.IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'devkit-wulf\state'))
}

function Assert-DevkitComposerStateReady {
    $stateDir = Get-DevkitComposerStateDirectory
    if (Test-DevkitPhpReparsePoint -Path $stateDir) { throw "GATE-10 refuses Composer state-directory reparse point: $stateDir" }
    if (-not (Test-Path -LiteralPath $stateDir)) { New-Item -ItemType Directory -Path $stateDir -Force | Out-Null }
    if (-not (Test-Path -LiteralPath $stateDir -PathType Container)) { throw "Composer state path is not a directory: $stateDir" }
    $stateFile = Join-Path $stateDir 'composer-windows.jsonl'
    if (Test-DevkitPhpReparsePoint -Path $stateFile) { throw "GATE-10 refuses Composer state-file reparse point: $stateFile" }
    if ((Test-Path -LiteralPath $stateFile) -and -not (Test-Path -LiteralPath $stateFile -PathType Leaf)) { throw "Composer state path is not a regular file: $stateFile" }
    return $stateFile
}

function Add-DevkitComposerStateRecord {
    param(
        [Parameter(Mandatory = $true)][string]$Action,
        [Parameter(Mandatory = $true)][string]$Version,
        [Parameter(Mandatory = $true)][string]$SourceUrl,
        [Parameter(Mandatory = $true)][string]$ChecksumUrl,
        [Parameter(Mandatory = $true)][string]$Sha256,
        [Parameter(Mandatory = $true)][string]$Destination,
        [Parameter(Mandatory = $true)][string]$PhpSha256,
        [bool]$Created = $false
    )
    $stateFile = Assert-DevkitComposerStateReady
    [ordered]@{
        timestamp      = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
        environment    = 'php'
        component      = 'composer'
        publisher      = 'Composer'
        action         = $Action
        version        = $Version
        source_url     = $SourceUrl
        checksum_url   = $ChecksumUrl
        sha256         = $Sha256
        destination    = $Destination
        php_sha256     = $PhpSha256
        created        = $Created
        path_mutation  = $false
    } | ConvertTo-Json -Compress | Add-Content -LiteralPath $stateFile -Encoding UTF8
}

function Test-DevkitComposerMarkerMatches {
    param(
        [Parameter(Mandatory = $true)][string]$MarkerPath,
        [Parameter(Mandatory = $true)][string]$PharPath,
        [Parameter(Mandatory = $true)][string]$WrapperPath,
        [Parameter(Mandatory = $true)][string]$ExpectedSha,
        [Parameter(Mandatory = $true)][string]$SourceUrl,
        [Parameter(Mandatory = $true)][string]$PhpSha
    )
    foreach ($path in @($MarkerPath, $PharPath, $WrapperPath)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Test-DevkitPhpReparsePoint -Path $path)) { return $false }
    }
    try { $marker = Get-Content -LiteralPath $MarkerPath -Raw | ConvertFrom-Json } catch { return $false }
    $pharSha = Get-DevkitPhpSha256 -Path $PharPath
    return (
        $marker.environment -eq 'php' -and
        $marker.component -eq 'composer' -and
        $marker.source_url -eq $SourceUrl -and
        $marker.sha256 -eq $ExpectedSha -and
        $marker.sha256 -eq $pharSha -and
        $marker.php_sha256 -eq $PhpSha
    )
}

function Get-DevkitComposerWindowsPlan {
    param([Parameter(Mandatory = $true)][string]$ManifestPath)
    $manifest = Get-DevkitComposerWindowsManifest -ManifestPath $ManifestPath
    if ((Get-DevkitPhpWindowsArchitecture) -ne 'amd64') { throw 'GATE-02 Composer Windows helper currently requires the managed amd64 PHP runtime.' }
    $phpDir = Resolve-DevkitPhpLocalAppDataTemplate -Template $manifest.target.php_directory_template
    $php = Assert-DevkitManagedPhpRuntime -Directory $phpDir -Manifest $manifest
    [pscustomobject]@{
        Environment    = 'php'
        Component      = 'composer'
        Platform       = 'windows'
        Architecture   = 'amd64'
        PharUrl        = [string]$manifest.phar_url
        ChecksumUrl    = [string]$manifest.checksum_url
        Destination    = (Join-Path $phpDir ([string]$manifest.target.phar_name))
        Wrapper        = (Join-Path $phpDir ([string]$manifest.target.wrapper_name))
        PhpExecutable  = $php.PhpExe
        PhpSha256      = $php.PhpSha256
        PathMutation   = $false
        Privilege      = 'none'
        MutatesHost    = $false
        ConflictPolicy = 'refuse-unowned-existing-composer-files-or-reparse-points'
    }
}

function Install-DevkitComposerWindows {
    param([Parameter(Mandatory = $true)][string]$ManifestPath)
    $manifest = Get-DevkitComposerWindowsManifest -ManifestPath $ManifestPath
    if ((Get-DevkitPhpWindowsArchitecture) -ne 'amd64') { throw 'GATE-02 Composer Windows helper currently requires amd64.' }
    $phpDir = Resolve-DevkitPhpLocalAppDataTemplate -Template $manifest.target.php_directory_template
    if (-not (Test-DevkitPhpPathDeclared -Directory $phpDir)) { throw "GATE-13 PATH must already contain managed PHP directory $phpDir" }
    $php = Assert-DevkitManagedPhpRuntime -Directory $phpDir -Manifest $manifest
    Assert-DevkitComposerStateReady | Out-Null

    $phar = Join-Path $phpDir ([string]$manifest.target.phar_name)
    $wrapper = Join-Path $phpDir ([string]$manifest.target.wrapper_name)
    $markerPath = Join-Path $phpDir ([string]$manifest.target.marker_name)
    foreach ($path in @($phar, $wrapper, $markerPath)) {
        if (Test-DevkitPhpReparsePoint -Path $path) { throw "GATE-08 refuses Composer reparse-point destination: $path" }
    }

    $tmpDir = Join-Path $phpDir ('.devkit-wulf-composer.' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmpDir | Out-Null
    try {
        $checksum1 = Join-Path $tmpDir 'composer.sha256.1'
        $checksum2 = Join-Path $tmpDir 'composer.sha256.2'
        $stagedPhar = Join-Path $tmpDir 'composer.phar'
        Invoke-DevkitComposerDownload -Url ([string]$manifest.checksum_url) -Destination $checksum1
        $expected1 = Get-DevkitComposerExpectedSha -ChecksumFile $checksum1
        Invoke-DevkitComposerDownload -Url ([string]$manifest.phar_url) -Destination $stagedPhar
        Invoke-DevkitComposerDownload -Url ([string]$manifest.checksum_url) -Destination $checksum2
        $expected2 = Get-DevkitComposerExpectedSha -ChecksumFile $checksum2
        if ($expected1 -ne $expected2) { throw 'GATE-03/05 Composer stable checksum changed during download; retry with a consistent release.' }
        $actual = Get-DevkitPhpSha256 -Path $stagedPhar
        if ($actual -ne $expected1) { throw 'GATE-05 Composer PHAR SHA-256 mismatch.' }

        $versionOutput = Invoke-DevkitComposerVersion -PhpExe $php.PhpExe -ComposerPhar $stagedPhar
        $version = Get-DevkitComposerVersionFromOutput -Output $versionOutput -Pattern ([string]$manifest.version_pattern)

        if ((Test-Path -LiteralPath $phar) -or (Test-Path -LiteralPath $wrapper) -or (Test-Path -LiteralPath $markerPath)) {
            if (Test-DevkitComposerMarkerMatches -MarkerPath $markerPath -PharPath $phar -WrapperPath $wrapper -ExpectedSha $actual -SourceUrl ([string]$manifest.phar_url) -PhpSha $php.PhpSha256) {
                Add-DevkitComposerStateRecord -Action 'observed-exact-artifact' -Version $version -SourceUrl ([string]$manifest.phar_url) -ChecksumUrl ([string]$manifest.checksum_url) -Sha256 $actual -Destination $phar -PhpSha256 $php.PhpSha256 -Created $false
                return
            }
            throw 'GATE-08 existing Composer files are not the exact devkit-wulf-managed artifact.'
        }

        $wrapperContent = "@echo off`r`n`"%~dp0php.exe`" `"%~dp0composer.phar`" %*`r`n"
        $stagedWrapper = Join-Path $tmpDir 'composer.bat'
        [System.IO.File]::WriteAllText($stagedWrapper, $wrapperContent, [System.Text.Encoding]::ASCII)
        $stagedMarker = Join-Path $tmpDir '.devkit-wulf-composer.json'
        [ordered]@{
            environment = 'php'
            component = 'composer'
            publisher = 'Composer'
            version = $version
            source_url = [string]$manifest.phar_url
            checksum_url = [string]$manifest.checksum_url
            sha256 = $actual
            php_sha256 = $php.PhpSha256
        } | ConvertTo-Json | Set-Content -LiteralPath $stagedMarker -Encoding UTF8

        Add-DevkitComposerStateRecord -Action 'mutation-intent' -Version $version -SourceUrl ([string]$manifest.phar_url) -ChecksumUrl ([string]$manifest.checksum_url) -Sha256 $actual -Destination $phar -PhpSha256 $php.PhpSha256 -Created $false
        Move-Item -LiteralPath $stagedPhar -Destination $phar
        Move-Item -LiteralPath $stagedWrapper -Destination $wrapper
        Move-Item -LiteralPath $stagedMarker -Destination $markerPath
        if ((Get-DevkitPhpSha256 -Path $phar) -ne $actual) { throw 'GATE-12 installed Composer PHAR differs from staged artifact.' }
        $installedOutput = Invoke-DevkitComposerVersion -PhpExe $php.PhpExe -ComposerPhar $phar
        $installedVersion = Get-DevkitComposerVersionFromOutput -Output $installedOutput -Pattern ([string]$manifest.version_pattern)
        if ($installedVersion -ne $version) { throw 'GATE-12 installed Composer version differs from staged artifact.' }
        Add-DevkitComposerStateRecord -Action 'installed-verified-artifact' -Version $version -SourceUrl ([string]$manifest.phar_url) -ChecksumUrl ([string]$manifest.checksum_url) -Sha256 $actual -Destination $phar -PhpSha256 $php.PhpSha256 -Created $true
    } finally {
        Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
