param(
    [Parameter(Position = 0)]
    [ValidateSet('plan', 'install', 'verify')]
    [string]$Action = 'plan',
    [switch]$Experimental
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Stop-DevkitPython312([string]$Message) {
    throw "[devkit-wulf][python-3.12] $Message"
}

if ($env:OS -ne 'Windows_NT') {
    Stop-DevkitPython312 'This adapter is for native Windows only.'
}
if ($Action -eq 'install' -and -not $Experimental) {
    Stop-DevkitPython312 'Python 3.12 remains experimental; install requires -Experimental.'
}

$RootDir = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$ContractPath = Join-Path $RootDir 'environments\python\3.12.json'
if (-not (Test-Path -LiteralPath $ContractPath -PathType Leaf)) {
    Stop-DevkitPython312 "Shared contract not found: $ContractPath"
}
$Contract = Get-Content -LiteralPath $ContractPath -Raw -Encoding UTF8 | ConvertFrom-Json
$Adapter = $Contract.adapters.'windows-native'
if ($Adapter.support -ne 'experimental' -or $Adapter.strategy -ne 'python-install-manager') {
    Stop-DevkitPython312 'Shared contract does not authorize the Windows Python Install Manager strategy.'
}

$ManagerCommand = Get-Command pymanager -ErrorAction SilentlyContinue
if (-not $ManagerCommand) {
    Stop-DevkitPython312 'Python Install Manager is required. Install it separately before using this adapter.'
}
$Manager = $ManagerCommand.Source
$RuntimeTag = [string]$Adapter.runtime_tag
$MinimumVersion = [version][string]$Adapter.minimum_runtime_patch

function Get-ManagedPython312Executable {
    $output = @(& $Manager list --only-managed --one --format=exe $RuntimeTag 2>$null)
    if ($LASTEXITCODE -ne 0 -or $output.Count -ne 1) { return $null }
    $candidate = [string]$output[0]
    if ([string]::IsNullOrWhiteSpace($candidate) -or -not [IO.Path]::IsPathRooted($candidate)) { return $null }
    $candidate = [IO.Path]::GetFullPath($candidate.Trim())
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { return $null }
    return $candidate
}

function Get-Python312Version([string]$Executable) {
    $text = (& $Executable -c 'import sys; print("%d.%d.%d" % sys.version_info[:3])').Trim()
    if ($LASTEXITCODE -ne 0 -or $text -notmatch '^3\.12\.[0-9]+$') {
        Stop-DevkitPython312 "Managed runtime is not Python 3.12: $text"
    }
    return [version]$text
}

function Invoke-Python312VenvSmoke([string]$Executable) {
    $base = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
    $temp = Join-Path $base ('.devkit-wulf-python312-' + [guid]::NewGuid().ToString('N'))
    try {
        & $Executable -m venv $temp
        if ($LASTEXITCODE -ne 0) { Stop-DevkitPython312 'venv smoke test failed.' }
        $venvPython = Join-Path $temp 'Scripts\python.exe'
        if (-not (Test-Path -LiteralPath $venvPython -PathType Leaf)) {
            Stop-DevkitPython312 'venv did not create Scripts\python.exe.'
        }
        & $venvPython -m pip --version | Out-Null
        if ($LASTEXITCODE -ne 0) { Stop-DevkitPython312 'pip smoke test inside venv failed.' }
    } finally {
        if (Test-Path -LiteralPath $temp) {
            $resolved = [IO.Path]::GetFullPath($temp)
            $prefix = $base + [IO.Path]::DirectorySeparatorChar + '.devkit-wulf-python312-'
            if (-not $resolved.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
                Stop-DevkitPython312 "Refusing unsafe temporary cleanup path: $resolved"
            }
            Remove-Item -LiteralPath $resolved -Recurse -Force
        }
    }
}

function Test-Python312ManagedRuntime {
    $exe = Get-ManagedPython312Executable
    if (-not $exe) { return $false }
    $version = Get-Python312Version $exe
    if ($version -lt $MinimumVersion) {
        Stop-DevkitPython312 "Managed Python $version is below the researched security baseline $MinimumVersion. Automatic replacement/upgrades are intentionally not performed."
    }
    Invoke-Python312VenvSmoke $exe
    Write-Output "python_executable=$exe"
    Write-Output "python_version=$version"
    return $true
}

switch ($Action) {
    'plan' {
        Write-Output 'environment=python'
        Write-Output 'version_family=3.12'
        Write-Output 'platform=windows'
        Write-Output 'strategy=python-install-manager'
        Write-Output "runtime_tag=$RuntimeTag"
        Write-Output "minimum_security_baseline=$MinimumVersion"
        Write-Output 'path_mutation=none-by-devkit-wulf'
        Write-Output 'privilege=per-user'
        Write-Output 'mutation=python-install-manager-managed-runtime-only'
        & $Manager list --online --one --format=json $RuntimeTag
        if ($LASTEXITCODE -ne 0) { Stop-DevkitPython312 'Unable to resolve Python 3.12 from the Python Install Manager online index.' }
        & $Manager install --dry-run $RuntimeTag
        if ($LASTEXITCODE -ne 0) { Stop-DevkitPython312 'Python Install Manager dry-run failed.' }
        break
    }
    'verify' {
        if (-not (Test-Python312ManagedRuntime)) {
            Stop-DevkitPython312 'No Python Install Manager-owned Python 3.12 runtime is installed.'
        }
        break
    }
    'install' {
        $existing = Get-ManagedPython312Executable
        if ($existing) {
            Test-Python312ManagedRuntime | Out-Null
            Write-Output 'result=already-satisfied'
            break
        }

        $hadConfirm = Test-Path Env:PYTHON_MANAGER_CONFIRM
        $oldConfirm = $env:PYTHON_MANAGER_CONFIRM
        try {
            $env:PYTHON_MANAGER_CONFIRM = 'no'
            & $Manager install $RuntimeTag
            if ($LASTEXITCODE -ne 0) { Stop-DevkitPython312 'Python Install Manager failed to install Python 3.12.' }
        } finally {
            if ($hadConfirm) { $env:PYTHON_MANAGER_CONFIRM = $oldConfirm }
            else { Remove-Item Env:PYTHON_MANAGER_CONFIRM -ErrorAction SilentlyContinue }
        }

        if (-not (Test-Python312ManagedRuntime)) {
            Stop-DevkitPython312 'Python 3.12 installation completed but managed verification failed.'
        }
        Write-Output 'result=installed'
        break
    }
}
