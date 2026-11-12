# No desktop input is generated. Exercises actual Windows process/event/mutex coordination.
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { Write-Host 'SKIP: lifecycle integration requires Windows named events.'; return }
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $repo 'lib/Kmao.Common.ps1')
. (Join-Path $repo 'lib/Kmao.Update.ps1')
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('kmao-lifecycle-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $temporary | Out-Null
$workers = @()
$gate = $null; $locked = $false
try {
    $common = Join-Path $repo 'lib/Kmao.Common.ps1'
    $fixture = Join-Path $PSScriptRoot 'fixtures/SessionWorker.ps1'
    $ready = Join-Path $temporary 'ready'
    $argsText = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -CommonPath "{1}" -ReadyPath "{2}" -CleanupMilliseconds 2000' -f $fixture, $common, $ready
    $worker = Start-Process -FilePath (Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe') -ArgumentList $argsText -PassThru
    $workers += $worker
    $timer = [Diagnostics.Stopwatch]::StartNew()
    while (!(Test-Path -LiteralPath $ready)) {
        if ($worker.HasExited -or $timer.Elapsed.TotalSeconds -ge 15) { throw 'Session worker did not start.' }
        Start-Sleep -Milliseconds 50
    }
    $blocked = $false
    try { $duplicate = Enter-KmaoSession bot; Exit-KmaoSession $duplicate }
    catch { if ($_.Exception.Message -notmatch 'already running') { throw }; $blocked = $true }
    if (!$blocked) { throw 'Duplicate component session was allowed.' }
    $timedOut = $false
    try { Stop-KmaoComponents -TimeoutSeconds 1 }
    catch { if ($_.Exception.Message -notmatch 'did not finish cleanup') { throw }; $timedOut = $true }
    if (!$timedOut) { throw 'Updater did not wait for delayed cleanup.' }
    Stop-KmaoComponents -TimeoutSeconds 10
    if (!$worker.WaitForExit(5000)) { throw 'Worker did not exit after cooperative stop.' }
    # A separate process cannot enter the session while the updater owns its gate.
    Remove-Item -LiteralPath $ready
    $gate = Get-KmaoUpdateMutex; $locked = $gate.WaitOne(0)
    if (!$locked) { throw 'Could not acquire test update gate.' }
    $blockedWorker = Start-Process -FilePath (Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe') -ArgumentList $argsText -PassThru -RedirectStandardError (Join-Path $temporary 'blocked-error.txt')
    $workers += $blockedWorker
    if (!$blockedWorker.WaitForExit(10000) -or $blockedWorker.ExitCode -eq 0 -or (Test-Path $ready)) { throw 'Update gate did not block a new session.' }
    Write-Host 'PASS: duplicate-session prevention, cooperative stop, cleanup timeout and update/start concurrency.'
}
finally {
    if ($locked) { $gate.ReleaseMutex() }
    if ($null -ne $gate) { $gate.Dispose() }
    foreach ($process in $workers) {
        if (!$process.HasExited) { $process.Kill(); $process.WaitForExit() } # Only processes created by this test.
        $process.Dispose()
    }
    Remove-Item -LiteralPath $temporary -Recurse -Force
}
