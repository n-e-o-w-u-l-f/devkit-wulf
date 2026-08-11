Set-StrictMode -Version Latest

function Get-DevkitKubectlWindowsManifest {
    param([Parameter(Mandatory = $true)][string]$ManifestPath)
    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) { throw "kubectl native manifest not found: $ManifestPath" }
    return Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-DevkitKubectlWindowsArchitecture {
    $arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLowerInvariant()
    switch ($arch) { 'x64' { 'amd64'; break } default { $arch } }
}

function Assert-DevkitKubectlWindowsTarget {
    param([object]$Manifest, [string]$Architecture)
    if ($Manifest.support -ne 'experimental') { throw 'GATE-02 kubectl Windows contract must remain experimental.' }
    $target = $Manifest.targets.windows
    $mapping = $target.architectures.PSObject.Properties[$Architecture]
    if (-not $mapping) { throw "GATE-02 kubectl Windows does not support architecture '$Architecture'." }
    if ([string]$mapping.Value -ne $Architecture) { throw 'kubectl Windows architecture mapping is inconsistent.' }
    return $target
}

function Test-DevkitKubectlWindowsReparsePoint {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    return (((Get-Item -LiteralPath $Path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)
}

function Get-DevkitKubectlWindowsPaths {
    param([object]$Target)
    if (-not $env:LOCALAPPDATA -or -not [IO.Path]::IsPathRooted($env:LOCALAPPDATA)) { throw 'LOCALAPPDATA must be absolute.' }
    if ([string]$Target.root_template -ne '{localappdata}/devkit-wulf/kubectl') { throw 'Unsafe kubectl Windows root template.' }
    $base = [IO.Path]::GetFullPath($env:LOCALAPPDATA)
    $root = [IO.Path]::GetFullPath((Join-Path $base 'devkit-wulf\kubectl'))
    $prefix = $base.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (-not $root.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'kubectl root escaped LOCALAPPDATA.' }
    $pathDirectory = [IO.Path]::GetFullPath((Join-Path $root ([string]$Target.path_directory_relative)))
    return [pscustomobject]@{
        Root = $root
        PathDirectory = $pathDirectory
        Binary = Join-Path $pathDirectory ([string]$Target.filename)
        Marker = Join-Path $root ([string]$Target.marker_relative_path)
    }
}

function Invoke-DevkitKubectlWindowsDownload {
    param([string]$Uri, [string]$Destination)
    $parsed = [Uri]$Uri
    if ($parsed.Scheme -ne 'https' -or $parsed.Host -ne 'dl.k8s.io' -or -not $parsed.AbsolutePath.StartsWith('/release/', [StringComparison]::Ordinal)) {
        throw "GATE-04 blocked untrusted kubectl URL: $Uri"
    }
    Invoke-WebRequest -Uri $parsed -OutFile $Destination -UseBasicParsing
}

function Get-DevkitKubectlWindowsSha256 {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-DevkitKubectlStableVersion {
    param([object]$Manifest)
    if ([string]$Manifest.version.url -ne 'https://dl.k8s.io/release/stable.txt') { throw 'GATE-04 kubectl stable resolver is not pinned.' }
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('devkit-wulf-kubectl-version-' + [guid]::NewGuid().ToString('N') + '.txt')
    try {
        Invoke-DevkitKubectlWindowsDownload -Uri ([string]$Manifest.version.url) -Destination $tmp
        $version = (Get-Content -LiteralPath $tmp -Raw -Encoding UTF8).Trim()
    } finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    if (-not [regex]::IsMatch($version, [string]$Manifest.version.pattern)) { throw "GATE-03 rejected kubectl stable version: $version" }
    return $version
}

function Get-DevkitKubectlWindowsArtifact {
    param([string]$ManifestPath, [string]$Architecture = (Get-DevkitKubectlWindowsArchitecture))
    $manifest = Get-DevkitKubectlWindowsManifest -ManifestPath $ManifestPath
    $target = Assert-DevkitKubectlWindowsTarget -Manifest $manifest -Architecture $Architecture
    $version = Get-DevkitKubectlStableVersion -Manifest $manifest
    $source = ([string]$target.url_template).Replace('{version}', $version).Replace('{architecture}', $Architecture)
    $checksum = ([string]$target.checksum_url_template).Replace('{version}', $version).Replace('{architecture}', $Architecture)
    foreach ($url in @($source, $checksum)) {
        $uri = [Uri]$url
        if ($uri.Scheme -ne 'https' -or $uri.Host -ne 'dl.k8s.io' -or -not $uri.AbsolutePath.StartsWith("/release/$version/bin/windows/$Architecture/", [StringComparison]::Ordinal)) { throw "GATE-04 kubectl artifact URL escaped pinned release path: $url" }
    }
    return [pscustomobject]@{ Version = $version; Architecture = $Architecture; SourceUrl = $source; ChecksumUrl = $checksum }
}

function Get-DevkitKubectlWindowsExpectedSha256 {
    param([string]$ChecksumUrl)
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('devkit-wulf-kubectl-checksum-' + [guid]::NewGuid().ToString('N') + '.txt')
    try {
        Invoke-DevkitKubectlWindowsDownload -Uri $ChecksumUrl -Destination $tmp
        $text = (Get-Content -LiteralPath $tmp -Raw -Encoding UTF8).Trim()
    } finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    if ($text -notmatch '^([0-9a-fA-F]{64})(?:\s+\*?kubectl\.exe)?$') { throw 'GATE-05 kubectl checksum sidecar is malformed.' }
    return $Matches[1].ToLowerInvariant()
}

function Assert-DevkitKubectlWindowsPathReady {
    param([object]$Paths)
    foreach ($path in @($Paths.Root, $Paths.PathDirectory)) {
        if ((Test-Path -LiteralPath $path) -and (Test-DevkitKubectlWindowsReparsePoint $path)) { throw "GATE-08 kubectl path is a reparse point: $path" }
    }
    $wanted = [IO.Path]::GetFullPath($Paths.PathDirectory).TrimEnd('\')
    $present = $false
    foreach ($entry in ([string]$env:PATH -split ';')) {
        if ([string]::IsNullOrWhiteSpace($entry)) { continue }
        try { $candidate = [IO.Path]::GetFullPath($entry).TrimEnd('\') } catch { continue }
        if ($candidate.Equals($wanted, [StringComparison]::OrdinalIgnoreCase)) { $present = $true; break }
    }
    if (-not $present) { throw "GATE-13 PATH must already contain $($Paths.PathDirectory); devkit-wulf will not modify PATH implicitly." }
}

function Test-DevkitKubectlWindowsManagedVerification {
    param([string]$ManifestPath, [string]$Architecture = (Get-DevkitKubectlWindowsArchitecture))
    try {
        $manifest = Get-DevkitKubectlWindowsManifest -ManifestPath $ManifestPath
        $target = Assert-DevkitKubectlWindowsTarget -Manifest $manifest -Architecture $Architecture
        $paths = Get-DevkitKubectlWindowsPaths -Target $target
        if (-not (Test-Path -LiteralPath $paths.Binary -PathType Leaf) -or (Test-DevkitKubectlWindowsReparsePoint $paths.Binary)) { return $false }
        if (-not (Test-Path -LiteralPath $paths.Marker -PathType Leaf) -or (Test-DevkitKubectlWindowsReparsePoint $paths.Marker)) { return $false }
        $owned = Get-Content -LiteralPath $paths.Marker -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($owned.environment -ne 'kubectl' -or $owned.selector -ne 'kubectl@stable' -or $owned.platform -ne 'windows' -or $owned.architecture -ne $Architecture) { return $false }
        if ([string]$owned.version -notmatch '^v[0-9]+\.[0-9]+\.[0-9]+$' -or [string]$owned.source_url -notmatch '^https://dl\.k8s\.io/release/v[0-9]+\.[0-9]+\.[0-9]+/bin/windows/amd64/kubectl\.exe$' -or [string]$owned.sha256 -notmatch '^[0-9a-fA-F]{64}$') { return $false }
        if ((Get-DevkitKubectlWindowsSha256 -Path $paths.Binary) -ne ([string]$owned.sha256).ToLowerInvariant()) { return $false }
        $raw = (& $paths.Binary version --client=true --output=json 2>$null | Out-String).Trim()
        if ($LASTEXITCODE -ne 0) { return $false }
        $versionInfo = $raw | ConvertFrom-Json
        if ([string]$versionInfo.clientVersion.gitVersion -ne [string]$owned.version) { return $false }
        return $true
    } catch { return $false }
}

function Get-DevkitKubectlWindowsPlan {
    param([string]$ManifestPath, [string]$Architecture = (Get-DevkitKubectlWindowsArchitecture))
    $manifest = Get-DevkitKubectlWindowsManifest -ManifestPath $ManifestPath
    $target = Assert-DevkitKubectlWindowsTarget -Manifest $manifest -Architecture $Architecture
    $paths = Get-DevkitKubectlWindowsPaths -Target $target
    $artifact = Get-DevkitKubectlWindowsArtifact -ManifestPath $ManifestPath -Architecture $Architecture
    $sha = Get-DevkitKubectlWindowsExpectedSha256 -ChecksumUrl $artifact.ChecksumUrl
    return [pscustomobject]@{ Environment = 'kubectl'; Selector = 'kubectl@stable'; Platform = 'windows'; Architecture = $Architecture; Support = 'experimental'; Version = $artifact.Version; SourceUrl = $artifact.SourceUrl; ChecksumUrl = $artifact.ChecksumUrl; Sha256 = $sha; Destination = $paths.Binary; PathDirectory = $paths.PathDirectory; Privileged = $false; PathMutation = $false; MutatesHost = $false }
}

function Install-DevkitKubectlWindowsArtifact {
    param([string]$ManifestPath, [string]$Architecture = (Get-DevkitKubectlWindowsArchitecture))
    $manifest = Get-DevkitKubectlWindowsManifest -ManifestPath $ManifestPath
    $target = Assert-DevkitKubectlWindowsTarget -Manifest $manifest -Architecture $Architecture
    $paths = Get-DevkitKubectlWindowsPaths -Target $target

    if ((Test-Path -LiteralPath $paths.Binary) -or (Test-Path -LiteralPath $paths.Marker)) {
        if (Test-DevkitKubectlWindowsManagedVerification -ManifestPath $ManifestPath -Architecture $Architecture) { return [pscustomobject]@{ Result = 'already-satisfied'; Destination = $paths.Binary } }
        throw 'GATE-08 existing kubectl selector destination is not an exact devkit-managed installation.'
    }

    Assert-DevkitKubectlWindowsPathReady -Paths $paths
    $artifact = Get-DevkitKubectlWindowsArtifact -ManifestPath $ManifestPath -Architecture $Architecture
    $expected = Get-DevkitKubectlWindowsExpectedSha256 -ChecksumUrl $artifact.ChecksumUrl
    if (-not (Test-Path -LiteralPath $paths.Root)) { New-Item -ItemType Directory -Path $paths.Root -Force | Out-Null }
    if (-not (Test-Path -LiteralPath $paths.PathDirectory)) { New-Item -ItemType Directory -Path $paths.PathDirectory -Force | Out-Null }
    foreach ($path in @($paths.Root, $paths.PathDirectory)) { if (Test-DevkitKubectlWindowsReparsePoint $path) { throw "GATE-08 kubectl destination path is a reparse point: $path" } }

    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('devkit-wulf-kubectl-' + [guid]::NewGuid().ToString('N') + '.exe')
    try {
        Invoke-DevkitKubectlWindowsDownload -Uri $artifact.SourceUrl -Destination $tmp
        $actual = Get-DevkitKubectlWindowsSha256 -Path $tmp
        if ($actual -ne $expected) { throw "GATE-05 kubectl.exe SHA-256 mismatch: expected $expected, got $actual" }
        if (Test-DevkitKubectlWindowsReparsePoint $tmp) { throw 'GATE-05 kubectl staging file is a reparse point.' }
        Move-Item -LiteralPath $tmp -Destination $paths.Binary
        $marker = [ordered]@{ environment = 'kubectl'; selector = 'kubectl@stable'; platform = 'windows'; architecture = $Architecture; publisher = 'Kubernetes SIG CLI'; version = $artifact.Version; source_url = $artifact.SourceUrl; sha256 = $expected; privileged = $false; path_mutation = $false }
        ($marker | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath $paths.Marker -Encoding UTF8
        if (-not (Test-DevkitKubectlWindowsManagedVerification -ManifestPath $ManifestPath -Architecture $Architecture)) { throw 'GATE-12 kubectl Windows managed verification failed after installation.' }
        return [pscustomobject]@{ Result = 'installed'; Version = $artifact.Version; Destination = $paths.Binary }
    } catch {
        if ((Test-Path -LiteralPath $paths.Binary) -and -not (Test-Path -LiteralPath $paths.Marker -PathType Leaf)) { throw "kubectl installation failed after binary placement; automatic destructive rollback is intentionally refused. Original error: $($_.Exception.Message)" }
        throw
    } finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
}
