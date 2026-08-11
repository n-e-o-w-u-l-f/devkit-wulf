Set-StrictMode -Version Latest

function Get-DevkitFlutterWindowsManifest {
    param([Parameter(Mandatory = $true)][string]$ManifestPath)
    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) { throw "Flutter Windows manifest not found: $ManifestPath" }
    return Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-DevkitFlutterWindowsArchitecture {
    $arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLowerInvariant()
    switch ($arch) {
        'x64' { return 'amd64' }
        'arm64' { return 'arm64' }
        'x86' { return '386' }
        default { return $arch }
    }
}

function Assert-DevkitFlutterWindowsTarget {
    param(
        [Parameter(Mandatory = $true)][object]$Manifest,
        [Parameter(Mandatory = $true)][string]$Architecture
    )
    if ($Manifest.support -ne 'experimental') { throw 'GATE-02 Flutter Windows contract must remain experimental.' }
    if ($Architecture -ne [string]$Manifest.target.architecture) {
        throw "GATE-02 Flutter Windows adapter does not support architecture '$Architecture'."
    }
}

function Get-DevkitFlutterWindowsHome {
    $candidate = [string]$HOME
    if ([string]::IsNullOrWhiteSpace($candidate)) { $candidate = [Environment]::GetFolderPath('UserProfile') }
    if ([string]::IsNullOrWhiteSpace($candidate) -or -not [IO.Path]::IsPathRooted($candidate)) {
        throw 'Unable to resolve an absolute Windows user home directory.'
    }
    return [IO.Path]::GetFullPath($candidate)
}

function Resolve-DevkitFlutterWindowsHomeTemplate {
    param(
        [Parameter(Mandatory = $true)][string]$Template,
        [string]$HomePath = (Get-DevkitFlutterWindowsHome)
    )
    if (-not $Template.StartsWith('{home}/', [StringComparison]::Ordinal)) { throw "Unsafe Flutter Windows home template: $Template" }
    $home = [IO.Path]::GetFullPath($HomePath)
    $relative = $Template.Substring(7).Replace('/', [IO.Path]::DirectorySeparatorChar)
    if ($relative -split '[\\/]' -contains '..') { throw "Unsafe Flutter Windows template traversal: $Template" }
    $resolved = [IO.Path]::GetFullPath((Join-Path $home $relative))
    $prefix = $home.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (-not $resolved.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw "Flutter Windows template escapes user home: $Template" }
    return $resolved
}

function Test-DevkitFlutterWindowsReparsePoint {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $item = Get-Item -LiteralPath $Path -Force
    return (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)
}

function Get-DevkitFlutterWindowsStateDirectory {
    if ($env:DEVKIT_WULF_STATE_DIR) { return [IO.Path]::GetFullPath($env:DEVKIT_WULF_STATE_DIR) }
    if (-not $env:LOCALAPPDATA) { throw 'LOCALAPPDATA is required when DEVKIT_WULF_STATE_DIR is not set.' }
    return [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'devkit-wulf'))
}

function Assert-DevkitFlutterWindowsStateReady {
    param([Parameter(Mandatory = $true)][string]$StateDirectory)
    $state = [IO.Path]::GetFullPath($StateDirectory)
    if (Test-DevkitFlutterWindowsReparsePoint $state) { throw "GATE-10 refuses Flutter Windows state-directory reparse point: $state" }
    if (-not (Test-Path -LiteralPath $state)) { New-Item -ItemType Directory -Path $state -Force | Out-Null }
    if (-not (Test-Path -LiteralPath $state -PathType Container)) { throw "GATE-10 Flutter Windows state path is not a directory: $state" }
    $file = Join-Path $state 'flutter-windows.jsonl'
    if (Test-DevkitFlutterWindowsReparsePoint $file) { throw "GATE-10 refuses Flutter Windows state-file reparse point: $file" }
    if ((Test-Path -LiteralPath $file) -and -not (Test-Path -LiteralPath $file -PathType Leaf)) {
        throw "GATE-10 Flutter Windows state path is not a regular file: $file"
    }
    return $file
}

