$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Cli = Join-Path $Root 'bin\devkit-wulf.ps1'
$TempState = Join-Path ([IO.Path]::GetTempPath()) ("devkit-wulf-test-{0}" -f [guid]::NewGuid())
$env:DEVKIT_WULF_STATE_DIR = $TempState

try {
    $detect = & $Cli detect | Out-String
    if ($LASTEXITCODE -ne 0 -or $detect -notmatch 'platform\s*:\s*windows') { throw 'detect did not report Windows' }

    $list = & $Cli list | Out-String
    if ($list -notmatch '(?m)^base\s+') { throw 'base environment missing from list' }

    $plan = & $Cli plan base | Out-String
    if ($plan -notmatch 'mutates_host=false') { throw 'plan did not prove non-mutation' }

    try {
        & $Cli remove base | Out-Null
        throw 'unsafe remove unexpectedly succeeded'
    } catch {
        if ($_.Exception.Message -match 'unexpectedly succeeded') { throw }
    }

    & $Cli install profile:full | Out-Null
    $state = Join-Path $TempState 'state.jsonl'
    if (Test-Path $state) {
        if ((Get-Item $state).Length -gt 0) { throw 'profile:full mutated state without -Experimental' }
    }

    Write-Host 'PowerShell CLI smoke tests passed'
}
finally {
    Remove-Item -LiteralPath $TempState -Recurse -Force -ErrorAction SilentlyContinue
}
