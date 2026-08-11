param(
    [Parameter(Position = 0)]
    [ValidateSet('plan', 'install', 'verify')]
    [string]$Action = 'plan',
    [switch]$Experimental
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Stop-DevkitGoStable([string]$Message) {
    throw "[devkit-wulf][go@stable] $Message"
}

if ($env:OS -ne 'Windows_NT') { Stop-DevkitGoStable 'This adapter is for native Windows only.' }
if ($Action -eq 'install' -and -not $Experimental) { Stop-DevkitGoStable 'go@stable remains experimental; install requires -Experimental.' }

$RootDir = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$ManifestPath = Join-Path $RootDir 'manifests\go-windows.json'
$HelperPath = Join-Path $RootDir 'lib\go-windows.ps1'
if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) { Stop-DevkitGoStable "Manifest not found: $ManifestPath" }
if (-not (Test-Path -LiteralPath $HelperPath -PathType Leaf)) { Stop-DevkitGoStable "Helper not found: $HelperPath" }
. $HelperPath

switch ($Action) {
    'plan' {
        Get-DevkitGoWindowsPlan -ManifestPath $ManifestPath | Format-List
        break
    }
    'verify' {
        if (-not (Test-DevkitGoWindowsManagedVerification -ManifestPath $ManifestPath)) { Stop-DevkitGoStable 'Managed Go Windows verification failed.' }
        Write-Output 'result=verified'
        break
    }
    'install' {
        Install-DevkitGoWindowsArtifact -ManifestPath $ManifestPath | Format-List
        if (-not (Test-DevkitGoWindowsManagedVerification -ManifestPath $ManifestPath)) { Stop-DevkitGoStable 'Go installation completed but managed verification failed.' }
        break
    }
}