function Add-DevkitFlutterWindowsStateRecord {
    param(
        [Parameter(Mandatory = $true)][string]$StateDirectory,
        [Parameter(Mandatory = $true)][string]$Action,
        [string]$Version = '',
        [string]$SourceUrl = '',
        [string]$ArchiveSha256 = '',
        [string]$Destination = '',
        [bool]$Created = $false
    )
    $stateFile = Assert-DevkitFlutterWindowsStateReady -StateDirectory $StateDirectory
    $record = [ordered]@{
        timestamp = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
        environment = 'flutter'
        platform = 'windows'
        publisher = 'Flutter Authors / Google'
        action = $Action
        version = $Version
        source_url = $SourceUrl
        archive_sha256 = $ArchiveSha256
        destination = $Destination
        created = $Created
        path_mutation = $false
        privileged = $false
    }
    ($record | ConvertTo-Json -Compress) | Add-Content -LiteralPath $stateFile -Encoding UTF8
}

function Invoke-DevkitFlutterWindowsDownload {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][string]$Destination
    )
    $parsed = [Uri]$Uri
    if ($parsed.Scheme -ne 'https') { throw "GATE-04 blocked non-HTTPS Flutter URL: $Uri" }
    Invoke-WebRequest -Uri $parsed -OutFile $Destination -UseBasicParsing
}

function Get-DevkitFlutterWindowsSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Test-DevkitFlutterWindowsVersion {
    param(
        [Parameter(Mandatory = $true)][string]$Version,
        [Parameter(Mandatory = $true)][string]$Pattern
    )
    if ($Version -match '[\\/:]') { return $false }
    return [regex]::IsMatch($Version, $Pattern)
}

