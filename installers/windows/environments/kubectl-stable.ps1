param(
    [Parameter(Position = 0)]
    [ValidateSet('plan', 'install', 'verify')]
    [string]$Action = 'plan',
    [switch]$Experimental
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Stop-DevkitKubectlStable([string]$Message) {
    throw "[devkit-wulf][kubectl@stable] $Message"
}

if ($env:OS -ne 'Windows_NT') { Stop-DevkitKubectlStable 'This adapter is for native Windows only.' }
if ($Action -eq 'install' -and -not $Experimental) { Stop-DevkitKubectlStable 'kubectl@stable remains experimental; install requires -Experimental.' }

$RootDir = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$ManifestPath = Join-Path $RootDir 'manifests\kubectl-native.json'
$HelperPath = Join-Path $RootDir 'lib\kubectl-windows.ps1'
if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) { Stop-DevkitKubectlStable "Manifest not found: $ManifestPath" }
if (-not (Test-Path -LiteralPath $HelperPath -PathType Leaf)) { Stop-DevkitKubectlStable "Helper not found: $HelperPath" }
. $HelperPath

switch ($Action) {
    'plan' { Get-DevkitKubectlWindowsPlan -ManifestPath $ManifestPath | Format-List; break }
    'verify' {
        if (-not (Test-DevkitKubectlWindowsManagedVerification -ManifestPath $ManifestPath)) { Stop-DevkitKubectlStable 'Managed Windows kubectl verification failed.' }
        Write-Output 'result=verified'
        break
    }
    'install' {
        Install-DevkitKubectlWindowsArtifact -ManifestPath $ManifestPath | Format-List
        if (-not (Test-DevkitKubectlWindowsManagedVerification -ManifestPath $ManifestPath)) { Stop-DevkitKubectlStable 'kubectl installation completed but managed verification failed.' }
        break
    }
}
