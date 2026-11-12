# Interactive end-to-end bot startup/shutdown. Uses an isolated profile and disables cycles.
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'This test requires Windows.' }
$repo = [IO.Path]::GetFullPath((Resolve-Path (Join-Path $PSScriptRoot '..')).ProviderPath)
. (Join-Path $repo 'lib/Kmao.Common.ps1')
Import-KmaoDesktop
$probe = [Threading.Mutex]::new($false, 'Local\Kmao.Component.bot')
$available = $false
try { try { $available = $probe.WaitOne(0) } catch [Threading.AbandonedMutexException] { $available = $true } }
finally { if ($available) { $probe.ReleaseMutex() }; $probe.Dispose() }
if (!$available) { throw 'Close the running KMAO bot before this interactive test.' }
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('kmao-bot-desktop-' + [Guid]::NewGuid().ToString('N'))
$configDirectory = Join-Path $temporary '.kmao-bot/config'
New-Item -ItemType Directory $configDirectory -Force | Out-Null
$config = [IO.File]::ReadAllText((Join-Path $repo 'config/bot.conf.example')) -replace 'IDLE_TIME_THRESHOLD=60', 'IDLE_TIME_THRESHOLD=86400'
[IO.File]::WriteAllText((Join-Path $configDirectory 'bot.conf'), $config)
$token = [Guid]::NewGuid().ToString('N')
$health = [Threading.EventWaitHandle]::new($false, [Threading.EventResetMode]::ManualReset, "Local\Kmao.Health.$token")
$worker = $null; $ready = $false
try {
    $arguments = '-NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "{0}" -ProfileDirectory "{1}" -HealthToken {2}' -f (Join-Path $repo 'dev.ps1'), $temporary, $token
    $worker = Start-Process -FilePath (Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe') -ArgumentList $arguments -WindowStyle Hidden -PassThru
    $timer = [Diagnostics.Stopwatch]::StartNew()
    while (!$health.WaitOne(100)) {
        if ($worker.HasExited -or $timer.Elapsed.TotalSeconds -ge 30) {
            $logDirectory = Join-Path $temporary '.kmao-bot/logs'
            $diagnostic = if (Test-Path -LiteralPath $logDirectory) {
                (Get-ChildItem -LiteralPath $logDirectory -Filter '*.log' | ForEach-Object { Get-Content -LiteralPath $_.FullName -Tail 30 -Encoding UTF8 }) -join "`n"
            } else { 'No startup log was created.' }
            throw "Tray bot did not report readiness within the updater startup timeout.`n$diagnostic"
        }
    }
    $ready = $true
    $stop = [Threading.EventWaitHandle]::OpenExisting('Local\Kmao.Stop.bot')
    try { $stop.Set() | Out-Null } finally { $stop.Dispose() }
    if (!$worker.WaitForExit(20000)) { throw 'Bot did not close within updater shutdown timeout.' }
    if ($worker.ExitCode -ne 0) { throw "Desktop bot failed with exit code $($worker.ExitCode)." }
    $logs = @(Get-ChildItem -LiteralPath (Join-Path $temporary '.kmao-bot/logs') -Filter '*.log')
    $text = ($logs | ForEach-Object { [IO.File]::ReadAllText($_.FullName) }) -join "`n"
    if ($text -notmatch 'Owned Notepad discarded without saving' -or $text -notmatch 'Bot stopped') { throw 'Desktop shutdown did not log Notepad disposal and bot cleanup.' }
    Write-Host 'PASS: real bot starts tray/Notepad and exits cooperatively within updater timeouts without saving.'
}
finally {
    if ($null -ne $worker) {
        if (!$worker.HasExited) {
            if ($ready) {
                $stop = [Threading.EventWaitHandle]::OpenExisting('Local\Kmao.Stop.bot')
                try { $stop.Set() | Out-Null } finally { $stop.Dispose() }
                $worker.WaitForExit(10000) | Out-Null
            }
            if (!$worker.HasExited) { $worker.Kill(); $worker.WaitForExit() } # Only this test's process.
        }
        $worker.Dispose()
    }
    $health.Dispose()
    Remove-Item -LiteralPath $temporary -Recurse -Force
}
