$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Root = Split-Path -Parent $PSScriptRoot
$Helper = Join-Path $Root 'lib\flutter-windows.ps1'
$ManifestPath = Join-Path $Root 'manifests\flutter-windows.json'
$TestRoot = Join-Path ([IO.Path]::GetTempPath()) ("devkit-wulf-flutter-windows-test-{0}" -f [guid]::NewGuid().ToString('N'))
$HomePath = Join-Path $TestRoot 'home'
$Develop = Join-Path $HomePath 'develop'
$StateDir = Join-Path $TestRoot 'state'
$FixtureRoot = Join-Path $TestRoot 'fixture'
$Archive = Join-Path $TestRoot 'flutter.zip'
$IndexFixture = Join-Path $TestRoot 'releases_windows.json'
$DownloadLog = Join-Path $TestRoot 'downloads.log'

New-Item -ItemType Directory -Path $Develop, $StateDir, (Join-Path $FixtureRoot 'flutter\bin') -Force | Out-Null
Set-Content -LiteralPath (Join-Path $FixtureRoot 'flutter\bin\flutter.bat') -Encoding ASCII -Value '@echo off', 'echo Flutter fixture 3.35.0'
Set-Content -LiteralPath (Join-Path $FixtureRoot 'flutter\bin\dart.bat') -Encoding ASCII -Value '@echo off', 'echo Dart fixture 3.9.0'
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::CreateFromDirectory($FixtureRoot, $Archive)
$ArchiveSha = (Get-FileHash -LiteralPath $Archive -Algorithm SHA256).Hash.ToLowerInvariant()

function Write-FlutterIndexFixture {
    param(
        [string]$BaseUrl = 'https://storage.googleapis.com/flutter_infra_release/releases',
        [string]$Sha256 = $ArchiveSha,
        [string]$ArchivePath = 'stable/windows/flutter_windows_3.35.0-stable.zip'
    )
    $index = [ordered]@{
        base_url = $BaseUrl
        current_release = [ordered]@{ stable = 'stable-hash-x64' }
        releases = @(
            [ordered]@{
                hash = 'stable-hash-x64'
                channel = 'stable'
                version = '3.35.0'
                dart_sdk_arch = 'x64'
                dart_sdk_version = '3.9.0'
                archive = $ArchivePath
                sha256 = $Sha256
            },
            [ordered]@{
                hash = 'old-hash-x64'
                channel = 'stable'
                version = '3.32.0'
                dart_sdk_arch = 'x64'
                archive = 'stable/windows/flutter_windows_3.32.0-stable.zip'
                sha256 = ('1' * 64)
            }
        )
    }
    $index | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $IndexFixture -Encoding UTF8
}

Write-FlutterIndexFixture
Set-Content -LiteralPath $DownloadLog -Encoding ASCII -Value @()

. $Helper

function Invoke-DevkitFlutterWindowsDownload {
    param([string]$Uri, [string]$Destination)
    Add-Content -LiteralPath $DownloadLog -Encoding ASCII -Value $Uri
    switch ($Uri) {
        'https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json' {
            Copy-Item -LiteralPath $IndexFixture -Destination $Destination
        }
        'https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_3.35.0-stable.zip' {
            Copy-Item -LiteralPath $script:CurrentArchive -Destination $Destination
        }
        default { throw "Unexpected fixture URL: $Uri" }
    }
}

$script:CurrentArchive = $Archive
$ManagedBin = Join-Path $Develop 'flutter\bin'
$OldPath = $env:PATH
$env:PATH = "$ManagedBin;$OldPath"

function Remove-TestDirectory([string]$Path) {
    if (Test-Path -LiteralPath $Path) { [IO.Directory]::Delete($Path, $true) }
}

