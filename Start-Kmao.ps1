# Stable dispatcher: application and updater code live in versioned directories.
[CmdletBinding()]
param(
    [ValidateSet('bot', 'logger')][string]$Component = 'bot',
    [switch]$SkipUpdateCheck,
    [switch]$Rollback,
    [string]$HealthToken
)
$ErrorActionPreference = 'Stop'
try {
    $statePath = Join-Path $PSScriptRoot 'current.json'
    $pendingPath = Join-Path $PSScriptRoot 'pending.json'
    if (!$HealthToken -and (Test-Path -LiteralPath $pendingPath)) {
        # A worker interrupted between pointer activation and readiness leaves a journal.
        $gate = [Threading.Mutex]::new($false, 'Local\Kmao.Update')
        $locked = $false
        try {
            try { $locked = $gate.WaitOne(0) } catch [Threading.AbandonedMutexException] { $locked = $true }
            if (!$locked) { throw 'KMAO update is still running. Please wait.' }
            $pending = Get-Content -LiteralPath $pendingPath -Raw | ConvertFrom-Json
            if ($pending.version -notmatch '^\d+\.\d+\.\d+$' -or !(Test-Path -LiteralPath (Join-Path $PSScriptRoot "versions/$($pending.version)/Launch-Kmao.ps1"))) {
                throw 'Incomplete update has no usable recovery version. Reinstall KMAO.'
            }
            [IO.File]::Replace($pendingPath, $statePath, [NullString]::Value)
            $SkipUpdateCheck = $true
            Write-Warning 'Recovered previous version after an interrupted update.'
        }
        finally { if ($locked) { $gate.ReleaseMutex() }; $gate.Dispose() }
    }
    $global:LASTEXITCODE = 0
    if (Test-Path -LiteralPath $statePath) {
        $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        if ($state.version -notmatch '^\d+\.\d+\.\d+$') { throw 'Invalid installation state.' }
        $entry = Join-Path $PSScriptRoot "versions/$($state.version)/Launch-Kmao.ps1"
        & $entry -InstallRoot $PSScriptRoot -Component $Component -SkipUpdateCheck:$SkipUpdateCheck -Rollback:$Rollback -HealthToken $HealthToken
    }
    else {
        if ($Rollback) { throw 'Rollback requires an installed copy of KMAO.' }
        & (Join-Path $PSScriptRoot 'Launch-Kmao.ps1') -Component $Component -SkipUpdateCheck:$SkipUpdateCheck
    }
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
catch { Write-Error -ErrorRecord $_ -ErrorAction Continue; exit 1 }
