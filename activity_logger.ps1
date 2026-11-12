param([string]$HealthToken)
# KMAO activity recorder. Hook callbacks enqueue events; only this thread writes files.
$ErrorActionPreference = 'Stop'
# Validate the package before loading shared code; diagnostics are unavailable at this stage.
$missingFiles = @(@('lib/Kmao.Common.ps1', 'lib/Kmao.Windows.cs', 'config/kmao.conf.example') | Where-Object {
    !(Test-Path -LiteralPath (Join-Path $PSScriptRoot $_) -PathType Leaf)
})
if ($missingFiles.Count -gt 0) {
    Write-Error ("Incomplete KMAO package. Missing: {0}. Copy the entire portable package, including lib and config. No application log was created." -f ($missingFiles -join ', ')) -ErrorAction Continue
    exit 1
}
. (Join-Path $PSScriptRoot 'lib/Kmao.Common.ps1')

function Write-PendingEvents {
    $batch = @($recorder.Drain())
    foreach ($line in $batch) {
        $fields = $line.Split(',')
        if ($fields[4]) { $fields[4] = ([System.Windows.Forms.Keys][int]$fields[4]).ToString() }
        $writer.WriteLine(($fields -join ','))
        $script:eventCount++
        $script:pendingWrites++
    }
    if ($script:pendingWrites -ge 100 -or $flushTimer.Elapsed.TotalSeconds -ge 10) {
        $writer.Flush()
        $script:pendingWrites = 0
        $flushTimer.Restart()
    }
    return $batch.Count
}

$recorder = $null
$session = $null
$writer = $null
$failed = $false
$eventCount = 0L
$pendingWrites = 0
try {
    Initialize-Kmao logger
    Import-KmaoWindows
    $session = Enter-KmaoSession -Component logger -HealthToken $HealthToken
    $configPath = Join-Path $KmaoRoot 'config/kmao.conf'
    Initialize-KmaoFile $configPath (Join-Path $PSScriptRoot 'config/kmao.conf.example')
    $config = Read-KmaoConfig $configPath @{
        MOUSE_SAMPLING_INTERVAL = 200
        RECORDING_DURATION_MINUTES = 480
    } @{
        MOUSE_SAMPLING_INTERVAL = @(1, 60000)
        RECORDING_DURATION_MINUTES = @(0, 525600)
    }
    $name = '{0}-{1}-{2}-recording.csv' -f (Get-Date -Format 'yyyy-MM-dd-HH-mm-ss-fff'), $PID, [Guid]::NewGuid().ToString('N')
    $logFile = Join-Path $KmaoRoot "data/$name"
    # CreateNew avoids overwriting any existing recording; FileShare.Read permits inspection.
    $stream = [IO.File]::Open($logFile, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
    try { $writer = [IO.StreamWriter]::new($stream, [Text.UTF8Encoding]::new($false)) }
    catch { $stream.Dispose(); throw }
    $writer.WriteLine('t,e,x,y,k')
    $writer.Flush()
    $flushTimer = [Diagnostics.Stopwatch]::StartNew()
    $recorder = New-KmaoInput -RecordEvents $true -SamplingMilliseconds $config.MOUSE_SAMPLING_INTERVAL
    Set-KmaoReady $HealthToken
    $duration = [Diagnostics.Stopwatch]::StartNew()
    Write-KmaoLog INFO "Recording started: $logFile. Press Ctrl+C to stop."
    while (!(Test-KmaoStopRequested $session) -and ($config.RECORDING_DURATION_MINUTES -eq 0 -or $duration.Elapsed.TotalMinutes -lt $config.RECORDING_DURATION_MINUTES)) {
        $recorder.CheckHealth()
        Write-PendingEvents | Out-Null
        Start-Sleep -Milliseconds 25
    }
    Write-KmaoLog INFO 'Recording loop finished (duration or shutdown request).'
}
catch {
    $failed = $true
    if ($script:KmaoLogFile) { Write-KmaoLog ERROR $_.Exception.ToString() }
    Write-Error -ErrorRecord $_ -ErrorAction Continue
}
finally {
    # Stop producers first, then drain their remaining events. Each cleanup is independent.
    if ($null -ne $recorder) {
        try { $recorder.Dispose() }
        catch {
            $failed = $true
            Write-KmaoLog ERROR $_.Exception.ToString()
            Write-Error -ErrorRecord $_ -ErrorAction Continue
        }
    }
    if ($null -ne $writer) {
        try {
            if ($null -ne $recorder) { while ((Write-PendingEvents) -gt 0) { } }
            $writer.Flush()
        }
        catch {
            $failed = $true
            Write-KmaoLog ERROR $_.Exception.ToString()
            Write-Error -ErrorRecord $_ -ErrorAction Continue
        }
        finally {
            try { $writer.Dispose() }
            catch {
                $failed = $true
                Write-KmaoLog ERROR $_.Exception.ToString()
                Write-Error -ErrorRecord $_ -ErrorAction Continue
            }
        }
    }
    Exit-KmaoSession $session
    if ($script:KmaoLogFile) { Write-KmaoLog INFO "Recorder stopped. Events written: $eventCount. Failure: $failed" }
}
if ($failed) { exit 1 }
