Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $PSScriptRoot
$ManifestPath = Join-Path $Root 'manifests\kubectl-native.json'
$HelperPath = Join-Path $Root 'lib\kubectl-windows.ps1'
. $HelperPath

$TempRoot = Join-Path ([IO.Path]::GetTempPath()) ('devkit-wulf-kubectl-windows-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $TempRoot | Out-Null
$OldLocal = $env:LOCALAPPDATA
$OldPath = $env:PATH

try {
    $arch = Get-DevkitKubectlWindowsArchitecture
    if ($arch -ne 'amd64') {
        Write-Output "Windows kubectl fixture skipped on non-amd64 runner: $arch"
        exit 0
    }

    $env:LOCALAPPDATA = Join-Path $TempRoot 'local app data'
    New-Item -ItemType Directory -Path $env:LOCALAPPDATA -Force | Out-Null
    $manifest = Get-DevkitKubectlWindowsManifest -ManifestPath $ManifestPath
    $target = Assert-DevkitKubectlWindowsTarget -Manifest $manifest -Architecture $arch
    $paths = Get-DevkitKubectlWindowsPaths -Target $target
    $env:PATH = "$($paths.PathDirectory);$OldPath"

    $version = 'v9.9.9'
    $versionFile = Join-Path $TempRoot 'stable.txt'
    Set-Content -LiteralPath $versionFile -Value $version -Encoding ASCII -NoNewline

    $sourceFile = Join-Path $TempRoot 'KubectlStub.cs'
    $fakeBinary = Join-Path $TempRoot 'kubectl.exe'
    @'
using System;
public static class Program {
    public static int Main(string[] args) {
        if (args.Length == 3 && args[0] == "version" && args[1] == "--client=true" && args[2] == "--output=json") {
            Console.WriteLine("{\"clientVersion\":{\"gitVersion\":\"v9.9.9\"}}");
            return 0;
        }
        return 2;
    }
}
'@ | Set-Content -LiteralPath $sourceFile -Encoding ASCII
    $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    if (-not (Test-Path -LiteralPath $csc -PathType Leaf)) { throw "C# compiler not found: $csc" }
    & $csc /nologo /target:exe "/out:$fakeBinary" $sourceFile
    if ($LASTEXITCODE -ne 0) { throw 'kubectl fixture compilation failed' }
    $sha = (Get-FileHash -LiteralPath $fakeBinary -Algorithm SHA256).Hash.ToLowerInvariant()
    $checksumFile = Join-Path $TempRoot 'kubectl.exe.sha256'
    Set-Content -LiteralPath $checksumFile -Value "$sha  kubectl.exe" -Encoding ASCII -NoNewline

    function Invoke-DevkitKubectlWindowsDownload {
        param([string]$Uri, [string]$Destination)
        if ($Uri -eq 'https://dl.k8s.io/release/stable.txt') { Copy-Item -LiteralPath $versionFile -Destination $Destination; return }
        if ($Uri -eq "https://dl.k8s.io/release/$version/bin/windows/amd64/kubectl.exe") { Copy-Item -LiteralPath $fakeBinary -Destination $Destination; return }
        if ($Uri -eq "https://dl.k8s.io/release/$version/bin/windows/amd64/kubectl.exe.sha256") { Copy-Item -LiteralPath $checksumFile -Destination $Destination; return }
        throw "fixture blocked unexpected URL: $Uri"
    }

    $artifact = Get-DevkitKubectlWindowsArtifact -ManifestPath $ManifestPath -Architecture $arch
    if ($artifact.Version -ne $version) { throw 'stable version resolution mismatch' }
    if ($artifact.SourceUrl -ne "https://dl.k8s.io/release/$version/bin/windows/amd64/kubectl.exe") { throw 'artifact URL mismatch' }
    $expected = Get-DevkitKubectlWindowsExpectedSha256 -ChecksumUrl $artifact.ChecksumUrl
    if ($expected -ne $sha) { throw 'checksum sidecar mismatch' }

    $plan = Get-DevkitKubectlWindowsPlan -ManifestPath $ManifestPath -Architecture $arch
    if ($plan.MutatesHost -ne $false -or $plan.Sha256 -ne $sha) { throw 'plan contract mismatch' }
    if (Test-Path -LiteralPath $paths.Binary) { throw 'plan unexpectedly mutated destination' }

    $first = Install-DevkitKubectlWindowsArtifact -ManifestPath $ManifestPath -Architecture $arch
    if ($first.Result -ne 'installed') { throw 'first kubectl install did not report installed' }
    if (-not (Test-DevkitKubectlWindowsManagedVerification -ManifestPath $ManifestPath -Architecture $arch)) { throw 'installed kubectl fixture did not verify' }

    function Invoke-DevkitKubectlWindowsDownload { throw 'second install must be fully offline' }
    $second = Install-DevkitKubectlWindowsArtifact -ManifestPath $ManifestPath -Architecture $arch
    if ($second.Result -ne 'already-satisfied') { throw 'second kubectl install was not offline-idempotent' }

    Add-Content -LiteralPath $paths.Binary -Value 'tamper'
    if (Test-DevkitKubectlWindowsManagedVerification -ManifestPath $ManifestPath -Architecture $arch) { throw 'tampered kubectl.exe incorrectly verified' }

    $env:LOCALAPPDATA = Join-Path $TempRoot 'foreign local app data'
    New-Item -ItemType Directory -Path $env:LOCALAPPDATA -Force | Out-Null
    $foreignTarget = Assert-DevkitKubectlWindowsTarget -Manifest $manifest -Architecture $arch
    $foreignPaths = Get-DevkitKubectlWindowsPaths -Target $foreignTarget
    New-Item -ItemType Directory -Path $foreignPaths.PathDirectory -Force | Out-Null
    Set-Content -LiteralPath $foreignPaths.Binary -Value foreign -Encoding ASCII
    $env:PATH = "$($foreignPaths.PathDirectory);$OldPath"
    function Invoke-DevkitKubectlWindowsDownload { throw 'foreign conflict must be detected before network' }
    try {
        Install-DevkitKubectlWindowsArtifact -ManifestPath $ManifestPath -Architecture $arch | Out-Null
        throw 'foreign kubectl destination unexpectedly accepted'
    } catch {
        if ($_.Exception.Message -notmatch 'GATE-08 existing kubectl selector destination') { throw }
    }

    Write-Output 'Windows kubectl offline artifact fixture: OK'
} finally {
    $env:LOCALAPPDATA = $OldLocal
    $env:PATH = $OldPath
    if (Test-Path -LiteralPath $TempRoot) { Remove-Item -LiteralPath $TempRoot -Recurse -Force }
}
