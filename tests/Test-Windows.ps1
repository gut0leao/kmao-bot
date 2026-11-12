# Native integration smoke test. Moves the cursor by one pixel; does not click or type.
# Run on an interactive Windows desktop, leaving the mouse and keyboard untouched.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../lib/Kmao.Common.ps1')
Import-KmaoWindows
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class KmaoTestMouse {
    [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
}
'@
$inputMonitor = $null
try {
    $inputMonitor = [Kmao.WindowsInput]::new($true, 1)
    $point = [System.Windows.Forms.Cursor]::Position
    $generation = $inputMonitor.Generation
    if (!$inputMonitor.Move($generation, $point.X, $point.Y)) { throw 'Unexpected cancellation during own input.' }
    Start-Sleep -Milliseconds 100
    if ($inputMonitor.Generation -ne $generation) { throw 'Own marked input incorrectly detected as user activity.' }
    $ownEvents = @($inputMonitor.Drain())
    if ($ownEvents.Count -eq 0) { throw 'No own-input events captured; verify message pump/hook installation.' }

    # An unmarked injected event models activity from outside this bot, including accessibility input.
    [KmaoTestMouse]::mouse_event(1, 1, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 100
    if ($inputMonitor.Generation -eq $generation) { throw 'External input did not cancel the cycle.' }
    if ($inputMonitor.IsCurrent($generation, [IntPtr]::Zero)) { throw 'Stale cycle is still allowed to send input.' }
    if ($inputMonitor.Enter($generation, [IntPtr]::Zero)) { throw 'Enter was not cancelled.' }
    if ($inputMonitor.IdleSeconds -gt 2) { throw 'Idle timer was not reset by external input.' }
    $inputMonitor.Dispose()
    $remaining = @($inputMonitor.Drain())
    if ($remaining.Count -eq 0) { throw 'Queued events were not retained for final drain after disposal.' }
    $inputMonitor.Dispose() # Idempotent cleanup.
    Write-Host 'PASS: Windows message pump, event capture, own/external distinction, cancellation and cleanup.'
} finally {
    if ($null -ne $inputMonitor) { $inputMonitor.Dispose() }
}
