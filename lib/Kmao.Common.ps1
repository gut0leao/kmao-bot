# Shared paths, configuration validation and operational logging (Windows PowerShell 5.1).
function Initialize-Kmao {
    param(
        [Parameter(Mandatory = $true)][string]$Component,
        [string]$ProfileDirectory = [Environment]::GetFolderPath('UserProfile')
    )
    $script:KmaoLogFile = $null
    if ([string]::IsNullOrWhiteSpace($ProfileDirectory)) { throw 'User profile directory is unavailable.' }
    $root = Join-Path $ProfileDirectory '.kmao-bot'
    foreach ($folder in @('', 'config', 'data', 'logs')) {
        $path = if ($folder) { Join-Path $root $folder } else { $root }
        New-Item -ItemType Directory -Path $path -Force -ErrorAction Stop | Out-Null
    }
    $script:KmaoRoot = $root
    $script:KmaoLogFile = Join-Path $root ('logs/{0}-{1}-{2}-{3}.log' -f $Component, (Get-Date -Format 'yyyyMMdd-HHmmss-fff'), $PID, [Guid]::NewGuid().ToString('N'))
    # Fail startup immediately if the diagnostics file cannot be created.
    New-Item -ItemType File -Path $script:KmaoLogFile -ErrorAction Stop | Out-Null
    Write-KmaoLog INFO "Application directory: $root"
    Write-Host "Log: $script:KmaoLogFile"
}

function Write-KmaoLog {
    param(
        [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level,
        [string]$Message
    )
    $line = '{0} [{1}] {2}' -f [DateTimeOffset]::Now.ToString('o'), $Level, ($Message -replace '[\r\n]+', ' | ')
    try { Add-Content -LiteralPath $script:KmaoLogFile -Value $line -Encoding UTF8 -ErrorAction Stop }
    catch { Write-Warning "Could not write operational log: $($_.Exception.Message)" }
    if ($Level -eq 'ERROR') { Write-Warning $line }
    else { Write-Host $line }
}

function Initialize-KmaoFile {
    param([string]$Destination, [string]$Template)
    if (!(Test-Path -LiteralPath $Destination)) {
        # Never replace an existing user configuration or phrase list.
        Copy-Item -LiteralPath $Template -Destination $Destination -ErrorAction Stop
        Write-KmaoLog INFO "Created user file: $Destination"
    }
}

function Read-KmaoConfig {
    param([string]$Path, [hashtable]$Defaults, [hashtable]$Ranges)
    $values = $Defaults.Clone()
    $seen = @{}
    $lineNumber = 0
    foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8 -ErrorAction Stop) {
        $lineNumber++
        if ($line -match '^\s*(#.*)?$') { continue }
        if ($line -notmatch '^\s*([A-Z_]+)\s*=\s*([0-9]+)\s*$') {
            throw "Invalid configuration at ${Path}:${lineNumber}. Expected NAME=integer (without quotes)."
        }
        $key = $matches[1]
        $raw = $matches[2]
        if (!$Defaults.ContainsKey($key)) { throw "Unknown configuration key '$key' at ${Path}:${lineNumber}." }
        if ($seen.ContainsKey($key)) { throw "Duplicate configuration key '$key' at ${Path}:${lineNumber}." }
        $number = 0
        if (![int]::TryParse($raw, [ref]$number) -or $number -lt $Ranges[$key][0] -or $number -gt $Ranges[$key][1]) {
            throw "Configuration '$key' must be an integer between $($Ranges[$key][0]) and $($Ranges[$key][1])."
        }
        $values[$key] = $number
        $seen[$key] = $true
    }
    return $values
}

function Import-KmaoWindows {
    if ($env:OS -ne 'Windows_NT') { throw 'KMAO requires Windows and Windows PowerShell 5.1 or later.' }
    if (!('Kmao.WindowsInput' -as [type])) {
        Add-Type -Path (Join-Path $PSScriptRoot 'Kmao.Windows.cs') -ErrorAction Stop
    }
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
}

function New-KmaoInput {
    param([bool]$RecordEvents, [int]$SamplingMilliseconds)
    return [Kmao.WindowsInput]::new($RecordEvents, $SamplingMilliseconds)
}

function Get-KmaoUpdateMutex {
    return [Threading.Mutex]::new($false, 'Local\Kmao.Update')
}

function Test-KmaoInstallerRunning {
    try {
        $installer = [Threading.Mutex]::OpenExisting('Local\Kmao.Install')
        $installer.Dispose()
        return $true
    } catch [Threading.WaitHandleCannotBeOpenedException] { return $false }
}

function Enter-KmaoSession {
    param([ValidateSet('bot', 'logger')][string]$Component, [string]$HealthToken)
    $gate = Get-KmaoUpdateMutex
    $locked = $false
    $componentMutex = $null
    $stop = $null
    try {
        if (Test-KmaoInstallerRunning) { throw 'KMAO installer is running. Wait for it to finish.' }
        # The updater's first startup owns a named health event and may pass its gate.
        $authorized = $false
        if ($HealthToken) {
            if ($HealthToken -notmatch '^[a-f0-9]{32}$') { throw 'Invalid health token.' }
            $health = [Threading.EventWaitHandle]::OpenExisting("Local\Kmao.Health.$HealthToken")
            $health.Dispose()
            $authorized = $true
        }
        if (!$authorized) {
            try { $locked = $gate.WaitOne(0) } catch [Threading.AbandonedMutexException] { $locked = $true }
            if (!$locked) { throw 'KMAO is being updated. Wait for the update to finish.' }
        }
        $componentMutex = [Threading.Mutex]::new($false, "Local\Kmao.Component.$Component")
        $acquired = $false
        try { $acquired = $componentMutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $acquired = $true }
        if (!$acquired) { throw "KMAO $Component is already running." }
        $stop = [Threading.EventWaitHandle]::new($false, [Threading.EventResetMode]::ManualReset, "Local\Kmao.Stop.$Component")
        $stop.Reset() | Out-Null
        return @{ Mutex = $componentMutex; Stop = $stop }
    }
    catch {
        if ($null -ne $stop) { $stop.Dispose() }
        if ($null -ne $componentMutex) {
            if ($acquired) { $componentMutex.ReleaseMutex() }
            $componentMutex.Dispose()
        }
        throw
    }
    finally { if ($locked) { $gate.ReleaseMutex() }; $gate.Dispose() }
}

function Test-KmaoStopRequested {
    param($Session)
    return ($null -ne $Session -and $Session.Stop.WaitOne(0))
}

function Exit-KmaoSession {
    param($Session)
    if ($null -ne $Session) {
        try { $Session.Stop.Dispose() }
        finally { $Session.Mutex.ReleaseMutex(); $Session.Mutex.Dispose() }
    }
}

function Set-KmaoReady {
    param([string]$HealthToken)
    if ($HealthToken) {
        $health = [Threading.EventWaitHandle]::OpenExisting("Local\Kmao.Health.$HealthToken")
        try { $health.Set() | Out-Null } finally { $health.Dispose() }
    }
}
