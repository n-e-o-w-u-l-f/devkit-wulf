Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $PSScriptRoot
$ManifestPath = Join-Path $Root 'manifests\go-windows.json'
$HelperPath = Join-Path $Root 'lib\go-windows.ps1'
. $HelperPath

$TempRoot = Join-Path ([IO.Path]::GetTempPath()) ('devkit-wulf-go-windows-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $TempRoot | Out-Null
$OldLocalAppData = $env:LOCALAPPDATA
$OldState = $env:DEVKIT_WULF_STATE_DIR
$OldPath = $env:PATH

try {
    $env:LOCALAPPDATA = Join-Path $TempRoot 'local app data'
    $env:DEVKIT_WULF_STATE_DIR = Join-Path $TempRoot 'state dir'
    New-Item -ItemType Directory -Path $env:LOCALAPPDATA -Force | Out-Null

    $arch = Get-DevkitGoWindowsArchitecture
    if ($arch -ne 'amd64') {
        Write-Output "Go Windows offline fixture skipped executable install transaction on non-amd64 runner: $arch"
        exit 0
    }

    $version = 'go9.9.9'
    $filename = "$version.windows-$arch.zip"
    $sourceRoot = Join-Path $TempRoot 'source'
    $goBin = Join-Path $sourceRoot 'go\bin'
    New-Item -ItemType Directory -Path $goBin -Force | Out-Null

    $source = @"
using System;
public static class Program {
    public static int Main(string[] args) {
        if (args.Length > 0 && args[0] == "version") {
            Console.WriteLine("go version $version windows/$arch");
            return 0;
        }
        Console.WriteLine("fixture");
        return 0;
    }
}
"@
    $fakeGo = Join-Path $goBin 'go.exe'
    Add-Type -TypeDefinition $source -OutputAssembly $fakeGo -OutputType ConsoleApplication
    Copy-Item -LiteralPath $fakeGo -Destination (Join-Path $goBin 'gofmt.exe')

    $archive = Join-Path $TempRoot $filename
    Compress-Archive -Path (Join-Path $sourceRoot 'go') -DestinationPath $archive
    $sha = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    $releaseJson = Join-Path $TempRoot 'releases.json'
    @(
        [ordered]@{
            version = $version
            stable = $true
            files = @(
                [ordered]@{
                    filename = $filename
                    os = 'windows'
                    arch = $arch
                    version = $version
                    sha256 = $sha
                    size = (Get-Item -LiteralPath $archive).Length
                    kind = 'archive'
                }
            )
        }
    ) | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $releaseJson -Encoding UTF8

    function Invoke-DevkitGoWindowsDownload {
        param([string]$Uri, [string]$Destination)
        if ($Uri -eq 'https://go.dev/dl/?mode=json') {
            Copy-Item -LiteralPath $releaseJson -Destination $Destination
            return
        }
        if ($Uri -eq "https://go.dev/dl/$filename") {
            Copy-Item -LiteralPath $archive -Destination $Destination
            return
        }
        throw "fixture blocked unexpected URL: $Uri"
    }

    $manifest = Get-DevkitGoWindowsManifest -ManifestPath $ManifestPath
    $destination = Resolve-DevkitGoLocalAppDataTemplate -Template ([string]$manifest.target.destination_template)
    $pathDirectory = Resolve-DevkitGoLocalAppDataTemplate -Template ([string]$manifest.target.path_directory_template)
    $env:PATH = "$pathDirectory;$OldPath"

    $release = Get-DevkitGoWindowsRelease -ManifestPath $ManifestPath -Architecture $arch
    if ($release.Version -ne $version -or $release.Sha256 -ne $sha -or $release.SourceUrl -ne "https://go.dev/dl/$filename") {
        throw 'release selection did not preserve fixture version/source/SHA'
    }
    if (-not (Test-DevkitGoWindowsZipSafe -ArchivePath $archive -Manifest $manifest)) {
        throw 'valid fixture ZIP failed safety validation'
    }

    $plan = Get-DevkitGoWindowsPlan -ManifestPath $ManifestPath -Architecture $arch
    if ($plan.MutatesHost -ne $false -or $plan.Destination -ne $destination) { throw 'plan contract is inconsistent' }
    if (Test-Path -LiteralPath $destination) { throw 'plan unexpectedly mutated destination' }

    $result = Install-DevkitGoWindowsArtifact -ManifestPath $ManifestPath -Architecture $arch
    if ($result.Result -ne 'installed') { throw 'first installation did not report installed' }
    if (-not (Test-DevkitGoWindowsManagedVerification -ManifestPath $ManifestPath -Architecture $arch)) { throw 'installed fixture did not verify' }

    function Invoke-DevkitGoWindowsDownload { throw 'second install must be fully offline' }
    $second = Install-DevkitGoWindowsArtifact -ManifestPath $ManifestPath -Architecture $arch
    if ($second.Result -ne 'already-satisfied') { throw 'second installation was not idempotent/offline' }

    Add-Content -LiteralPath (Join-Path $destination 'bin\go.exe') -Value 'tamper'
    if (Test-DevkitGoWindowsManagedVerification -ManifestPath $ManifestPath -Architecture $arch) { throw 'tampered go.exe incorrectly verified' }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $unsafe = Join-Path $TempRoot 'unsafe.zip'
    $zip = [IO.Compression.ZipFile]::Open($unsafe, [IO.Compression.ZipArchiveMode]::Create)
    try {
        [void]$zip.CreateEntry('../escape.txt')
        [void]$zip.CreateEntry('go/bin/go.exe')
        [void]$zip.CreateEntry('go/bin/gofmt.exe')
    } finally { $zip.Dispose() }
    if (Test-DevkitGoWindowsZipSafe -ArchivePath $unsafe -Manifest $manifest) { throw 'traversal ZIP incorrectly passed safety validation' }

    $foreignLocal = Join-Path $TempRoot 'foreign local app data'
    New-Item -ItemType Directory -Path (Join-Path $foreignLocal 'devkit-wulf\go') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $foreignLocal 'devkit-wulf\go\foreign.txt') -Value foreign
    $env:LOCALAPPDATA = $foreignLocal
    $foreignBin = Resolve-DevkitGoLocalAppDataTemplate -Template ([string]$manifest.target.path_directory_template)
    $env:PATH = "$foreignBin;$OldPath"
    function Invoke-DevkitGoWindowsDownload { throw 'foreign conflict must be detected before network' }
    try {
        Install-DevkitGoWindowsArtifact -ManifestPath $ManifestPath -Architecture $arch | Out-Null
        throw 'foreign destination unexpectedly accepted'
    } catch {
        if ($_.Exception.Message -notmatch 'GATE-08 existing Go destination') { throw }
    }

    Write-Output 'Go Windows offline artifact fixture: OK'
} finally {
    $env:LOCALAPPDATA = $OldLocalAppData
    if ($null -eq $OldState) { Remove-Item Env:DEVKIT_WULF_STATE_DIR -ErrorAction SilentlyContinue } else { $env:DEVKIT_WULF_STATE_DIR = $OldState }
    $env:PATH = $OldPath
    if (Test-Path -LiteralPath $TempRoot) { Remove-Item -LiteralPath $TempRoot -Recurse -Force }
}
