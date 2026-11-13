# Full native bot lifecycle with temporary data and a private event/mutex namespace.
# Other running KMAO sessions and their stop events are never touched.
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT' -or $PSVersionTable.PSEdition -ne 'Desktop') { throw 'Interactive Windows PowerShell 5.1 is required.' }
$repo = [IO.Path]::GetFullPath((Resolve-Path (Join-Path $PSScriptRoot '..')).ProviderPath)
. (Join-Path $repo 'scripts/Kmao.Authenticode.ps1')
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('kmao-native-desktop-' + [Guid]::NewGuid().ToString('N'))
$payload = Join-Path $temporary 'payload'
$profile = Join-Path $temporary 'profile'
$prefix = 'Local\Kmao.HostTest.' + [Guid]::NewGuid().ToString('N') + '.'
$token = [Guid]::NewGuid().ToString('N')
$health = [Threading.EventWaitHandle]::new($false, [Threading.EventResetMode]::ManualReset, ($prefix + 'Health.' + $token))
$worker = $null
try {
    & (Join-Path $repo 'Export-Kmao.ps1') -Destination $payload -SkipArchive
    # Rewrite only this temporary copy. Assert the real production namespace is
    # absent before launching; the production installation is never modified.
    $common = Join-Path $payload 'lib/Kmao.Common.ps1'
    $source = [IO.File]::ReadAllText($common).Replace('Local\Kmao.', $prefix)
    if ($source.Contains('Local\Kmao.Component.') -or $source.Contains('Local\Kmao.Stop.') -or !$source.Contains($prefix + 'Stop.')) { throw 'Session namespace isolation failed.' }
    [IO.File]::WriteAllText($common, $source)
    New-KmaoCompiledRuntime $payload
    New-KmaoBotHost $payload
    $configDirectory = Join-Path $profile '.kmao-bot/config'
    New-Item -ItemType Directory $configDirectory -Force | Out-Null
    $config = [IO.File]::ReadAllText((Join-Path $payload 'config/bot.conf.example')).Replace('IDLE_TIME_THRESHOLD=60', 'IDLE_TIME_THRESHOLD=86400')
    [IO.File]::WriteAllText((Join-Path $configDirectory 'bot.conf'), $config)
    $arguments = '-ProfileDirectory "{0}" -HealthToken {1}' -f $profile, $token
    $worker = Start-Process (Join-Path $payload 'Kmao.Bot.exe') -ArgumentList $arguments -PassThru
    $timer = [Diagnostics.Stopwatch]::StartNew()
    while (!$health.WaitOne(100)) {
        if ($worker.HasExited -or $timer.Elapsed.TotalSeconds -ge 30) {
            $diagnostic = @(Get-ChildItem -LiteralPath (Join-Path $profile '.kmao-bot/logs') -Filter '*.log' -ErrorAction SilentlyContinue | ForEach-Object { Get-Content -LiteralPath $_.FullName -Tail 20 }) -join "`n"
            throw "Native bot did not become ready within 30 seconds.`n$diagnostic"
        }
    }
    if ($worker.ProcessName -ne 'Kmao.Bot') { throw 'The real bot is not running in its own executable.' }
    $stop = [Threading.EventWaitHandle]::OpenExisting($prefix + 'Stop.bot')
    try { $stop.Set() | Out-Null } finally { $stop.Dispose() }
    if (!$worker.WaitForExit(20000) -or $worker.ExitCode -ne 0) { throw 'Native bot did not exit cleanly within 20 seconds.' }
    $logs = @(Get-ChildItem -LiteralPath (Join-Path $profile '.kmao-bot/logs') -Filter 'bot-*.log' | ForEach-Object { Get-Content -LiteralPath $_.FullName }) -join "`n"
    if ($logs -notmatch 'Owned Notepad discarded without saving' -or $logs -notmatch 'Bot stopped') { throw 'Native bot did not clean up its Notepad/session.' }
    Write-Host 'PASS: real native bot starts tray/Notepad, signals readiness and closes its own document within updater timeouts, with private session events.'
}
finally {
    if ($null -ne $worker) {
        if (!$worker.HasExited) {
            try { $stop = [Threading.EventWaitHandle]::OpenExisting($prefix + 'Stop.bot'); try { $stop.Set() | Out-Null } finally { $stop.Dispose() } } catch [Threading.WaitHandleCannotBeOpenedException] { }
            if (!$worker.WaitForExit(20000)) { $worker.Kill(); $worker.WaitForExit() }
        }
        $worker.Dispose()
    }
    $health.Dispose()
    if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Recurse -Force }
}
