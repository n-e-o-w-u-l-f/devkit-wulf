param(
    [Parameter(Position = 0)]
    [ValidateSet('plan', 'install', 'verify')]
    [string]$Action = 'plan',
    [switch]$Experimental
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Stop-DevkitFlutterStable([string]$Message) {
    throw "[devkit-wulf][flutter@stable] $Message"
}

if ($env:OS -ne 'Windows_NT') {
    Stop-DevkitFlutterStable 'This adapter is for native Windows only.'
}
if ($Action -eq 'install' -and -not $Experimental) {
    Stop-DevkitFlutterStable 'flutter@stable remains experimental; install requires -Experimental.'
}

$RootDir = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$ManifestPath = Join-Path $RootDir 'manifests\flutter-windows.json'
$HelperPath = Join-Path $RootDir 'lib\flutter-windows.ps1'
if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) { Stop-DevkitFlutterStable "Manifest not found: $ManifestPath" }
if (-not (Test-Path -LiteralPath $HelperPath -PathType Leaf)) { Stop-DevkitFlutterStable "Helper not found: $HelperPath" }
. $HelperPath

function Invoke-DevkitFlutterStableRuntimeSmoke {
    $manifest = Get-DevkitFlutterWindowsManifest -ManifestPath $ManifestPath
    $destination = Resolve-DevkitFlutterWindowsHomeTemplate -Template ([string]$manifest.target.destination_template)
    $flutter = Join-Path $destination 'bin\flutter.bat'
    $dart = Join-Path $destination 'bin\dart.bat'
    if (-not (Test-Path -LiteralPath $flutter -PathType Leaf)) { Stop-DevkitFlutterStable 'Managed flutter.bat is missing.' }
    if (-not (Test-Path -LiteralPath $dart -PathType Leaf)) { Stop-DevkitFlutterStable 'Managed dart.bat is missing.' }
    & $flutter --version | Out-Null
    if ($LASTEXITCODE -ne 0) { Stop-DevkitFlutterStable 'flutter --version failed.' }
    & $dart --version | Out-Null
    if ($LASTEXITCODE -ne 0) { Stop-DevkitFlutterStable 'dart --version failed.' }
    Write-Output "flutter_root=$destination"
}

switch ($Action) {
    'plan' {
        $plan = Get-DevkitFlutterWindowsPlan -ManifestPath $ManifestPath
        $plan | Format-List
        break
    }
    'verify' {
        if (-not (Test-DevkitFlutterWindowsManagedVerification -ManifestPath $ManifestPath)) {
            Stop-DevkitFlutterStable 'Managed Flutter Windows marker/hash verification failed.'
        }
        Invoke-DevkitFlutterStableRuntimeSmoke
        Write-Output 'result=verified'
        break
    }
    'install' {
        Install-DevkitFlutterWindowsArtifact -ManifestPath $ManifestPath
        if (-not (Test-DevkitFlutterWindowsManagedVerification -ManifestPath $ManifestPath)) {
            Stop-DevkitFlutterStable 'Flutter installation completed but managed marker/hash verification failed.'
        }
        Invoke-DevkitFlutterStableRuntimeSmoke
        Write-Output 'result=installed-or-already-satisfied'
        break
    }
}