try {
    $manifest = Get-DevkitFlutterWindowsManifest -ManifestPath $ManifestPath
    Assert-DevkitFlutterWindowsTarget -Manifest $manifest -Architecture 'amd64'
    $armBlocked = $false
    try { Assert-DevkitFlutterWindowsTarget -Manifest $manifest -Architecture 'arm64' } catch { $armBlocked = $_.Exception.Message -match 'does not support' }
    if (-not $armBlocked) { throw 'Windows ARM64 unexpectedly passed the Flutter target gate.' }

    $release = Get-DevkitFlutterWindowsRelease -ManifestPath $ManifestPath -Architecture 'amd64'
    if ($release.Version -ne '3.35.0') { throw 'Stable Flutter Windows release selection failed.' }
    if ($release.ReleaseArchitecture -ne 'x64') { throw 'Flutter Windows release architecture mapping failed.' }
    if ($release.SourceUrl -ne 'https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_3.35.0-stable.zip') { throw 'Flutter Windows source URL resolution failed.' }
    if ($release.Sha256 -ne $ArchiveSha) { throw 'Flutter Windows release SHA-256 resolution failed.' }

    $plan = Get-DevkitFlutterWindowsPlan -ManifestPath $ManifestPath -HomePath $HomePath -Architecture 'amd64'
    if ($plan.Support -ne 'experimental' -or $plan.Strategy -ne 'flutter-windows' -or $plan.MutatesHost -ne $false) { throw 'Flutter Windows plan contract drifted.' }
    if ($plan.PathMutation -ne 'none' -or $plan.Privilege -ne 'none') { throw 'Flutter Windows plan privilege/PATH policy drifted.' }
    if (Test-Path -LiteralPath (Join-Path $Develop 'flutter')) { throw 'Flutter Windows plan mutated the destination.' }

    Set-Content -LiteralPath $DownloadLog -Encoding ASCII -Value @()
    Install-DevkitFlutterWindowsArtifact -ManifestPath $ManifestPath -HomePath $HomePath -StateDirectory $StateDir -Architecture 'amd64'
    $Destination = Join-Path $Develop 'flutter'
    $Marker = Join-Path $Destination '.devkit-wulf-artifact.json'
    if (-not (Test-Path -LiteralPath $Marker -PathType Leaf)) { throw 'Flutter Windows ownership marker was not created.' }
    if (-not (Test-DevkitFlutterWindowsManagedVerification -ManifestPath $ManifestPath -HomePath $HomePath)) { throw 'Installed Flutter Windows SDK failed managed verification.' }
    $owned = Get-Content -LiteralPath $Marker -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($owned.version -ne '3.35.0' -or $owned.archive_sha256 -ne $ArchiveSha) { throw 'Flutter Windows marker release ownership drifted.' }
    $stateFile = Join-Path $StateDir 'flutter-windows.jsonl'
    if ((Get-Content -LiteralPath $stateFile | Select-Object -Last 1 | ConvertFrom-Json).action -ne 'installed-verified-artifact') { throw 'Flutter Windows verified state record missing.' }

    # Exact second install resolves current metadata but must not redownload/archive-replace the SDK.
    Set-Content -LiteralPath $DownloadLog -Encoding ASCII -Value @()
    Install-DevkitFlutterWindowsArtifact -ManifestPath $ManifestPath -HomePath $HomePath -StateDirectory $StateDir -Architecture 'amd64'
    $downloads = @(Get-Content -LiteralPath $DownloadLog | Where-Object { $_ })
    if ($downloads.Count -ne 1 -or $downloads[0] -ne 'https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json') {
        throw 'Flutter Windows idempotent install downloaded more than current release metadata.'
    }
    if ((Get-Content -LiteralPath $stateFile | Select-Object -Last 1 | ConvertFrom-Json).action -ne 'observed-exact-artifact') { throw 'Flutter Windows idempotent observation state missing.' }

    # Tampering with a critical managed launcher invalidates ownership verification.
    $FlutterBat = Join-Path $Destination 'bin\flutter.bat'
    Add-Content -LiteralPath $FlutterBat -Encoding ASCII -Value 'rem tampered'
    if (Test-DevkitFlutterWindowsManagedVerification -ManifestPath $ManifestPath -HomePath $HomePath) { throw 'Tampered Flutter Windows launcher unexpectedly verified.' }
    [IO.Directory]::Delete($Destination, $true)

    # Foreign existing directories fail before any network access.
    New-Item -ItemType Directory -Path $Destination | Out-Null
    Set-Content -LiteralPath $DownloadLog -Encoding ASCII -Value @()
    $foreignBlocked = $false
    try { Install-DevkitFlutterWindowsArtifact -ManifestPath $ManifestPath -HomePath $HomePath -StateDirectory $StateDir -Architecture 'amd64' } catch { $foreignBlocked = $_.Exception.Message -match 'not owned' }
    if (-not $foreignBlocked) { throw 'Foreign Flutter Windows SDK directory was not refused.' }
    if (@(Get-Content -LiteralPath $DownloadLog | Where-Object { $_ }).Count -ne 0) { throw 'Foreign Flutter conflict was checked after network access.' }
    [IO.Directory]::Delete($Destination, $true)

    # PATH prerequisite also fails before network access.
    $env:PATH = $OldPath
    Set-Content -LiteralPath $DownloadLog -Encoding ASCII -Value @()
    $pathBlocked = $false
    try { Install-DevkitFlutterWindowsArtifact -ManifestPath $ManifestPath -HomePath $HomePath -StateDirectory $StateDir -Architecture 'amd64' } catch { $pathBlocked = $_.Exception.Message -match 'PATH must already contain' }
    if (-not $pathBlocked) { throw 'Missing Flutter Windows PATH declaration was not refused.' }
    if (@(Get-Content -LiteralPath $DownloadLog | Where-Object { $_ }).Count -ne 0) { throw 'PATH gate ran after network access.' }
    $env:PATH = "$ManagedBin;$OldPath"

    # Wrong release-index base fails closed.
    Write-FlutterIndexFixture -BaseUrl 'https://evil.example/releases'
    $baseBlocked = $false
    try { Get-DevkitFlutterWindowsRelease -ManifestPath $ManifestPath -Architecture 'amd64' | Out-Null } catch { $baseBlocked = $_.Exception.Message -match 'base_url' }
    if (-not $baseBlocked) { throw 'Wrong Flutter Windows release-index base URL unexpectedly accepted.' }
    Write-FlutterIndexFixture

    # Checksum mismatch fails before destination creation.
    Write-FlutterIndexFixture -Sha256 ('0' * 64)
    $checksumBlocked = $false
    try { Install-DevkitFlutterWindowsArtifact -ManifestPath $ManifestPath -HomePath $HomePath -StateDirectory $StateDir -Architecture 'amd64' } catch { $checksumBlocked = $_.Exception.Message -match 'SHA-256 mismatch' }
    if (-not $checksumBlocked -or (Test-Path -LiteralPath $Destination)) { throw 'Flutter Windows checksum mismatch did not fail safely.' }
    Write-FlutterIndexFixture

    # Create an unsafe traversal ZIP with a matching metadata hash: the ZIP preflight must block it.
    $UnsafeZip = Join-Path $TestRoot 'unsafe.zip'
    $stream = [IO.File]::Open($UnsafeZip, [IO.FileMode]::Create)
    $zip = New-Object IO.Compression.ZipArchive($stream, [IO.Compression.ZipArchiveMode]::Create)
    try {
        $entry = $zip.CreateEntry('../evil.txt')
        $writer = New-Object IO.StreamWriter($entry.Open())
        $writer.Write('evil')
        $writer.Dispose()
        foreach ($name in @('flutter/bin/flutter.bat', 'flutter/bin/dart.bat')) {
            $entry = $zip.CreateEntry($name)
            $writer = New-Object IO.StreamWriter($entry.Open())
            $writer.Write('@echo off')
            $writer.Dispose()
        }
    } finally { $zip.Dispose(); $stream.Dispose() }
    $UnsafeSha = (Get-FileHash -LiteralPath $UnsafeZip -Algorithm SHA256).Hash.ToLowerInvariant()
    Write-FlutterIndexFixture -Sha256 $UnsafeSha
    $script:CurrentArchive = $UnsafeZip
    $unsafeBlocked = $false
    try { Install-DevkitFlutterWindowsArtifact -ManifestPath $ManifestPath -HomePath $HomePath -StateDirectory $StateDir -Architecture 'amd64' } catch { $unsafeBlocked = $_.Exception.Message -match 'unsafe Flutter Windows ZIP' }
    if (-not $unsafeBlocked -or (Test-Path -LiteralPath $Destination)) { throw 'Unsafe Flutter Windows ZIP unexpectedly accepted.' }

    # Wrong-root ZIP is also refused.
    $WrongRootSource = Join-Path $TestRoot 'wrong-root-source'
    New-Item -ItemType Directory -Path (Join-Path $WrongRootSource 'not-flutter\bin') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $WrongRootSource 'not-flutter\bin\flutter.bat') -Encoding ASCII -Value '@echo off'
    Set-Content -LiteralPath (Join-Path $WrongRootSource 'not-flutter\bin\dart.bat') -Encoding ASCII -Value '@echo off'
    $WrongRootZip = Join-Path $TestRoot 'wrong-root.zip'
    [IO.Compression.ZipFile]::CreateFromDirectory($WrongRootSource, $WrongRootZip)
    $WrongRootSha = (Get-FileHash -LiteralPath $WrongRootZip -Algorithm SHA256).Hash.ToLowerInvariant()
    Write-FlutterIndexFixture -Sha256 $WrongRootSha
    $script:CurrentArchive = $WrongRootZip
    $rootBlocked = $false
    try { Install-DevkitFlutterWindowsArtifact -ManifestPath $ManifestPath -HomePath $HomePath -StateDirectory $StateDir -Architecture 'amd64' } catch { $rootBlocked = $_.Exception.Message -match 'unsafe Flutter Windows ZIP' }
    if (-not $rootBlocked) { throw 'Wrong-root Flutter Windows ZIP unexpectedly accepted.' }

    # State-directory junctions are reparse points and must be refused.
    Remove-TestDirectory $StateDir
    $AlternateState = Join-Path $TestRoot 'alternate-state'
    New-Item -ItemType Directory -Path $AlternateState | Out-Null
    New-Item -ItemType Junction -Path $StateDir -Target $AlternateState | Out-Null
    $stateBlocked = $false
    try { Assert-DevkitFlutterWindowsStateReady -StateDirectory $StateDir | Out-Null } catch { $stateBlocked = $_.Exception.Message -match 'reparse point' }
    if (-not $stateBlocked) { throw 'Flutter Windows state-directory junction unexpectedly accepted.' }
    Remove-Item -LiteralPath $StateDir -Force

    # Install-parent junctions must also fail before release metadata access.
    Remove-TestDirectory $Develop
    $AlternateDevelop = Join-Path $TestRoot 'alternate-develop'
    New-Item -ItemType Directory -Path $AlternateDevelop | Out-Null
    New-Item -ItemType Junction -Path $Develop -Target $AlternateDevelop | Out-Null
    Set-Content -LiteralPath $DownloadLog -Encoding ASCII -Value @()
    $parentBlocked = $false
    try { Assert-DevkitFlutterWindowsPathPrerequisites -Manifest $manifest -HomePath $HomePath | Out-Null } catch { $parentBlocked = $_.Exception.Message -match 'reparse point' }
    if (-not $parentBlocked) { throw 'Flutter Windows install-parent junction unexpectedly accepted.' }

    Write-Host 'Flutter Windows offline artifact tests passed'
}
finally {
    $env:PATH = $OldPath
    if (Test-Path -LiteralPath $TestRoot) { [IO.Directory]::Delete($TestRoot, $true) }
}
