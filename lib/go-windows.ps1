Set-StrictMode -Version Latest

function Get-DevkitGoWindowsManifest {
    param([Parameter(Mandatory = $true)][string]$ManifestPath)
    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) { throw "Go Windows manifest not found: $ManifestPath" }
    return Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-DevkitGoWindowsArchitecture {
    $arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLowerInvariant()
    switch ($arch) {
        'x64' { return 'amd64' }
        'arm64' { return 'arm64' }
        default { return $arch }
    }
}

function Assert-DevkitGoWindowsTarget {
    param([Parameter(Mandatory = $true)][object]$Manifest, [Parameter(Mandatory = $true)][string]$Architecture)
    if ($Manifest.support -ne 'experimental') { throw 'GATE-02 Go Windows contract must remain experimental.' }
    $property = $Manifest.target.architectures.PSObject.Properties[$Architecture]
    if (-not $property) { throw "GATE-02 Go Windows adapter does not support architecture '$Architecture'." }
    if ([string]$property.Value -ne $Architecture) { throw 'Go Windows architecture mapping is inconsistent.' }
}

function Test-DevkitGoWindowsReparsePoint {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $item = Get-Item -LiteralPath $Path -Force
    return (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)
}

function Resolve-DevkitGoLocalAppDataTemplate {
    param([Parameter(Mandatory = $true)][string]$Template)
    if (-not $env:LOCALAPPDATA -or -not [IO.Path]::IsPathRooted($env:LOCALAPPDATA)) { throw 'LOCALAPPDATA must be an absolute path.' }
    if (-not $Template.StartsWith('{localappdata}/', [StringComparison]::Ordinal)) { throw "Unsafe Go Windows template: $Template" }
    $base = [IO.Path]::GetFullPath($env:LOCALAPPDATA)
    $relative = $Template.Substring(15).Replace('/', [IO.Path]::DirectorySeparatorChar)
    if (@($relative -split '[\\/]' | Where-Object { $_ -in @('', '.', '..') }).Count -gt 0) { throw "Unsafe Go Windows template traversal: $Template" }
    $resolved = [IO.Path]::GetFullPath((Join-Path $base $relative))
    $prefix = $base.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (-not $resolved.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw "Go Windows template escapes LOCALAPPDATA: $Template" }
    return $resolved
}

function Get-DevkitGoWindowsStateDirectory {
    if ($env:DEVKIT_WULF_STATE_DIR) { return [IO.Path]::GetFullPath($env:DEVKIT_WULF_STATE_DIR) }
    if (-not $env:LOCALAPPDATA) { throw 'LOCALAPPDATA is required when DEVKIT_WULF_STATE_DIR is not set.' }
    return [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'devkit-wulf\state'))
}

