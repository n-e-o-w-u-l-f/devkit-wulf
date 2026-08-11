Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $PSScriptRoot
$ManifestPath = Join-Path $Root 'manifests\rustup-windows.json'
$HelperPath = Join-Path $Root 'lib\rustup-windows.ps1'
. $HelperPath

$TempRoot = Join-Path ([IO.Path]::GetTempPath()) ('devkit-wulf-rustup-windows-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $TempRoot | Out-Null
$OldLocalAppData = $env:LOCALAPPDATA
$OldState = $env:DEVKIT_WULF_STATE_DIR
$OldPath = $env:PATH

try {
    $arch = Get-DevkitRustupWindowsArchitecture
    if ($arch -ne 'amd64') {
        Write-Output "Rustup Windows offline fixture skipped executable transaction on non-amd64 runner: $arch"
        exit 0
    }

    $env:LOCALAPPDATA = Join-Path $TempRoot 'local app data'
    $env:DEVKIT_WULF_STATE_DIR = Join-Path $TempRoot 'state dir'
    New-Item -ItemType Directory -Path $env:LOCALAPPDATA -Force | Out-Null

    $manifest = Get-DevkitRustupWindowsManifest -ManifestPath $ManifestPath
    $paths = Get-DevkitRustupWindowsPaths -Manifest $manifest
    $env:PATH = "$($paths.PathDirectory);$OldPath"
    $artifact = Get-DevkitRustupWindowsArtifact -ManifestPath $ManifestPath -Architecture $arch
    if ($artifact.TargetTriple -ne 'x86_64-pc-windows-msvc') { throw 'amd64 target triple mismatch' }
    if ($artifact.SourceUrl -ne 'https://static.rust-lang.org/rustup/dist/x86_64-pc-windows-msvc/rustup-init.exe') { throw 'rustup-init URL mismatch' }
    if ($artifact.ChecksumUrl -ne 'https://static.rust-lang.org/rustup/dist/x86_64-pc-windows-msvc/rustup-init.exe.sha256') { throw 'rustup checksum URL mismatch' }

    $fakeInstaller = Join-Path $TempRoot 'rustup-init.exe'
    [IO.File]::WriteAllBytes($fakeInstaller, [byte[]](0..255))
    $installerSha = (Get-FileHash -LiteralPath $fakeInstaller -Algorithm SHA256).Hash.ToLowerInvariant()
    $checksum = Join-Path $TempRoot 'rustup-init.exe.sha256'
    Set-Content -LiteralPath $checksum -Encoding ASCII -NoNewline -Value "$installerSha  rustup-init.exe"

    $sourceFile = Join-Path $TempRoot 'Stub.cs'
    $stubExe = Join-Path $TempRoot 'rust-stub.exe'
    @'
using System;
using System.IO;
using System.Reflection;
public static class Program {
    public static int Main(string[] args) {
        string name = Path.GetFileName(Assembly.GetEntryAssembly().Location).ToLowerInvariant();
        if (name == "rustup.exe") {
            if (args.Length == 1 && args[0] == "--version") { Console.WriteLine("rustup 9.9.9 (fixture)"); return 0; }
            if (args.Length == 2 && args[0] == "show" && args[1] == "active-toolchain") { Console.WriteLine("stable-x86_64-pc-windows-msvc (default)"); return 0; }
        }
        if (name == "rustc.exe" && args.Length == 1 && args[0] == "--version") { Console.WriteLine("rustc 9.9.9 (fixture)"); return 0; }
        if (name == "cargo.exe" && args.Length == 1 && args[0] == "--version") { Console.WriteLine("cargo 9.9.9 (fixture)"); return 0; }
        Console.Error.WriteLine("unexpected fixture invocation: " + name + " " + String.Join(" ", args));
        return 2;
    }
}
'@ | Set-Content -LiteralPath $sourceFile -Encoding ASCII

    $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    if (-not (Test-Path -LiteralPath $csc -PathType Leaf)) { throw "C# compiler required by offline fixture not found: $csc" }
    & $csc /nologo /target:exe "/out:$stubExe" $sourceFile
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $stubExe -PathType Leaf)) { throw 'fixture stub compilation failed' }

    function Invoke-DevkitRustupWindowsDownload {
        param([string]$Uri, [string]$Destination)
        if ($Uri -eq $artifact.ChecksumUrl) { Copy-Item -LiteralPath $checksum -Destination $Destination; return }
        if ($Uri -eq $artifact.SourceUrl) { Copy-Item -LiteralPath $fakeInstaller -Destination $Destination; return }
        throw "fixture blocked unexpected URL: $Uri"
    }

    function Invoke-DevkitRustupWindowsInstaller {
        param([string]$InstallerPath, [object]$Manifest, [object]$Paths)
        if ((Get-DevkitRustupWindowsSha256 -Path $InstallerPath) -ne $installerSha) { throw 'fixture installer was not the SHA-checked payload' }
        if (@($Manifest.install.arguments) -join ' ' -ne '-y --profile minimal --default-toolchain stable --no-modify-path') { throw 'installer arguments changed unexpectedly' }
        New-Item -ItemType Directory -Path $Paths.PathDirectory -Force | Out-Null
        New-Item -ItemType Directory -Path $Paths.RustupHome -Force | Out-Null
        Copy-Item -LiteralPath $stubExe -Destination (Join-Path $Paths.PathDirectory 'rustup.exe')
        Copy-Item -LiteralPath $stubExe -Destination (Join-Path $Paths.PathDirectory 'rustc.exe')
        Copy-Item -LiteralPath $stubExe -Destination (Join-Path $Paths.PathDirectory 'cargo.exe')
    }

    $expected = Get-DevkitRustupWindowsExpectedSha256 -ChecksumUrl $artifact.ChecksumUrl
    if ($expected -ne $installerSha) { throw 'checksum sidecar did not resolve expected SHA-256' }

    $plan = Get-DevkitRustupWindowsPlan -ManifestPath $ManifestPath -Architecture $arch
    if ($plan.MutatesHost -ne $false -or $plan.Sha256 -ne $installerSha) { throw 'plan contract is inconsistent' }
    if ((Test-Path -LiteralPath $paths.CargoHome) -or (Test-Path -LiteralPath $paths.RustupHome)) { throw 'plan unexpectedly mutated managed homes' }

    $result = Install-DevkitRustupWindowsArtifact -ManifestPath $ManifestPath -Architecture $arch
    if ($result.Result -ne 'installed') { throw 'first rust@stable installation did not report installed' }
    if (-not (Test-DevkitRustupWindowsManagedVerification -ManifestPath $ManifestPath -Architecture $arch)) { throw 'installed rust@stable fixture did not verify' }

    function Invoke-DevkitRustupWindowsDownload { throw 'second installation must be fully offline' }
    function Invoke-DevkitRustupWindowsInstaller { throw 'second installation must not rerun rustup-init' }
    $second = Install-DevkitRustupWindowsArtifact -ManifestPath $ManifestPath -Architecture $arch
    if ($second.Result -ne 'already-satisfied') { throw 'second rust@stable installation was not offline-idempotent' }

    Add-Content -LiteralPath (Join-Path $paths.PathDirectory 'cargo.exe') -Value 'tamper'
    if (Test-DevkitRustupWindowsManagedVerification -ManifestPath $ManifestPath -Architecture $arch) { throw 'tampered cargo.exe incorrectly verified' }

    $foreignLocal = Join-Path $TempRoot 'foreign local app data'
    $env:LOCALAPPDATA = $foreignLocal
    $foreignManifest = Get-DevkitRustupWindowsManifest -ManifestPath $ManifestPath
    $foreignPaths = Get-DevkitRustupWindowsPaths -Manifest $foreignManifest
    New-Item -ItemType Directory -Path $foreignPaths.CargoHome -Force | Out-Null
    New-Item -ItemType Directory -Path $foreignPaths.RustupHome -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $foreignPaths.CargoHome 'foreign.txt') -Value foreign
    $env:PATH = "$($foreignPaths.PathDirectory);$OldPath"
    function Invoke-DevkitRustupWindowsDownload { throw 'foreign-home conflict must be detected before network' }
    try {
        Install-DevkitRustupWindowsArtifact -ManifestPath $ManifestPath -Architecture $arch | Out-Null
        throw 'foreign managed homes unexpectedly accepted'
    } catch {
        if ($_.Exception.Message -notmatch 'GATE-08 existing CARGO_HOME/RUSTUP_HOME') { throw }
    }

    $env:LOCALAPPDATA = Join-Path $TempRoot 'checksum test local app data'
    New-Item -ItemType Directory -Path $env:LOCALAPPDATA -Force | Out-Null
    $badChecksum = Join-Path $TempRoot 'bad.sha256'
    Set-Content -LiteralPath $badChecksum -Value 'not-a-checksum' -Encoding ASCII
    function Invoke-DevkitRustupWindowsDownload {
        param([string]$Uri, [string]$Destination)
        Copy-Item -LiteralPath $badChecksum -Destination $Destination
    }
    try {
        Get-DevkitRustupWindowsExpectedSha256 -ChecksumUrl $artifact.ChecksumUrl | Out-Null
        throw 'malformed checksum sidecar unexpectedly accepted'
    } catch {
        if ($_.Exception.Message -notmatch 'checksum sidecar is malformed') { throw }
    }

    Write-Output 'Rustup Windows offline artifact fixture: OK'
} finally {
    $env:LOCALAPPDATA = $OldLocalAppData
    if ($null -eq $OldState) { Remove-Item Env:DEVKIT_WULF_STATE_DIR -ErrorAction SilentlyContinue } else { $env:DEVKIT_WULF_STATE_DIR = $OldState }
    $env:PATH = $OldPath
    if (Test-Path -LiteralPath $TempRoot) { Remove-Item -LiteralPath $TempRoot -Recurse -Force }
}
