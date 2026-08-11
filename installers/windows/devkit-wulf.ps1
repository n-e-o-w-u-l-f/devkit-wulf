param(
    [Parameter(Position = 0)]
    [string]$Command,
    [Parameter(Position = 1)]
    [string]$Target,
    [switch]$Experimental,
    [switch]$AcceptRemoteScript,
    [switch]$Supported,
    [string]$Platform
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT') {
    throw '[devkit-wulf] This entrypoint is for native Windows only.'
}

$RootDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$Core = Join-Path $RootDir 'bin\devkit-wulf.ps1'
if (-not (Test-Path -LiteralPath $Core -PathType Leaf)) {
    throw "[devkit-wulf] Windows orchestrator core not found: $Core"
}

$Forward = @()
if ($PSBoundParameters.ContainsKey('Command')) { $Forward += $Command }
if ($PSBoundParameters.ContainsKey('Target')) { $Forward += $Target }
if ($Experimental) { $Forward += '-Experimental' }
if ($AcceptRemoteScript) { $Forward += '-AcceptRemoteScript' }
if ($Supported) { $Forward += '-Supported' }
if ($PSBoundParameters.ContainsKey('Platform')) {
    $Forward += '-Platform'
    $Forward += $Platform
}

& $Core @Forward
if ($LASTEXITCODE -is [int]) { exit $LASTEXITCODE }
