Set-StrictMode -Version Latest

function Get-DevkitRustupWindowsManifest {
    param([Parameter(Mandatory = $true)][string]$ManifestPath)
    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) { throw "Rustup Windows manifest not found: $ManifestPath" }
    return Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-DevkitRustupWindowsArchitecture {
    $arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLowerInvariant()
    switch ($arch) {
        'x64' { return 'amd64' }
        'arm64' { return 'arm64' }
        default { return $arch }
    }
}

function Assert-DevkitRustupWindowsTarget {
    param([Parameter(Mandatory = $true)][object]$Manifest, [Parameter(Mandatory = $true)][string]$Architecture)
    if ($Manifest.support -ne 'experimental') { throw 'GATE-02 Rust Windows contract must remain experimental.' }
    $property = $Manifest.target.architectures.PSObject.Properties[$Architecture]
    if (-not $property) { throw "GATE-02 rust@stable Windows does not support architecture '$Architecture'." }
    $triple = [string]$property.Value
    if ($triple -notmatch '^(x86_64|aarch64)-pc-windows-msvc$') { throw "GATE-02 rejected Rust Windows target triple: $triple" }
    return $triple
}

function Test-DevkitRustupWindowsReparsePoint {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    return (((Get-Item -LiteralPath $Path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)
}

function Resolve-DevkitRustupLocalAppDataRoot {
    param([Parameter(Mandatory = $true)][object]$Manifest)
    if (-not $env:LOCALAPPDATA -or -not [IO.Path]::IsPathRooted($env:LOCALAPPDATA)) { throw 'LOCALAPPDATA must be an absolute path.' }
    if ([string]$Manifest.target.root_template -ne '{localappdata}/devkit-wulf') { throw 'Unsafe Rust Windows root template.' }
    $base = [IO.Path]::GetFullPath($env:LOCALAPPDATA)
    $root = [IO.Path]::GetFullPath((Join-Path $base 'devkit-wulf'))
    $prefix = $base.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (-not $root.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Rust Windows root escaped LOCALAPPDATA.' }
    return $root
}

function Get-DevkitRustupWindowsPaths {
    param([Parameter(Mandatory = $true)][object]$Manifest)
    $root = Resolve-DevkitRustupLocalAppDataRoot -Manifest $Manifest
    foreach ($relative in @($Manifest.target.cargo_home_relative, $Manifest.target.rustup_home_relative, $Manifest.target.path_directory_relative, $Manifest.target.marker_relative_path)) {
        if ([string]$relative -match '(^[\\/])|(^|[\\/])\.\.([\\/]|$)|:') { throw "Unsafe Rust Windows relative path in manifest: $relative" }
    }
    return [pscustomobject]@{
        Root = $root
        CargoHome = [IO.Path]::GetFullPath((Join-Path $root (([string]$Manifest.target.cargo_home_relative).Replace('/', '\'))))
        RustupHome = [IO.Path]::GetFullPath((Join-Path $root (([string]$Manifest.target.rustup_home_relative).Replace('/', '\'))))
        PathDirectory = [IO.Path]::GetFullPath((Join-Path $root (([string]$Manifest.target.path_directory_relative).Replace('/', '\'))))
        Marker = [IO.Path]::GetFullPath((Join-Path $root ([string]$Manifest.target.marker_relative_path))
    }
}

function Get-DevkitRustupWindowsStateDirectory {
    if ($env:DEVKIT_WULF_STATE_DIR) { return [IO.Path]::GetFullPath($env:DEVKIT_WULF_STATE_DIR) }
    if (-not $env:LOCALAPPDATA) { throw 'LOCALAPPDATA is required when DEVKIT_WULF_STATE_DIR is not set.' }
    return [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'devkit-wulf\state'))
}

function Add-DevkitRustupWindowsStateRecord {
    param([Parameter(Mandatory = $true)][string]$Action, [Parameter(Mandatory = $true)][string]$Architecture, [string]$TargetTriple = '', [string]$SourceUrl = '', [string]$Sha256 = '')
    $state = Get-DevkitRustupWindowsStateDirectory
    if (Test-DevkitRustupWindowsReparsePoint $state) { throw "GATE-10 refuses Rust state-directory reparse point: $state" }
    if (-not (Test-Path -LiteralPath $state)) { New-Item -ItemType Directory -Path $state -Force | Out-Null }
    if (-not (Test-Path -LiteralPath $state -PathType Container)) { throw "Rust state path is not a directory: $state" }
    $file = Join-Path $state 'rustup-windows.jsonl'
    if (Test-DevkitRustupWindowsReparsePoint $file) { throw "GATE-10 refuses Rust state-file reparse point: $file" }
    if ((Test-Path -LiteralPath $file) -and -not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Rust state path is not a regular file: $file" }
    $record = [ordered]@{ timestamp = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ'); environment = 'rust'; selector = 'rust@stable'; platform = 'windows'; architecture = $Architecture; target_triple = $TargetTriple; publisher = 'The Rust Project'; action = $Action; source_url = $SourceUrl; installer_sha256 = $Sha256; privileged = $false; path_mutation = $false }
    ($record | ConvertTo-Json -Compress) | Add-Content -LiteralPath $file -Encoding UTF8
}

function Invoke-DevkitRustupWindowsDownload {
    param([Parameter(Mandatory = $true)][string]$Uri, [Parameter(Mandatory = $true)][string]$Destination)
    $parsed = [Uri]$Uri
    if ($parsed.Scheme -ne 'https' -or $parsed.Host -ne 'static.rust-lang.org' -or -not $parsed.AbsolutePath.StartsWith('/rustup/dist/', [StringComparison]::Ordinal)) { throw "GATE-04 blocked untrusted Rust URL: $Uri" }
    Invoke-WebRequest -Uri $parsed -OutFile $Destination -UseBasicParsing
}

function Get-DevkitRustupWindowsSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-DevkitRustupWindowsArtifact {
    param([Parameter(Mandatory = $true)][string]$ManifestPath, [string]$Architecture = (Get-DevkitRustupWindowsArchitecture))
    $manifest = Get-DevkitRustupWindowsManifest -ManifestPath $ManifestPath
    $triple = Assert-DevkitRustupWindowsTarget -Manifest $manifest -Architecture $Architecture
    if ([string]$manifest.distribution_base_url -ne 'https://static.rust-lang.org/rustup/dist') { throw 'GATE-04 Rust distribution base is not pinned.' }
    if ([string]$manifest.target.filename -ne 'rustup-init.exe' -or [string]$manifest.target.checksum_filename -ne 'rustup-init.exe.sha256') { throw 'Rust Windows artifact filenames changed unexpectedly.' }
    $source = "$($manifest.distribution_base_url)/$triple/$($manifest.target.filename)"
    $checksumUrl = "$($manifest.distribution_base_url)/$triple/$($manifest.target.checksum_filename)"
    return [pscustomobject]@{ Architecture = $Architecture; TargetTriple = $triple; SourceUrl = $source; ChecksumUrl = $checksumUrl }
}

function Get-DevkitRustupWindowsExpectedSha256 {
    param([Parameter(Mandatory = $true)][string]$ChecksumUrl)
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("devkit-wulf-rustup-checksum-{0}.txt" -f [guid]::NewGuid().ToString('N'))
    try {
        Invoke-DevkitRustupWindowsDownload -Uri $ChecksumUrl -Destination $tmp
        $text = (Get-Content -LiteralPath $tmp -Raw -Encoding UTF8).Trim()
    } finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    if ($text -notmatch '^([0-9a-fA-F]{64})(?:\s+\*?rustup-init\.exe)?$') { throw 'GATE-05 Rustup checksum sidecar is malformed.' }
    return $Matches[1].ToLowerInvariant()
}

function Assert-DevkitRustupWindowsPathPrerequisites {
    param([Parameter(Mandatory = $true)][object]$Paths)
    if ((Test-Path -LiteralPath $Paths.Root) -and (Test-DevkitRustupWindowsReparsePoint $Paths.Root)) { throw "GATE-08 Rust selector root is a reparse point: $($Paths.Root)" }
    $normalized = [IO.Path]::GetFullPath($Paths.PathDirectory).TrimEnd('\')
    $present = $false
    foreach ($entry in ([string]$env:PATH -split ';')) {
        if ([string]::IsNullOrWhiteSpace($entry)) { continue }
        try { $candidate = [IO.Path]::GetFullPath($entry).TrimEnd('\') } catch { continue }
        if ($candidate.Equals($normalized, [StringComparison]::OrdinalIgnoreCase)) { $present = $true; break }
    }
    if (-not $present) { throw "GATE-13 PATH must already contain $($Paths.PathDirectory); devkit-wulf will not modify PATH implicitly." }
}

function Get-DevkitRustupWindowsCriticalHashes {
    param([Parameter(Mandatory = $true)][object]$Manifest, [Parameter(Mandatory = $true)][object]$Paths)
    $hashes = [ordered]@{}
    foreach ($relative in @($Manifest.target.critical_files)) {
        $path = [IO.Path]::GetFullPath((Join-Path $Paths.Root (([string]$relative).Replace('/', '\'))))
        if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Test-DevkitRustupWindowsReparsePoint $path)) { throw "GATE-12 managed Rust critical file is missing or unsafe: $relative" }
        $hashes[[string]$relative] = Get-DevkitRustupWindowsSha256 -Path $path
    }
    return $hashes
}

function Invoke-DevkitRustupWindowsManagedCommand {
    param([Parameter(Mandatory = $true)][object]$Paths, [Parameter(Mandatory = $true)][string]$Executable, [Parameter(Mandatory = $true)][string[]]$Arguments)
    $hadCargo = Test-Path Env:CARGO_HOME; $oldCargo = $env:CARGO_HOME
    $hadRustup = Test-Path Env:RUSTUP_HOME; $oldRustup = $env:RUSTUP_HOME
    try {
        $env:CARGO_HOME = $Paths.CargoHome; $env:RUSTUP_HOME = $Paths.RustupHome
        $output = (& $Executable @Arguments 2>$null | Out-String).Trim()
        if ($LASTEXITCODE -ne 0) { throw "Managed Rust command failed: $Executable $($Arguments -join ' ')" }
        return $output
    } finally {
        if ($hadCargo) { $env:CARGO_HOME = $oldCargo } else { Remove-Item Env:CARGO_HOME -ErrorAction SilentlyContinue }
        if ($hadRustup) { $env:RUSTUP_HOME = $oldRustup } else { Remove-Item Env:RUSTUP_HOME -ErrorAction SilentlyContinue }
    }
}

function Test-DevkitRustupWindowsManagedVerification {
    param([Parameter(Mandatory = $true)][string]$ManifestPath, [string]$Architecture = (Get-DevkitRustupWindowsArchitecture))
    try {
        $manifest = Get-DevkitRustupWindowsManifest -ManifestPath $ManifestPath
        $triple = Assert-DevkitRustupWindowsTarget -Manifest $manifest -Architecture $Architecture
        $paths = Get-DevkitRustupWindowsPaths -Manifest $manifest
        foreach ($directory in @($paths.Root, $paths.CargoHome, $paths.RustupHome, $paths.PathDirectory)) {
            if (-not (Test-Path -LiteralPath $directory -PathType Container) -or (Test-DevkitRustupWindowsReparsePoint $directory)) { return $false }
        }
        if (-not (Test-Path -LiteralPath $paths.Marker -PathType Leaf) -or (Test-DevkitRustupWindowsReparsePoint $paths.Marker)) { return $false }
        $owned = Get-Content -LiteralPath $paths.Marker -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($owned.environment -ne 'rust' -or $owned.selector -ne 'rust@stable' -or $owned.platform -ne 'windows' -or $owned.architecture -ne $Architecture -or $owned.target_triple -ne $triple) { return $false }
        if ([string]$owned.source_url -ne "$($manifest.distribution_base_url)/$triple/rustup-init.exe" -or [string]$owned.installer_sha256 -notmatch '^[0-9a-fA-F]{64}$') { return $false }
        $current = Get-DevkitRustupWindowsCriticalHashes -Manifest $manifest -Paths $paths
        foreach ($relative in @($manifest.target.critical_files)) {
            $expected = $owned.critical_files.PSObject.Properties[[string]$relative]
            if (-not $expected -or [string]$expected.Value -notmatch '^[0-9a-fA-F]{64}$' -or $current[[string]$relative] -ne ([string]$expected.Value).ToLowerInvariant()) { return $false }
        }
        $rustup = Join-Path $paths.PathDirectory 'rustup.exe'; $rustc = Join-Path $paths.PathDirectory 'rustc.exe'; $cargo = Join-Path $paths.PathDirectory 'cargo.exe'
        $rustupVersion = Invoke-DevkitRustupWindowsManagedCommand -Paths $paths -Executable $rustup -Arguments @('--version')
        $rustcVersion = Invoke-DevkitRustupWindowsManagedCommand -Paths $paths -Executable $rustc -Arguments @('--version')
        $cargoVersion = Invoke-DevkitRustupWindowsManagedCommand -Paths $paths -Executable $cargo -Arguments @('--version')
        $active = Invoke-DevkitRustupWindowsManagedCommand -Paths $paths -Executable $rustup -Arguments @('show', 'active-toolchain')
        if ($rustupVersion -notmatch '^rustup ' -or $rustcVersion -notmatch '^rustc ' -or $cargoVersion -notmatch '^cargo ' -or $active -notmatch '^stable') { return $false }
        return $true
    } catch { return $false }
}

function Invoke-DevkitRustupWindowsInstaller {
    param([Parameter(Mandatory = $true)][string]$InstallerPath, [Parameter(Mandatory = $true)][object]$Manifest, [Parameter(Mandatory = $true)][object]$Paths)
    $hadCargo = Test-Path Env:CARGO_HOME; $oldCargo = $env:CARGO_HOME
    $hadRustup = Test-Path Env:RUSTUP_HOME; $oldRustup = $env:RUSTUP_HOME
    try {
        $env:CARGO_HOME = $Paths.CargoHome; $env:RUSTUP_HOME = $Paths.RustupHome
        & $InstallerPath @($Manifest.install.arguments)
        if ($LASTEXITCODE -ne 0) { throw "Verified rustup-init.exe failed with exit code $LASTEXITCODE." }
    } finally {
        if ($hadCargo) { $env:CARGO_HOME = $oldCargo } else { Remove-Item Env:CARGO_HOME -ErrorAction SilentlyContinue }
        if ($hadRustup) { $env:RUSTUP_HOME = $oldRustup } else { Remove-Item Env:RUSTUP_HOME -ErrorAction SilentlyContinue }
    }
}

function Get-DevkitRustupWindowsPlan {
    param([Parameter(Mandatory = $true)][string]$ManifestPath, [string]$Architecture = (Get-DevkitRustupWindowsArchitecture))
    $manifest = Get-DevkitRustupWindowsManifest -ManifestPath $ManifestPath
    $artifact = Get-DevkitRustupWindowsArtifact -ManifestPath $ManifestPath -Architecture $Architecture
    $paths = Get-DevkitRustupWindowsPaths -Manifest $manifest
    $sha = Get-DevkitRustupWindowsExpectedSha256 -ChecksumUrl $artifact.ChecksumUrl
    return [pscustomobject]@{ Environment = 'rust'; Selector = 'rust@stable'; Platform = 'windows'; Architecture = $Architecture; TargetTriple = $artifact.TargetTriple; Support = 'experimental'; Strategy = 'verified-rustup-init-exe'; SourceUrl = $artifact.SourceUrl; ChecksumUrl = $artifact.ChecksumUrl; Sha256 = $sha; CargoHome = $paths.CargoHome; RustupHome = $paths.RustupHome; PathDirectory = $paths.PathDirectory; Arguments = @($manifest.install.arguments); Privileged = $false; PathMutation = $false; MutatesHost = $false }
}

function Install-DevkitRustupWindowsArtifact {
    param([Parameter(Mandatory = $true)][string]$ManifestPath, [string]$Architecture = (Get-DevkitRustupWindowsArchitecture))
    $manifest = Get-DevkitRustupWindowsManifest -ManifestPath $ManifestPath
    $artifact = Get-DevkitRustupWindowsArtifact -ManifestPath $ManifestPath -Architecture $Architecture
    $paths = Get-DevkitRustupWindowsPaths -Manifest $manifest

    $cargoExists = (Test-Path -LiteralPath $paths.CargoHome) -or (Test-DevkitRustupWindowsReparsePoint $paths.CargoHome)
    $rustupExists = (Test-Path -LiteralPath $paths.RustupHome) -or (Test-DevkitRustupWindowsReparsePoint $paths.RustupHome)
    if ($cargoExists -or $rustupExists) {
        if ($cargoExists -and $rustupExists -and (Test-DevkitRustupWindowsManagedVerification -ManifestPath $ManifestPath -Architecture $Architecture)) {
            Add-DevkitRustupWindowsStateRecord -Action 'observe-existing' -Architecture $Architecture -TargetTriple $artifact.TargetTriple
            return [pscustomobject]@{ Result = 'already-satisfied'; CargoHome = $paths.CargoHome; RustupHome = $paths.RustupHome }
        }
        throw 'GATE-08 existing CARGO_HOME/RUSTUP_HOME is not an exact devkit-managed rust@stable installation.'
    }

    Assert-DevkitRustupWindowsPathPrerequisites -Paths $paths
    $expected = Get-DevkitRustupWindowsExpectedSha256 -ChecksumUrl $artifact.ChecksumUrl
    $installer = Join-Path ([IO.Path]::GetTempPath()) ("devkit-wulf-rustup-init-{0}.exe" -f [guid]::NewGuid().ToString('N'))
    try {
        Invoke-DevkitRustupWindowsDownload -Uri $artifact.SourceUrl -Destination $installer
        $actual = Get-DevkitRustupWindowsSha256 -Path $installer
        if ($actual -ne $expected) { throw "GATE-05 rustup-init.exe SHA-256 mismatch: expected $expected, got $actual" }
        if (Test-DevkitRustupWindowsReparsePoint $installer) { throw 'GATE-05 rustup-init staging file is a reparse point.' }
        if ((Test-Path -LiteralPath $paths.Root) -and (Test-DevkitRustupWindowsReparsePoint $paths.Root)) { throw "GATE-08 Rust selector root is a reparse point: $($paths.Root)" }
        if (-not (Test-Path -LiteralPath $paths.Root)) { New-Item -ItemType Directory -Path $paths.Root -Force | Out-Null }

        Invoke-DevkitRustupWindowsInstaller -InstallerPath $installer -Manifest $manifest -Paths $paths
        $hashes = Get-DevkitRustupWindowsCriticalHashes -Manifest $manifest -Paths $paths
        $marker = [ordered]@{ environment = 'rust'; selector = 'rust@stable'; platform = 'windows'; architecture = $Architecture; target_triple = $artifact.TargetTriple; publisher = 'The Rust Project'; source_url = $artifact.SourceUrl; installer_sha256 = $expected; critical_files = $hashes; privileged = $false; path_mutation = $false }
        ($marker | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath $paths.Marker -Encoding UTF8
        if (-not (Test-DevkitRustupWindowsManagedVerification -ManifestPath $ManifestPath -Architecture $Architecture)) { throw 'GATE-12 Rust Windows managed verification failed after installation.' }
        Add-DevkitRustupWindowsStateRecord -Action 'install' -Architecture $Architecture -TargetTriple $artifact.TargetTriple -SourceUrl $artifact.SourceUrl -Sha256 $expected
        return [pscustomobject]@{ Result = 'installed'; CargoHome = $paths.CargoHome; RustupHome = $paths.RustupHome; TargetTriple = $artifact.TargetTriple }
    } catch {
        if ((Test-Path -LiteralPath $paths.CargoHome) -or (Test-Path -LiteralPath $paths.RustupHome)) -and -not (Test-Path -LiteralPath $paths.Marker -PathType Leaf)) {
            throw "Rust installation failed after managed-home mutation; automatic destructive rollback is intentionally refused. Original error: $($_.Exception.Message)"
        }
        throw
    } finally { Remove-Item -LiteralPath $installer -Force -ErrorAction SilentlyContinue }
}
