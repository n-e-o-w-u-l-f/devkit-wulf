[CmdletBinding()]
param(
    [switch]$PlanWSL2,
    [switch]$InstallWSL2,
    [string]$Distribution,
    [switch]$AllowSystemChange
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RootDir = Split-Path -Parent $PSScriptRoot

function Log([string]$Message) { Write-Host "[devkit-wulf bootstrap] $Message" }
function Fail([string]$Message) { throw "[devkit-wulf bootstrap] $Message" }
function Test-Admin {
    return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not $env:OS -or $env:OS -ne 'Windows_NT') { Fail 'bootstrap/windows.ps1 is for native Windows.' }

$winget = Get-Command winget.exe -ErrorAction SilentlyContinue
if (-not $winget) {
    Fail 'WinGet is not available. Install/update Microsoft App Installer from an official Microsoft source, then rerun. devkit-wulf does not substitute an arbitrary package manager.'
}
Log "WinGet detected: $(& winget.exe --version)"

$wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
if ($PlanWSL2 -or $InstallWSL2) {
    Write-Host 'WSL2 plan:'
    Write-Host '  - Windows optional virtualization/WSL components may be enabled.'
    Write-Host '  - A reboot may be required.'
    Write-Host '  - Existing WSL1 distributions will NOT be converted automatically.'
    if ($Distribution) { Write-Host "  - requested distribution: $Distribution" }
    else { Write-Host '  - no distribution requested; no distro will be selected implicitly by devkit-wulf.' }
    Write-Host "  - administrator currently: $(Test-Admin)"
    Write-Host '  - project files will not be relocated.'
}

if ($InstallWSL2) {
    if (-not $AllowSystemChange) { Fail 'WSL installation changes Windows features. Review the plan and rerun with -AllowSystemChange.' }
    if (-not (Test-Admin)) { Fail 'WSL feature installation requires an elevated PowerShell session.' }

    if ($Distribution) {
        $online = @(& wsl.exe --list --online 2>$null)
        if ($LASTEXITCODE -ne 0) { Fail 'Unable to query WSL online distributions.' }
        $escaped = [regex]::Escape($Distribution)
        if (-not ($online -match "(?im)^\s*$escaped(?:\s|$)")) {
            Write-Host ($online -join [Environment]::NewLine)
            Fail "Requested WSL distribution '$Distribution' was not found in the current official WSL online list. Use the exact listed name."
        }
        Log "Installing WSL2 distribution '$Distribution' via wsl.exe."
        & wsl.exe --install -d $Distribution
        if ($LASTEXITCODE -ne 0) { Fail "wsl --install failed with exit code $LASTEXITCODE" }
    } else {
        Log 'Enabling/installing WSL without selecting a distribution.'
        & wsl.exe --install --no-distribution
        if ($LASTEXITCODE -ne 0) { Fail "wsl --install --no-distribution failed with exit code $LASTEXITCODE" }
    }
}

if (Get-Command wsl.exe -ErrorAction SilentlyContinue) {
    Log 'Current WSL distributions:'
    & wsl.exe --list --verbose 2>$null
    if ($LASTEXITCODE -eq 0) {
        $raw = @(& wsl.exe --list --verbose 2>$null)
        if ($raw -match '(?m)\s1\s*$') {
            Write-Warning '[devkit-wulf bootstrap] One or more WSL1 distributions were detected. They are not converted automatically. Back up the distribution and plan an explicit wsl --set-version <name> 2 operation if desired.'
        }
    }
}

& (Join-Path $RootDir 'bin\devkit-wulf.ps1') doctor
Log 'Windows bootstrap completed.'
