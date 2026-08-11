param(
    [Parameter(Position = 0)]
    [ValidateSet('plan', 'install', 'verify')]
    [string]$Action = 'plan',
    [switch]$Experimental
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Stop-DevkitRustStable([string]$Message) {
    throw "[devkit-wulf][rust@stable] $Message"
}

if ($env:OS -ne 'Windows_NT') {
    Stop-DevkitRustStable 'This adapter is for native Windows only.'
}
if ($Action -eq 'install' -and -not $Experimental) {
    Stop-DevkitRustStable 'rust@stable remains experimental; install requires -Experimental.'
}

$RootDir = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$ManifestPath = Join-Path $RootDir 'manifests\rustup-windows.json'
$HelperPath = Join-Path $RootDir 'lib\rustup-windows.ps1'
if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) { Stop-DevkitRustStable "Manifest not found: $ManifestPath" }
if (-not (Test-Path -LiteralPath $HelperPath -PathType Leaf)) { Stop-DevkitRustStable "Helper not found: $HelperPath" }
. $HelperPath

switch ($Action) {
    'plan' {
        Get-DevkitRustupWindowsPlan -ManifestPath $ManifestPath | Format-List
        break
    }
    'verify' {
        if (-not (Test-DevkitRustupWindowsManagedVerification -ManifestPath $ManifestPath)) {
            Stop-DevkitRustStable 'Managed Windows Rust stable verification failed.'
        }
        Write-Output 'result=verified'
        break
    }
    'install' {
        Install-DevkitRustupWindowsArtifact -ManifestPath $ManifestPath | Format-List
        if (-not (Test-DevkitRustupWindowsManagedVerification -ManifestPath $ManifestPath)) {
            Stop-DevkitRustStable 'Rust installation completed but managed verification failed.'
        }
        break
    }
}