function Test-DevkitFlutterWindowsArchivePath {
    param(
        [Parameter(Mandatory = $true)][string]$ArchivePath,
        [Parameter(Mandatory = $true)][string]$Pattern
    )
    if ([string]::IsNullOrWhiteSpace($ArchivePath)) { return $false }
    if ($ArchivePath.StartsWith('/') -or $ArchivePath.Contains('\') -or $ArchivePath.Contains(':')) { return $false }
    if ($ArchivePath -split '/' -contains '..') { return $false }
    return [regex]::IsMatch($ArchivePath, $Pattern)
}

function Get-DevkitFlutterWindowsRelease {
    param(
        [Parameter(Mandatory = $true)][string]$ManifestPath,
        [string]$Architecture = (Get-DevkitFlutterWindowsArchitecture)
    )
    $manifest = Get-DevkitFlutterWindowsManifest -ManifestPath $ManifestPath
    Assert-DevkitFlutterWindowsTarget -Manifest $manifest -Architecture $Architecture

    $indexUri = [Uri][string]$manifest.release_index_url
    if ($indexUri.AbsoluteUri -ne 'https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json') {
        throw 'GATE-04 Flutter Windows release index is not the pinned official endpoint.'
    }

    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("devkit-wulf-flutter-windows-index-{0}.json" -f [guid]::NewGuid().ToString('N'))
    try {
        Invoke-DevkitFlutterWindowsDownload -Uri $indexUri.AbsoluteUri -Destination $tmp
        $index = Get-Content -LiteralPath $tmp -Raw -Encoding UTF8 | ConvertFrom-Json
    } finally {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }

    $base = [string]$index.base_url
    if ($base -ne [string]$manifest.expected_base_url) { throw 'GATE-04 Flutter release-index base_url does not match the pinned official release base.' }
    $stableHash = [string]$index.current_release.stable
    if ([string]::IsNullOrWhiteSpace($stableHash)) { throw 'GATE-03 Flutter Windows release index has no current stable hash.' }

    $releaseArch = [string]$manifest.target.release_architecture
    $matches = @($index.releases | Where-Object {
        [string]$_.hash -eq $stableHash -and [string]$_.channel -eq 'stable' -and [string]$_.dart_sdk_arch -eq $releaseArch
    })
    if ($matches.Count -ne 1) { throw "GATE-03 expected exactly one current stable Flutter Windows/$releaseArch release; got $($matches.Count)." }
    $release = $matches[0]

    $version = [string]$release.version
    if (-not (Test-DevkitFlutterWindowsVersion -Version $version -Pattern ([string]$manifest.version_pattern))) {
        throw "GATE-03 rejected unsafe Flutter Windows version: $version"
    }
    $archive = [string]$release.archive
    if (-not (Test-DevkitFlutterWindowsArchivePath -ArchivePath $archive -Pattern ([string]$manifest.target.archive_path_pattern))) {
        throw "GATE-03 rejected unsafe Flutter Windows archive path: $archive"
    }
    $sha = ([string]$release.sha256).ToLowerInvariant()
    if ($sha -notmatch '^[0-9a-f]{64}$') { throw 'GATE-05 Flutter Windows release metadata contains malformed SHA-256.' }

    $source = "$base/$archive"
    $sourceUri = [Uri]$source
    if ($sourceUri.Scheme -ne 'https' -or $sourceUri.Host -ne 'storage.googleapis.com' -or -not $sourceUri.AbsolutePath.StartsWith('/flutter_infra_release/releases/', [StringComparison]::Ordinal)) {
        throw 'GATE-04 Flutter Windows archive URL escaped the official release host/prefix.'
    }

    return [pscustomobject]@{
        Version = $version
        Hash = $stableHash
        ReleaseArchitecture = $releaseArch
        Archive = $archive
        SourceUrl = $source
        Sha256 = $sha
        BaseUrl = $base
    }
}

function Assert-DevkitFlutterWindowsPathPrerequisites {
    param(
        [Parameter(Mandatory = $true)][object]$Manifest,
        [string]$HomePath = (Get-DevkitFlutterWindowsHome)
    )
    $destination = Resolve-DevkitFlutterWindowsHomeTemplate -Template ([string]$Manifest.target.destination_template) -HomePath $HomePath
    $pathDirectory = Resolve-DevkitFlutterWindowsHomeTemplate -Template ([string]$Manifest.target.path_directory_template) -HomePath $HomePath
    $parent = Split-Path -Parent $destination
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { throw "GATE-08 Flutter Windows install parent must already exist: $parent" }
    if (Test-DevkitFlutterWindowsReparsePoint $parent) { throw "GATE-08 Flutter Windows install parent is a reparse point: $parent" }

    $normalizedPath = [IO.Path]::GetFullPath($pathDirectory).TrimEnd('\')
    $present = $false
    foreach ($entry in ([string]$env:PATH -split ';')) {
        if ([string]::IsNullOrWhiteSpace($entry)) { continue }
        try { $candidate = [IO.Path]::GetFullPath($entry).TrimEnd('\') } catch { continue }
        if ($candidate.Equals($normalizedPath, [StringComparison]::OrdinalIgnoreCase)) { $present = $true; break }
    }
    if (-not $present) { throw "GATE-13 PATH must already contain $pathDirectory; devkit-wulf will not modify PATH implicitly." }

    return [pscustomobject]@{
        Destination = $destination
        PathDirectory = $pathDirectory
        Parent = $parent
        Marker = Join-Path $destination ([string]$Manifest.target.marker_relative_path)
    }
}

function Test-DevkitFlutterWindowsZipSafe {
    param(
        [Parameter(Mandatory = $true)][string]$ArchivePath,
        [Parameter(Mandatory = $true)][object]$Manifest
    )
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($ArchivePath)
    try {
        $root = [string]$Manifest.target.root_directory
        $required = @{}
        foreach ($critical in @($Manifest.target.critical_files)) { $required[("$root/$critical")] = $false }
        foreach ($entry in $zip.Entries) {
            $name = [string]$entry.FullName
            if ([string]::IsNullOrWhiteSpace($name)) { return $false }
            if ($name.StartsWith('/') -or $name.StartsWith('\') -or $name.Contains('\') -or $name -match '^[A-Za-z]:') { return $false }
            $parts = @($name -split '/')
            if ($parts.Count -lt 1 -or $parts[0] -ne $root -or $parts -contains '..') { return $false }
            $unixType = (($entry.ExternalAttributes -shr 16) -band 0xF000)
            if ($unixType -eq 0xA000) { return $false }
            if (($entry.ExternalAttributes -band 0x400) -ne 0) { return $false }
            if ($required.ContainsKey($name)) {
                if ([string]::IsNullOrEmpty($entry.Name)) { return $false }
                $required[$name] = $true
            }
        }
        foreach ($value in $required.Values) { if (-not $value) { return $false } }
        return $true
    } finally {
        $zip.Dispose()
    }
}

function Get-DevkitFlutterWindowsCriticalHashes {
    param(
        [Parameter(Mandatory = $true)][string]$SdkRoot,
        [Parameter(Mandatory = $true)][object]$Manifest
    )
    $hashes = [ordered]@{}
    foreach ($relative in @($Manifest.target.critical_files)) {
        $native = ([string]$relative).Replace('/', [IO.Path]::DirectorySeparatorChar)
        $path = Join-Path $SdkRoot $native
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "GATE-12 Flutter Windows critical file missing: $relative" }
        if (Test-DevkitFlutterWindowsReparsePoint $path) { throw "GATE-12 Flutter Windows critical file is a reparse point: $relative" }
        $hashes[[string]$relative] = Get-DevkitFlutterWindowsSha256 -Path $path
    }
    return $hashes
}

function Test-DevkitFlutterWindowsManagedVerification {
    param(
        [Parameter(Mandatory = $true)][string]$ManifestPath,
        [string]$HomePath = (Get-DevkitFlutterWindowsHome)
    )
    try {
        $manifest = Get-DevkitFlutterWindowsManifest -ManifestPath $ManifestPath
        Assert-DevkitFlutterWindowsTarget -Manifest $manifest -Architecture 'amd64'
        $destination = Resolve-DevkitFlutterWindowsHomeTemplate -Template ([string]$manifest.target.destination_template) -HomePath $HomePath
        if (-not (Test-Path -LiteralPath $destination -PathType Container) -or (Test-DevkitFlutterWindowsReparsePoint $destination)) { return $false }
        $marker = Join-Path $destination ([string]$manifest.target.marker_relative_path)
        if (-not (Test-Path -LiteralPath $marker -PathType Leaf) -or (Test-DevkitFlutterWindowsReparsePoint $marker)) { return $false }
        $owned = Get-Content -LiteralPath $marker -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($owned.environment -ne 'flutter' -or $owned.publisher -ne 'Flutter Authors / Google' -or $owned.platform -ne 'windows' -or $owned.architecture -ne 'amd64') { return $false }
        if (-not (Test-DevkitFlutterWindowsVersion -Version ([string]$owned.version) -Pattern ([string]$manifest.version_pattern))) { return $false }
        if ([string]$owned.source_url -notmatch '^https://storage\.googleapis\.com/flutter_infra_release/releases/') { return $false }
        if ([string]$owned.archive_sha256 -notmatch '^[0-9a-fA-F]{64}$') { return $false }
        $current = Get-DevkitFlutterWindowsCriticalHashes -SdkRoot $destination -Manifest $manifest
        foreach ($relative in @($manifest.target.critical_files)) {
            $property = $owned.critical_files.PSObject.Properties[[string]$relative]
            if (-not $property) { return $false }
            if (-not ([string]$property.Value).Equals([string]$current[[string]$relative], [StringComparison]::OrdinalIgnoreCase)) { return $false }
        }
        return $true
    } catch {
        return $false
    }
}

function Test-DevkitFlutterWindowsMarkerMatchesRelease {
    param(
        [Parameter(Mandatory = $true)][string]$ManifestPath,
        [Parameter(Mandatory = $true)][object]$Release,
        [string]$HomePath = (Get-DevkitFlutterWindowsHome)
    )
    if (-not (Test-DevkitFlutterWindowsManagedVerification -ManifestPath $ManifestPath -HomePath $HomePath)) { return $false }
    $manifest = Get-DevkitFlutterWindowsManifest -ManifestPath $ManifestPath
    $destination = Resolve-DevkitFlutterWindowsHomeTemplate -Template ([string]$manifest.target.destination_template) -HomePath $HomePath
    $marker = Join-Path $destination ([string]$manifest.target.marker_relative_path)
    $owned = Get-Content -LiteralPath $marker -Raw -Encoding UTF8 | ConvertFrom-Json
    return ([string]$owned.version -eq [string]$Release.Version -and
            [string]$owned.source_url -eq [string]$Release.SourceUrl -and
            ([string]$owned.archive_sha256).Equals([string]$Release.Sha256, [StringComparison]::OrdinalIgnoreCase))
}

function Get-DevkitFlutterWindowsPlan {
    param(
        [Parameter(Mandatory = $true)][string]$ManifestPath,
        [string]$HomePath = (Get-DevkitFlutterWindowsHome),
        [string]$Architecture = (Get-DevkitFlutterWindowsArchitecture)
    )
    $manifest = Get-DevkitFlutterWindowsManifest -ManifestPath $ManifestPath
    Assert-DevkitFlutterWindowsTarget -Manifest $manifest -Architecture $Architecture
    $paths = Assert-DevkitFlutterWindowsPathPrerequisites -Manifest $manifest -HomePath $HomePath
    $release = Get-DevkitFlutterWindowsRelease -ManifestPath $ManifestPath -Architecture $Architecture
    return [pscustomobject]@{
        Environment = 'flutter'
        Platform = 'windows'
        Architecture = $Architecture
        Support = 'experimental'
        Strategy = 'flutter-windows'
        Version = $release.Version
        ReleaseArchitecture = $release.ReleaseArchitecture
        ReleaseIndex = [string]$manifest.release_index_url
        SourceUrl = $release.SourceUrl
        ExpectedSha256 = $release.Sha256
        Destination = $paths.Destination
        PathDirectory = $paths.PathDirectory
        Privilege = 'none'
        PathMutation = 'none'
        MutatesHost = $false
    }
}

function Remove-DevkitFlutterWindowsStaging {
    param(
        [string]$StagingPath,
        [Parameter(Mandatory = $true)][string]$ExpectedParent
    )
    if ([string]::IsNullOrWhiteSpace($StagingPath) -or -not (Test-Path -LiteralPath $StagingPath)) { return }
    $parent = [IO.Path]::GetFullPath($ExpectedParent).TrimEnd('\')
    $staging = [IO.Path]::GetFullPath($StagingPath).TrimEnd('\')
    $prefix = $parent + '\'
    if (-not $staging.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Refusing Flutter staging cleanup outside the approved install parent.' }
    $leaf = Split-Path -Leaf $staging
    if ($leaf -notmatch '^\.devkit-wulf-flutter-[0-9a-f]{32}$') { throw "Refusing unexpected Flutter staging cleanup path: $staging" }
    if (Test-DevkitFlutterWindowsReparsePoint $staging) { throw "Refusing Flutter staging cleanup through reparse point: $staging" }
    [IO.Directory]::Delete($staging, $true)
}

function Install-DevkitFlutterWindowsArtifact {
    param(
        [Parameter(Mandatory = $true)][string]$ManifestPath,
        [string]$HomePath = (Get-DevkitFlutterWindowsHome),
        [string]$StateDirectory = (Get-DevkitFlutterWindowsStateDirectory),
        [string]$Architecture = (Get-DevkitFlutterWindowsArchitecture)
    )
    $manifest = Get-DevkitFlutterWindowsManifest -ManifestPath $ManifestPath
    Assert-DevkitFlutterWindowsTarget -Manifest $manifest -Architecture $Architecture
    $paths = Assert-DevkitFlutterWindowsPathPrerequisites -Manifest $manifest -HomePath $HomePath
    $stateFile = Assert-DevkitFlutterWindowsStateReady -StateDirectory $StateDirectory
    $null = $stateFile

    if (Test-Path -LiteralPath $paths.Destination) {
        if (Test-DevkitFlutterWindowsReparsePoint $paths.Destination) { throw "GATE-08 Flutter Windows destination is a reparse point: $($paths.Destination)" }
        if (-not (Test-Path -LiteralPath $paths.Marker -PathType Leaf)) { throw 'GATE-08 existing Flutter SDK is not owned by devkit-wulf; refusing adoption.' }
    }

    $release = Get-DevkitFlutterWindowsRelease -ManifestPath $ManifestPath -Architecture $Architecture
    if (Test-Path -LiteralPath $paths.Destination) {
        if (Test-DevkitFlutterWindowsMarkerMatchesRelease -ManifestPath $ManifestPath -Release $release -HomePath $HomePath) {
            Add-DevkitFlutterWindowsStateRecord -StateDirectory $StateDirectory -Action 'observed-exact-artifact' -Version $release.Version -SourceUrl $release.SourceUrl -ArchiveSha256 $release.Sha256 -Destination $paths.Destination -Created $false
            return
        }
        throw 'GATE-08 existing devkit Flutter SDK does not match the current resolved release; explicit upgrade/migration is required.'
    }

    $staging = Join-Path $paths.Parent ('.devkit-wulf-flutter-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $staging | Out-Null
    $archive = Join-Path $staging 'flutter.zip'
    $extract = Join-Path $staging 'extract'
    try {
        Invoke-DevkitFlutterWindowsDownload -Uri $release.SourceUrl -Destination $archive
        $actual = Get-DevkitFlutterWindowsSha256 -Path $archive
        if (-not $actual.Equals([string]$release.Sha256, [StringComparison]::OrdinalIgnoreCase)) { throw 'GATE-05 Flutter Windows archive SHA-256 mismatch.' }
        if (-not (Test-DevkitFlutterWindowsZipSafe -ArchivePath $archive -Manifest $manifest)) { throw 'GATE-05/08 rejected unsafe Flutter Windows ZIP contents.' }

        New-Item -ItemType Directory -Path $extract | Out-Null
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [IO.Compression.ZipFile]::ExtractToDirectory($archive, $extract)
        $sdk = Join-Path $extract ([string]$manifest.target.root_directory)
        if (-not (Test-Path -LiteralPath $sdk -PathType Container) -or (Test-DevkitFlutterWindowsReparsePoint $sdk)) { throw 'GATE-12 extracted Flutter SDK root is missing or unsafe.' }
        $criticalHashes = Get-DevkitFlutterWindowsCriticalHashes -SdkRoot $sdk -Manifest $manifest

        $critical = [ordered]@{}
        foreach ($relative in @($manifest.target.critical_files)) { $critical[[string]$relative] = [string]$criticalHashes[[string]$relative] }
        $markerData = [ordered]@{
            environment = 'flutter'
            publisher = 'Flutter Authors / Google'
            platform = 'windows'
            architecture = 'amd64'
            version = [string]$release.Version
            source_url = [string]$release.SourceUrl
            archive_sha256 = [string]$actual
            critical_files = $critical
        }
        $markerInStaging = Join-Path $sdk ([string]$manifest.target.marker_relative_path)
        $markerData | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $markerInStaging -Encoding UTF8

        Add-DevkitFlutterWindowsStateRecord -StateDirectory $StateDirectory -Action 'mutation-intent' -Version $release.Version -SourceUrl $release.SourceUrl -ArchiveSha256 $actual -Destination $paths.Destination -Created $false
        Move-Item -LiteralPath $sdk -Destination $paths.Destination
        if (-not (Test-DevkitFlutterWindowsManagedVerification -ManifestPath $ManifestPath -HomePath $HomePath)) { throw 'GATE-12 managed Flutter Windows verification failed after placement.' }
        Add-DevkitFlutterWindowsStateRecord -StateDirectory $StateDirectory -Action 'installed-verified-artifact' -Version $release.Version -SourceUrl $release.SourceUrl -ArchiveSha256 $actual -Destination $paths.Destination -Created $true
    } finally {
        Remove-DevkitFlutterWindowsStaging -StagingPath $staging -ExpectedParent $paths.Parent
    }
}
