# UI compilation and tray lifecycle only: does not open Notepad or send desktop input.
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT' -or $PSVersionTable.PSEdition -ne 'Desktop') { Write-Host 'SKIP: desktop component tests require Windows PowerShell 5.1.'; return }
$repo = [IO.Path]::GetFullPath((Resolve-Path (Join-Path $PSScriptRoot '..')).ProviderPath)
. (Join-Path $repo 'lib/Kmao.Common.ps1')
Import-KmaoDesktop
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('kmao-desktop-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $temporary | Out-Null
$tray = $null; $running = $null; $paused = $null; $viewer = $null
try {
    $running = [Kmao.TrayController]::CreateRobotIcon([Drawing.Color]::FromArgb(36, 167, 82))
    $paused = [Kmao.TrayController]::CreateRobotIcon([Drawing.Color]::FromArgb(135, 140, 148))
    if ($running.Width -ne 32 -or $paused.Width -ne 32) { throw 'Invalid robot icon size.' }
    $greenBitmap = $running.ToBitmap(); $grayBitmap = $paused.ToBitmap()
    try {
        $green = $greenBitmap.GetPixel(7, 10); $gray = $grayBitmap.GetPixel(7, 10)
        if ($green.G -le $green.R -or [Math]::Abs($gray.G - $gray.R) -gt 15) { throw 'Running/paused icon colors are incorrect.' }
    } finally { $greenBitmap.Dispose(); $grayBitmap.Dispose() }
    $log = Join-Path $temporary 'bot.log'
    Set-Content -LiteralPath $log -Value 'test log' -Encoding UTF8
    if (![Environment]::UserInteractive) { Write-Host 'PASS: desktop compilation and icons (tray interaction skipped in noninteractive session).'; return }
    $tray = [Kmao.TrayController]::new($log, (Join-Path $repo 'Show-KmaoLogs.ps1'), 'test')
    if ($tray.Enabled) { throw 'Tray must wait for configuration validation before Running.' }
    $tray.RequestRun()
    if ($tray.Enabled -or $tray.ManualStopped) { throw 'Run must request backend validation without turning green.' }
    $tray.SetEnabled($false)
    if ($tray.Enabled) { throw 'Stop did not pause the tray controller.' }
    $tray.SetEnabled($true)
    if (!$tray.Enabled) { throw 'Run did not resume the tray controller.' }
    $tray.RequestStop()
    if ($tray.Enabled -or !$tray.ManualStopped) { throw 'Manual Stop did not pause.' }
    $tray.RequestRun()
    if ($tray.Enabled -or $tray.ManualStopped) { throw 'Manual Run bypassed configuration validation.' }
    $tray.SetEnabled($true)
    $tray.RequestExit()
    if (!$tray.ExitRequested -or $tray.Enabled) { throw 'Exit did not stop automation.' }
    $tray.Dispose(); $tray.Dispose()
    $output = Join-Path $temporary 'follow.txt'
    $arguments = '-NoLogo -NoProfile -ExecutionPolicy Bypass -File "{0}" -LogPath "{1}"' -f (Join-Path $repo 'Show-KmaoLogs.ps1'), $log
    $viewer = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $arguments -WindowStyle Hidden -RedirectStandardOutput $output -PassThru
    $marker = 'live-follow-' + [Guid]::NewGuid().ToString('N')
    Start-Sleep -Milliseconds 300
    Add-Content -LiteralPath $log -Value $marker -Encoding UTF8
    $timer = [Diagnostics.Stopwatch]::StartNew()
    do {
        Start-Sleep -Milliseconds 100
        $followed = ''
        if (Test-Path -LiteralPath $output) {
            $stream = [IO.File]::Open($output, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
            $reader = [IO.StreamReader]::new($stream)
            try { $followed = $reader.ReadToEnd() } finally { $reader.Dispose() }
        }
    } while (!$followed.Contains($marker) -and !$viewer.HasExited -and $timer.Elapsed.TotalSeconds -lt 8)
    if (!$followed.Contains($marker)) { throw 'Logs viewer did not follow appended log records.' }
    Write-Host 'PASS: desktop compilation, icons, tray run/stop/exit, disposal and live log following.'
}
finally {
    if ($null -ne $viewer) { if (!$viewer.HasExited) { $viewer.Kill(); $viewer.WaitForExit() }; $viewer.Dispose() }
    if ($null -ne $tray) { $tray.Dispose() }
    if ($null -ne $running) { $running.Dispose() }
    if ($null -ne $paused) { $paused.Dispose() }
    Remove-Item -LiteralPath $temporary -Recurse -Force
}
