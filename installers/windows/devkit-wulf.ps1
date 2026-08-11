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

if ($Target -eq 'python@3.12') {
    if ($Command -notin @('plan', 'install', 'verify')) {
        throw '[devkit-wulf] python@3.12 supports only plan, install and verify.'
    }
    if ($AcceptRemoteScript -or $Supported -or $PSBoundParameters.ContainsKey('Platform')) {
        throw '[devkit-wulf] python@3.12 does not accept -AcceptRemoteScript, -Supported or -Platform.'
    }

    $Adapter = Join-Path $RootDir 'installers\windows\environments\python-3.12.ps1'
    if (-not (Test-Path -LiteralPath $Adapter -PathType Leaf)) {
        throw "[devkit-wulf] Python 3.12 Windows adapter not found: $Adapter"
    }

    & $Adapter -Action $Command -Experimental:$Experimental
    return
}

if ($Target -eq 'go@stable') {
    throw '[devkit-wulf] go@stable is not enabled on Windows: the current verified Go artifact contract contains Linux and macOS targets only. A Windows-native Go artifact adapter requires a separate reviewed contract.'
}

$Core = Join-Path $RootDir 'bin\devkit-wulf.ps1'
if (-not (Test-Path -LiteralPath $Core -PathType Leaf)) {
    throw "[devkit-wulf] Windows orchestrator core not found: $Core"
}

$Forward = @{}
if ($PSBoundParameters.ContainsKey('Command')) { $Forward.Command = $Command }
if ($PSBoundParameters.ContainsKey('Target')) { $Forward.Target = $Target }
if ($Experimental) { $Forward.Experimental = $true }
if ($AcceptRemoteScript) { $Forward.AcceptRemoteScript = $true }
if ($Supported) { $Forward.Supported = $true }
if ($PSBoundParameters.ContainsKey('Platform')) { $Forward.Platform = $Platform }

& $Core @Forward