function Assert-DevkitGoWindowsStateReady {
    param([Parameter(Mandatory = $true)][string]$StateDirectory)
    $state = [IO.Path]::GetFullPath($StateDirectory)
    if (Test-DevkitGoWindowsReparsePoint $state) { throw "GATE-10 refuses Go Windows state-directory reparse point: $state" }
    if (-not (Test-Path -LiteralPath $state)) { New-Item -ItemType Directory -Path $state -Force | Out-Null }
    if (-not (Test-Path -LiteralPath $state -PathType Container)) { throw "Go Windows state path is not a directory: $state" }
    $file = Join-Path $state 'go-windows.jsonl'
    if (Test-DevkitGoWindowsReparsePoint $file) { throw "GATE-10 refuses Go Windows state-file reparse point: $file" }
    if ((Test-Path -LiteralPath $file) -and -not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Go Windows state path is not a regular file: $file" }
    return $file
}

function Add-DevkitGoWindowsStateRecord {
    param(
        [Parameter(Mandatory = $true)][string]$Action,
        [Parameter(Mandatory = $true)][string]$Architecture,
        [string]$Version = '', [string]$SourceUrl = '', [string]$ArchiveSha256 = '', [string]$Destination = ''
    )
    $stateFile = Assert-DevkitGoWindowsStateReady -StateDirectory (Get-DevkitGoWindowsStateDirectory)
    $record = [ordered]@{
        timestamp = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
        environment = 'go'; selector = 'go@stable'; platform = 'windows'; architecture = $Architecture
        publisher = 'The Go Authors / Google'; action = $Action; version = $Version
        source_url = $SourceUrl; archive_sha256 = $ArchiveSha256; destination = $Destination
        privileged = $false; path_mutation = $false
    }
    ($record | ConvertTo-Json -Compress) | Add-Content -LiteralPath $stateFile -Encoding UTF8
}

function Invoke-DevkitGoWindowsDownload {
    param([Parameter(Mandatory = $true)][string]$Uri, [Parameter(Mandatory = $true)][string]$Destination)
    $parsed = [Uri]$Uri
    if ($parsed.Scheme -ne 'https') { throw "GATE-04 blocked non-HTTPS Go URL: $Uri" }
    Invoke-WebRequest -Uri $parsed -OutFile $Destination -UseBasicParsing
}

function Get-DevkitGoWindowsSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-DevkitGoWindowsRelease {
    param([Parameter(Mandatory = $true)][string]$ManifestPath, [string]$Architecture = (Get-DevkitGoWindowsArchitecture))
    $manifest = Get-DevkitGoWindowsManifest -ManifestPath $ManifestPath
    Assert-DevkitGoWindowsTarget -Manifest $manifest -Architecture $Architecture
    if ([string]$manifest.release_index_url -ne 'https://go.dev/dl/?mode=json') { throw 'GATE-04 Go Windows release index is not the pinned official endpoint.' }
    if ([string]$manifest.download_base_url -ne 'https://go.dev/dl') { throw 'GATE-04 Go Windows download base is not the pinned official endpoint.' }

    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("devkit-wulf-go-windows-index-{0}.json" -f [guid]::NewGuid().ToString('N'))
    try {
        Invoke-DevkitGoWindowsDownload -Uri ([string]$manifest.release_index_url) -Destination $tmp
        $index = @(Get-Content -LiteralPath $tmp -Raw -Encoding UTF8 | ConvertFrom-Json)
    } finally {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
    $stable = @($index | Where-Object { $_.stable -eq $true })
    if ($stable.Count -lt 1) { throw 'GATE-03 Go release index contains no stable release.' }
    $release = $stable[0]
    $version = [string]$release.version
    if (-not [regex]::IsMatch($version, [string]$manifest.version_pattern)) { throw "GATE-03 rejected unsafe Go version: $version" }

    $files = @($release.files | Where-Object { [string]$_.os -eq 'windows' -and [string]$_.arch -eq $Architecture -and [string]$_.kind -eq 'archive' })
    if ($files.Count -ne 1) { throw "GATE-03 expected one Go Windows/$Architecture archive; got $($files.Count)." }
    $file = $files[0]
    $filename = [string]$file.filename
    $expectedFilename = "$version.windows-$Architecture.zip"
    if ($filename -ne $expectedFilename -or -not [regex]::IsMatch($filename, [string]$manifest.target.filename_pattern)) { throw "GATE-03 rejected Go Windows archive filename: $filename" }
    if ([string]$file.version -ne $version) { throw 'GATE-03 Go archive version does not match selected stable release.' }
    $sha = ([string]$file.sha256).ToLowerInvariant()
    if ($sha -notmatch '^[0-9a-f]{64}$') { throw 'GATE-05 Go release metadata contains malformed SHA-256.' }
    $source = "$($manifest.download_base_url)/$filename"
    $uri = [Uri]$source
    if ($uri.Scheme -ne 'https' -or $uri.Host -ne 'go.dev' -or -not $uri.AbsolutePath.StartsWith('/dl/', [StringComparison]::Ordinal)) { throw 'GATE-04 Go archive URL escaped the official source.' }

    return [pscustomobject]@{ Version = $version; Filename = $filename; SourceUrl = $source; Sha256 = $sha; Architecture = $Architecture }
}

function Assert-DevkitGoWindowsPathPrerequisites {
    param([Parameter(Mandatory = $true)][object]$Manifest)
    $destination = Resolve-DevkitGoLocalAppDataTemplate -Template ([string]$Manifest.target.destination_template)
    $pathDirectory = Resolve-DevkitGoLocalAppDataTemplate -Template ([string]$Manifest.target.path_directory_template)
    $parent = Split-Path -Parent $destination
    if ((Test-Path -LiteralPath $parent) -and (Test-DevkitGoWindowsReparsePoint $parent)) { throw "GATE-08 Go Windows install parent is a reparse point: $parent" }
    if ((Test-Path -LiteralPath $parent) -and -not (Test-Path -LiteralPath $parent -PathType Container)) { throw "GATE-08 Go Windows install parent is not a directory: $parent" }
    $normalized = [IO.Path]::GetFullPath($pathDirectory).TrimEnd('\')
    $present = $false
    foreach ($entry in ([string]$env:PATH -split ';')) {
        if ([string]::IsNullOrWhiteSpace($entry)) { continue }
        try { $candidate = [IO.Path]::GetFullPath($entry).TrimEnd('\') } catch { continue }
        if ($candidate.Equals($normalized, [StringComparison]::OrdinalIgnoreCase)) { $present = $true; break }
    }
    if (-not $present) { throw "GATE-13 PATH must already contain $pathDirectory; devkit-wulf will not modify PATH implicitly." }
    return [pscustomobject]@{ Destination = $destination; PathDirectory = $pathDirectory; Parent = $parent; Marker = Join-Path $destination ([string]$Manifest.target.marker_relative_path) }
}

function Test-DevkitGoWindowsZipSafe {
    param([Parameter(Mandatory = $true)][string]$ArchivePath, [Parameter(Mandatory = $true)][object]$Manifest)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($ArchivePath)
    try {
        $root = [string]$Manifest.target.root_directory
        $required = @{}
        foreach ($critical in @($Manifest.target.critical_files)) { $required[("$root/$critical")] = $false }
        foreach ($entry in $zip.Entries) {
            $name = [string]$entry.FullName
            if ([string]::IsNullOrWhiteSpace($name) -or $name.StartsWith('/') -or $name.StartsWith('\') -or $name.Contains('\') -or $name.Contains(':')) { return $false }
            $trimmed = $name.TrimEnd('/')
            if ([string]::IsNullOrWhiteSpace($trimmed)) { return $false }
            $parts = @($trimmed -split '/')
            if ($parts[0] -ne $root -or @($parts | Where-Object { $_ -in @('', '.', '..') }).Count -gt 0) { return $false }
            $unixType = (($entry.ExternalAttributes -shr 16) -band 0xF000)
            if ($unixType -eq 0xA000 -or ($entry.ExternalAttributes -band 0x400) -ne 0) { return $false }
            if ($required.ContainsKey($name)) {
                if ([string]::IsNullOrEmpty($entry.Name)) { return $false }
                $required[$name] = $true
            }
        }
        foreach ($value in $required.Values) { if (-not $value) { return $false } }
        return $true
    } finally { $zip.Dispose() }
}

function Get-DevkitGoWindowsCriticalHashes {
    param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)][object]$Manifest)
    $hashes = [ordered]@{}
    foreach ($relative in @($Manifest.target.critical_files)) {
        $path = Join-Path $Root (([string]$relative).Replace('/', [IO.Path]::DirectorySeparatorChar))
        if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Test-DevkitGoWindowsReparsePoint $path)) { throw "GATE-12 Go critical file is missing or unsafe: $relative" }
        $hashes[[string]$relative] = Get-DevkitGoWindowsSha256 -Path $path
    }
    return $hashes
}

function Test-DevkitGoWindowsManagedVerification {
    param([Parameter(Mandatory = $true)][string]$ManifestPath, [string]$Architecture = (Get-DevkitGoWindowsArchitecture))
    try {
        $manifest = Get-DevkitGoWindowsManifest -ManifestPath $ManifestPath
        Assert-DevkitGoWindowsTarget -Manifest $manifest -Architecture $Architecture
        $destination = Resolve-DevkitGoLocalAppDataTemplate -Template ([string]$manifest.target.destination_template)
        if (-not (Test-Path -LiteralPath $destination -PathType Container) -or (Test-DevkitGoWindowsReparsePoint $destination)) { return $false }
        $bin = Join-Path $destination 'bin'
        if (-not (Test-Path -LiteralPath $bin -PathType Container) -or (Test-DevkitGoWindowsReparsePoint $bin)) { return $false }
        $marker = Join-Path $destination ([string]$manifest.target.marker_relative_path)
        if (-not (Test-Path -LiteralPath $marker -PathType Leaf) -or (Test-DevkitGoWindowsReparsePoint $marker)) { return $false }
        $owned = Get-Content -LiteralPath $marker -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($owned.environment -ne 'go' -or $owned.selector -ne 'go@stable' -or $owned.platform -ne 'windows' -or $owned.architecture -ne $Architecture) { return $false }
        if (-not [regex]::IsMatch([string]$owned.version, [string]$manifest.version_pattern)) { return $false }
        if ([string]$owned.source_url -notmatch '^https://go\.dev/dl/go[0-9].*\.windows-(amd64|arm64)\.zip$') { return $false }
        if ([string]$owned.archive_sha256 -notmatch '^[0-9a-fA-F]{64}$') { return $false }
        $current = Get-DevkitGoWindowsCriticalHashes -Root $destination -Manifest $manifest
        foreach ($relative in @($manifest.target.critical_files)) {
            $expectedProperty = $owned.critical_files.PSObject.Properties[[string]$relative]
            if (-not $expectedProperty -or [string]$expectedProperty.Value -notmatch '^[0-9a-fA-F]{64}$') { return $false }
            if ($current[[string]$relative] -ne ([string]$expectedProperty.Value).ToLowerInvariant()) { return $false }
        }
        $go = Join-Path $destination 'bin\go.exe'
        $versionOutput = (& $go version 2>$null | Out-String).Trim()
        if ($LASTEXITCODE -ne 0 -or -not $versionOutput.Contains([string]$owned.version) -or -not $versionOutput.Contains("windows/$Architecture")) { return $false }
        return $true
    } catch { return $false }
}

function Remove-DevkitGoWindowsStaging {
    param([Parameter(Mandatory = $true)][string]$StagePath, [Parameter(Mandatory = $true)][string]$ParentPath)
    $stage = [IO.Path]::GetFullPath($StagePath)
    $parent = [IO.Path]::GetFullPath($ParentPath).TrimEnd('\')
    $prefix = $parent + [IO.Path]::DirectorySeparatorChar
    if (-not $stage.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw "Refusing unsafe Go staging cleanup path: $stage" }
    $leaf = Split-Path -Leaf $stage
    if ($leaf -notmatch '^\.devkit-wulf-go-[0-9a-f]{32}$') { throw "Refusing unrecognized Go staging path: $stage" }
    if ((Test-Path -LiteralPath $stage) -and (Test-DevkitGoWindowsReparsePoint $stage)) { throw "Refusing Go staging reparse point: $stage" }
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
}

function Get-DevkitGoWindowsPlan {
    param([Parameter(Mandatory = $true)][string]$ManifestPath, [string]$Architecture = (Get-DevkitGoWindowsArchitecture))
    $manifest = Get-DevkitGoWindowsManifest -ManifestPath $ManifestPath
    Assert-DevkitGoWindowsTarget -Manifest $manifest -Architecture $Architecture
    $destination = Resolve-DevkitGoLocalAppDataTemplate -Template ([string]$manifest.target.destination_template)
    $pathDirectory = Resolve-DevkitGoLocalAppDataTemplate -Template ([string]$manifest.target.path_directory_template)
    $release = Get-DevkitGoWindowsRelease -ManifestPath $ManifestPath -Architecture $Architecture
    return [pscustomobject]@{
        Environment = 'go'; Selector = 'go@stable'; Platform = 'windows'; Architecture = $Architecture
        Support = 'experimental'; Strategy = 'verified-windows-zip'; Version = $release.Version
        SourceUrl = $release.SourceUrl; Sha256 = $release.Sha256; Destination = $destination
        PathDirectory = $pathDirectory; Privileged = $false; PathMutation = $false; MutatesHost = $false
    }
}

function Install-DevkitGoWindowsArtifact {
    param([Parameter(Mandatory = $true)][string]$ManifestPath, [string]$Architecture = (Get-DevkitGoWindowsArchitecture))
    $manifest = Get-DevkitGoWindowsManifest -ManifestPath $ManifestPath
    Assert-DevkitGoWindowsTarget -Manifest $manifest -Architecture $Architecture
    $destination = Resolve-DevkitGoLocalAppDataTemplate -Template ([string]$manifest.target.destination_template)

    if ((Test-Path -LiteralPath $destination) -or (Test-DevkitGoWindowsReparsePoint $destination)) {
        if (Test-DevkitGoWindowsManagedVerification -ManifestPath $ManifestPath -Architecture $Architecture) {
            Add-DevkitGoWindowsStateRecord -Action 'observe-existing' -Architecture $Architecture -Destination $destination
            return [pscustomobject]@{ Result = 'already-satisfied'; Destination = $destination }
        }
        throw "GATE-08 existing Go destination is not an exact devkit-managed installation: $destination"
    }

    $paths = Assert-DevkitGoWindowsPathPrerequisites -Manifest $manifest
    $release = Get-DevkitGoWindowsRelease -ManifestPath $ManifestPath -Architecture $Architecture
    if (-not (Test-Path -LiteralPath $paths.Parent)) { New-Item -ItemType Directory -Path $paths.Parent -Force | Out-Null }
    if (Test-DevkitGoWindowsReparsePoint $paths.Parent) { throw "GATE-08 Go Windows install parent became a reparse point: $($paths.Parent)" }

    $stage = Join-Path $paths.Parent ('.devkit-wulf-go-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $stage | Out-Null
    $archive = Join-Path $stage 'go.zip'
    $extract = Join-Path $stage 'extract'
    New-Item -ItemType Directory -Path $extract | Out-Null
    try {
        Invoke-DevkitGoWindowsDownload -Uri $release.SourceUrl -Destination $archive
        $actual = Get-DevkitGoWindowsSha256 -Path $archive
        if ($actual -ne $release.Sha256) { throw "GATE-05 Go archive SHA-256 mismatch: expected $($release.Sha256), got $actual" }
        if (-not (Test-DevkitGoWindowsZipSafe -ArchivePath $archive -Manifest $manifest)) { throw 'GATE-05 Go Windows ZIP failed archive-safety validation.' }

        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [IO.Compression.ZipFile]::ExtractToDirectory($archive, $extract)
        $root = Join-Path $extract ([string]$manifest.target.root_directory)
        if (-not (Test-Path -LiteralPath $root -PathType Container) -or (Test-DevkitGoWindowsReparsePoint $root)) { throw 'GATE-12 extracted Go root is missing or unsafe.' }
        foreach ($item in @(Get-ChildItem -LiteralPath $root -Recurse -Force)) {
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "GATE-05 extracted Go tree contains a reparse point: $($item.FullName)" }
        }
        Get-DevkitGoWindowsCriticalHashes -Root $root -Manifest $manifest | Out-Null
        Move-Item -LiteralPath $root -Destination $destination

        $hashes = Get-DevkitGoWindowsCriticalHashes -Root $destination -Manifest $manifest
        $marker = [ordered]@{
            environment = 'go'; selector = 'go@stable'; platform = 'windows'; architecture = $Architecture
            publisher = 'The Go Authors / Google'; version = $release.Version; source_url = $release.SourceUrl
            archive_sha256 = $release.Sha256; critical_files = $hashes; path_mutation = $false; privileged = $false
        }
        ($marker | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath $paths.Marker -Encoding UTF8
        if (-not (Test-DevkitGoWindowsManagedVerification -ManifestPath $ManifestPath -Architecture $Architecture)) { throw 'GATE-12 Go Windows managed verification failed after installation.' }
        Add-DevkitGoWindowsStateRecord -Action 'install' -Architecture $Architecture -Version $release.Version -SourceUrl $release.SourceUrl -ArchiveSha256 $release.Sha256 -Destination $destination
        return [pscustomobject]@{ Result = 'installed'; Version = $release.Version; Destination = $destination }
    } catch {
        if ((Test-Path -LiteralPath $destination) -and -not (Test-Path -LiteralPath $paths.Marker -PathType Leaf)) {
            throw "Go installation failed after destination placement; automatic destructive rollback is intentionally refused. Original error: $($_.Exception.Message)"
        }
        throw
    } finally {
        Remove-DevkitGoWindowsStaging -StagePath $stage -ParentPath $paths.Parent
    }
}
