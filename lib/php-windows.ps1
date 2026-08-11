Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-DevkitPhpWindowsManifest {
    param([Parameter(Mandatory = $true)][string]$ManifestPath)
    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) { throw "PHP Windows manifest not found: $ManifestPath" }
    return (Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json)
}

function Get-DevkitPhpWindowsArchitecture {
    $values = @($env:PROCESSOR_ARCHITECTURE, $env:PROCESSOR_ARCHITEW6432) | Where-Object { $_ }
    if ($values -contains 'ARM64') { return 'arm64' }
    if ($values -contains 'AMD64') { return 'amd64' }
    if ($values -contains 'x86') { return 'x86' }
    return 'unknown'
}

function Resolve-DevkitPhpLocalAppDataTemplate {
    param([Parameter(Mandatory = $true)][string]$Template)
    if (-not $env:LOCALAPPDATA) { throw 'LOCALAPPDATA is required for the PHP Windows user-local installation path.' }
    if (-not [System.IO.Path]::IsPathRooted($env:LOCALAPPDATA)) { throw 'LOCALAPPDATA must be an absolute path.' }
    if (-not $Template.StartsWith('{localappdata}\', [System.StringComparison]::OrdinalIgnoreCase)) { throw "Unsupported PHP Windows path template: $Template" }
    $suffix = $Template.Substring('{localappdata}'.Length).TrimStart('\')
    if ($suffix -split '\\' | Where-Object { $_ -eq '..' -or $_ -eq '.' }) { throw "Unsafe PHP Windows path template: $Template" }
    return [System.IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA $suffix))
}

function Test-DevkitPhpReparsePoint {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $item = Get-Item -LiteralPath $Path -Force
    return (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
}

function Test-DevkitPhpPathDeclared {
    param([Parameter(Mandatory = $true)][string]$Directory)
    $expected = [System.IO.Path]::GetFullPath($Directory).TrimEnd('\')
    foreach ($entry in ($env:PATH -split ';')) {
        if (-not $entry) { continue }
        try { $candidate = [System.IO.Path]::GetFullPath($entry).TrimEnd('\') } catch { continue }
        if ([string]::Equals($candidate, $expected, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

if (-not (Get-Command Invoke-DevkitPhpDownload -CommandType Function -ErrorAction SilentlyContinue)) {
    function Invoke-DevkitPhpDownload {
        param(
            [Parameter(Mandatory = $true)][string]$Url,
            [Parameter(Mandatory = $true)][string]$Destination
        )
        $uri = [Uri]$Url
        if ($uri.Scheme -ne 'https') { throw "GATE-04 blocked non-HTTPS PHP URL: $Url" }
        if ($uri.Host -ne 'windows.php.net') { throw "GATE-04 blocked non-official PHP Windows host: $($uri.Host)" }
        if ($PSVersionTable.PSVersion.Major -lt 6) {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing
        } else {
            Invoke-WebRequest -Uri $Url -OutFile $Destination
        }
    }
}

function Get-DevkitPhpSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Resolve-DevkitPhpWindowsRelease {
    param(
        [Parameter(Mandatory = $true)][string]$ManifestPath,
        [string]$Architecture = (Get-DevkitPhpWindowsArchitecture)
    )
    $manifest = Get-DevkitPhpWindowsManifest -ManifestPath $ManifestPath
    if ($Architecture -ne $manifest.target.architecture) { throw "GATE-02 PHP Windows archive supports $($manifest.target.architecture), detected $Architecture" }
    $indexUri = [Uri]$manifest.release_index_url
    if ($indexUri.Scheme -ne 'https' -or $indexUri.Host -ne 'windows.php.net') { throw 'GATE-04 PHP release-index source is not the pinned official Windows PHP service.' }

    $tmp = [System.IO.Path]::GetTempFileName()
    try {
        Invoke-DevkitPhpDownload -Url $manifest.release_index_url -Destination $tmp
        $index = Get-Content -LiteralPath $tmp -Raw | ConvertFrom-Json
    } finally {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }

    $branches = @($index.PSObject.Properties | Where-Object { $_.Name -match '^\d+\.\d+$' } | Sort-Object { [version]$_.Name } -Descending)
    if ($branches.Count -eq 0) { throw 'GATE-03 PHP release index contains no stable numeric branches.' }
    $branch = $branches[0]
    $release = $branch.Value
    $version = [string]$release.version
    if ($version -notmatch $manifest.version_pattern) { throw "GATE-03 rejected PHP version from release metadata: $version" }
    if (-not $version.StartsWith($branch.Name + '.', [System.StringComparison]::Ordinal)) { throw "GATE-03 PHP release version does not match selected branch $($branch.Name)" }

    $builds = @($release.PSObject.Properties | Where-Object { $_.Name -match $manifest.build_pattern } | Sort-Object {
        if ($_.Name -match 'vs(\d+)') { [int]$Matches[1] } else { 0 }
    } -Descending)
    if ($builds.Count -eq 0) { throw 'GATE-03 PHP release contains no x64 NTS Windows ZIP build.' }
    $build = $builds[0]
    $zip = $build.Value.zip
    if (-not $zip) { throw "GATE-03 PHP build $($build.Name) has no ZIP metadata." }
    $relativePath = [string]$zip.path
    $sha256 = ([string]$zip.sha256).ToLowerInvariant()
    if ($relativePath -notmatch '^[A-Za-z0-9._+-]+\.zip$') { throw "GATE-04 rejected unsafe PHP archive path: $relativePath" }
    if ($sha256 -notmatch '^[0-9a-f]{64}$') { throw 'GATE-05 PHP release metadata contains malformed SHA-256.' }

    $base = ([string]$manifest.download_base_url).TrimEnd('/')
    $archiveUrl = "$base/$relativePath"
    $archiveUri = [Uri]$archiveUrl
    if ($archiveUri.Scheme -ne 'https' -or $archiveUri.Host -ne 'windows.php.net') { throw 'GATE-04 resolved PHP archive URL is outside windows.php.net.' }

    [pscustomobject]@{
        Branch       = [string]$branch.Name
        Version      = $version
        Build        = [string]$build.Name
        ArchiveUrl   = $archiveUrl
        ArchiveName  = $relativePath
        Sha256       = $sha256
        ReleaseIndex = [string]$manifest.release_index_url
    }
}

function Test-DevkitPhpZipSafe {
    param(
        [Parameter(Mandatory = $true)][string]$Archive,
        [Parameter(Mandatory = $true)][string]$DestinationRoot
    )
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $root = [System.IO.Path]::GetFullPath($DestinationRoot).TrimEnd('\') + '\'
    $zip = [System.IO.Compression.ZipFile]::OpenRead($Archive)
    try {
        foreach ($entry in $zip.Entries) {
            $name = [string]$entry.FullName
            if (-not $name) { continue }
            if ($name.StartsWith('/') -or $name.StartsWith('\') -or $name.Contains('\') -or $name.Contains(':')) { return $false }
            $segments = $name -split '/'
            if ($segments | Where-Object { $_ -eq '..' -or $_ -eq '.' }) { return $false }
            $candidate = [System.IO.Path]::GetFullPath((Join-Path $DestinationRoot ($name -replace '/', '\')))
            if (-not $candidate.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase) -and -not [string]::Equals($candidate.TrimEnd('\'), $root.TrimEnd('\'), [System.StringComparison]::OrdinalIgnoreCase)) { return $false }
        }
    } finally {
        $zip.Dispose()
    }
    return $true
}

function Get-DevkitPhpStateDirectory {
    if ($env:DEVKIT_WULF_STATE_DIR) { return [System.IO.Path]::GetFullPath($env:DEVKIT_WULF_STATE_DIR) }
    if (-not $env:LOCALAPPDATA) { throw 'LOCALAPPDATA is required for the default devkit-wulf state directory.' }
    return [System.IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'devkit-wulf\state'))
}

function Assert-DevkitPhpStateReady {
    $stateDir = Get-DevkitPhpStateDirectory
    if (Test-DevkitPhpReparsePoint -Path $stateDir) { throw "GATE-10 refuses state-directory reparse point: $stateDir" }
    if (-not (Test-Path -LiteralPath $stateDir)) { New-Item -ItemType Directory -Path $stateDir -Force | Out-Null }
    if (-not (Test-Path -LiteralPath $stateDir -PathType Container)) { throw "State path is not a directory: $stateDir" }
    $stateFile = Join-Path $stateDir 'php-windows.jsonl'
    if (Test-DevkitPhpReparsePoint -Path $stateFile) { throw "GATE-10 refuses state-file reparse point: $stateFile" }
    if ((Test-Path -LiteralPath $stateFile) -and -not (Test-Path -LiteralPath $stateFile -PathType Leaf)) { throw "State path is not a regular file: $stateFile" }
    return $stateFile
}

function Add-DevkitPhpStateRecord {
    param(
        [Parameter(Mandatory = $true)][string]$Action,
        [Parameter(Mandatory = $true)]$Release,
        [Parameter(Mandatory = $true)][string]$Destination,
        [string]$PhpSha256 = '',
        [bool]$Created = $false
    )
    $stateFile = Assert-DevkitPhpStateReady
    $record = [ordered]@{
        timestamp       = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
        environment     = 'php'
        component       = 'php-windows-runtime'
        publisher       = 'PHP Group'
        action          = $Action
        branch          = $Release.Branch
        version         = $Release.Version
        build           = $Release.Build
        source_url      = $Release.ArchiveUrl
        release_index   = $Release.ReleaseIndex
        archive_sha256  = $Release.Sha256
        php_sha256      = $PhpSha256
        destination     = $Destination
        created         = $Created
        path_mutation   = $false
    }
    ($record | ConvertTo-Json -Compress) | Add-Content -LiteralPath $stateFile -Encoding UTF8
}

function Test-DevkitPhpMarkerMatches {
    param(
        [Parameter(Mandatory = $true)][string]$Marker,
        [Parameter(Mandatory = $true)][string]$PhpExe,
        [Parameter(Mandatory = $true)]$Release
    )
    if (-not (Test-Path -LiteralPath $Marker -PathType Leaf) -or (Test-DevkitPhpReparsePoint -Path $Marker)) { return $false }
    if (-not (Test-Path -LiteralPath $PhpExe -PathType Leaf) -or (Test-DevkitPhpReparsePoint -Path $PhpExe)) { return $false }
    try { $markerData = Get-Content -LiteralPath $Marker -Raw | ConvertFrom-Json } catch { return $false }
    $currentPhpSha = Get-DevkitPhpSha256 -Path $PhpExe
    return (
        $markerData.environment -eq 'php' -and
        $markerData.component -eq 'php-windows-runtime' -and
        $markerData.version -eq $Release.Version -and
        $markerData.source_url -eq $Release.ArchiveUrl -and
        $markerData.archive_sha256 -eq $Release.Sha256 -and
        $markerData.php_sha256 -eq $currentPhpSha
    )
}

function Get-DevkitPhpWindowsPlan {
    param([Parameter(Mandatory = $true)][string]$ManifestPath)
    $manifest = Get-DevkitPhpWindowsManifest -ManifestPath $ManifestPath
    $arch = Get-DevkitPhpWindowsArchitecture
    $release = Resolve-DevkitPhpWindowsRelease -ManifestPath $ManifestPath -Architecture $arch
    $destination = Resolve-DevkitPhpLocalAppDataTemplate -Template $manifest.target.destination_template
    [pscustomobject]@{
        Environment      = 'php'
        Component        = 'php-windows-runtime'
        Platform         = 'windows'
        Architecture     = $arch
        ThreadSafety     = 'nts'
        Version          = $release.Version
        Build            = $release.Build
        ReleaseIndex     = $release.ReleaseIndex
        ArchiveUrl       = $release.ArchiveUrl
        ExpectedSha256   = $release.Sha256
        Destination      = $destination
        PathMutation     = $false
        Privilege        = 'none'
        ConflictPolicy   = 'refuse-unowned-existing-directory-or-reparse-point'
        ComposerIncluded = $false
        MutatesHost      = $false
    }
}

function Install-DevkitPhpWindowsRuntime {
    param([Parameter(Mandatory = $true)][string]$ManifestPath)
    $manifest = Get-DevkitPhpWindowsManifest -ManifestPath $ManifestPath
    $arch = Get-DevkitPhpWindowsArchitecture
    if ($arch -ne 'amd64') { throw "GATE-02 PHP Windows runtime adapter supports amd64 only, detected $arch" }
    $destination = Resolve-DevkitPhpLocalAppDataTemplate -Template $manifest.target.destination_template
    $pathDirectory = Resolve-DevkitPhpLocalAppDataTemplate -Template $manifest.target.path_directory_template
    $parent = Split-Path -Parent $destination
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { throw "GATE-08 PHP install parent must already exist: $parent" }
    if (Test-DevkitPhpReparsePoint -Path $parent) { throw "GATE-08 refuses PHP install parent reparse point: $parent" }
    if (-not (Test-DevkitPhpPathDeclared -Directory $pathDirectory)) { throw "GATE-13 PATH must already contain $pathDirectory; devkit-wulf will not modify PATH implicitly" }
    Assert-DevkitPhpStateReady | Out-Null

    $release = Resolve-DevkitPhpWindowsRelease -ManifestPath $ManifestPath -Architecture $arch
    $markerName = [string]$manifest.target.marker_name
    $marker = Join-Path $destination $markerName
    $phpExe = Join-Path $destination ([string]$manifest.target.php_executable)

    if ((Test-Path -LiteralPath $destination) -or (Test-DevkitPhpReparsePoint -Path $destination)) {
        if (Test-DevkitPhpReparsePoint -Path $destination) { throw "GATE-08 PHP destination is a reparse point: $destination" }
        if (-not (Test-Path -LiteralPath $destination -PathType Container)) { throw "GATE-08 PHP destination exists and is not a directory: $destination" }
        if (Test-DevkitPhpMarkerMatches -Marker $marker -PhpExe $phpExe -Release $release) {
            Add-DevkitPhpStateRecord -Action 'observed-exact-artifact' -Release $release -Destination $destination -PhpSha256 (Get-DevkitPhpSha256 -Path $phpExe) -Created $false
            return
        }
        throw 'GATE-08 existing PHP directory is not the exact devkit-wulf-managed runtime.'
    }

    $stage = Join-Path $parent ('.devkit-wulf-php.' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $stage | Out-Null
    try {
        $archive = Join-Path $stage $release.ArchiveName
        Invoke-DevkitPhpDownload -Url $release.ArchiveUrl -Destination $archive
        $actualSha = Get-DevkitPhpSha256 -Path $archive
        if ($actualSha -ne $release.Sha256) { throw 'GATE-05 PHP Windows archive SHA-256 mismatch.' }

        $extract = Join-Path $stage 'extracted'
        New-Item -ItemType Directory -Path $extract | Out-Null
        if (-not (Test-DevkitPhpZipSafe -Archive $archive -DestinationRoot $extract)) { throw 'GATE-05/08 rejected unsafe PHP ZIP contents.' }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($archive, $extract)
        $stagedPhp = Join-Path $extract ([string]$manifest.target.php_executable)
        if (-not (Test-Path -LiteralPath $stagedPhp -PathType Leaf) -or (Test-DevkitPhpReparsePoint -Path $stagedPhp)) { throw 'GATE-12 extracted php.exe is missing or unsafe.' }
        $phpSha = Get-DevkitPhpSha256 -Path $stagedPhp

        $markerPath = Join-Path $extract $markerName
        [ordered]@{
            environment     = 'php'
            component       = 'php-windows-runtime'
            version         = $release.Version
            build           = $release.Build
            source_url      = $release.ArchiveUrl
            release_index   = $release.ReleaseIndex
            archive_sha256  = $release.Sha256
            php_sha256      = $phpSha
        } | ConvertTo-Json | Set-Content -LiteralPath $markerPath -Encoding UTF8

        Add-DevkitPhpStateRecord -Action 'mutation-intent' -Release $release -Destination $destination -PhpSha256 $phpSha -Created $false
        Move-Item -LiteralPath $extract -Destination $destination
        $installedPhp = Join-Path $destination ([string]$manifest.target.php_executable)
        if ((Get-DevkitPhpSha256 -Path $installedPhp) -ne $phpSha) { throw 'GATE-12 installed php.exe differs from the verified staged executable.' }
        Add-DevkitPhpStateRecord -Action 'installed-verified-artifact' -Release $release -Destination $destination -PhpSha256 $phpSha -Created $true
    } finally {
        Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    }
}
