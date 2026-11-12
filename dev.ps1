param(
    [string]$HealthToken,
    [string]$ProfileDirectory = [Environment]::GetFolderPath('UserProfile')
)
# KMAO automation. All writable files live in the current user's profile.
$ErrorActionPreference = 'Stop'
# Validate the package before loading shared code; diagnostics are unavailable at this stage.
$missingFiles = @(@('lib/Kmao.Common.ps1', 'lib/Kmao.Windows.cs', 'lib/Kmao.Desktop.cs', 'lib/Kmao.Notepad.cs', 'Show-KmaoLogs.ps1', 'VERSION', 'config/bot.conf.example', 'phrases.txt') | Where-Object {
    !(Test-Path -LiteralPath (Join-Path $PSScriptRoot $_) -PathType Leaf)
})
if ($missingFiles.Count -gt 0) {
    Write-Error ("Incomplete KMAO package. Missing: {0}. Copy the entire portable package, including lib and config. No application log was created." -f ($missingFiles -join ', ')) -ErrorAction Continue
    exit 1
}
. (Join-Path $PSScriptRoot 'lib/Kmao.Common.ps1')

function Get-BotWindow { return $notepad.Window }

function Send-BotText {
    param([string]$Text)
    Assert-CycleActive
    $notepad.AppendText($Text)
}

function Send-BotClick {
    param([int]$X, [int]$Y)
    Assert-CycleActive
    $notepad.ClickEditor($X, $Y)
}

function Assert-CycleActive {
    if (!$desktop.Enabled -or $desktop.ExitRequested) { throw [OperationCanceledException]::new('Stopped from tray.') }
    if (!$notepad.IsForeground) { throw [OperationCanceledException]::new('Owned Notepad document is not active.') }
    if (Test-KmaoStopRequested $session) { throw [OperationCanceledException]::new('Update requested a clean shutdown.') }
    if (!$script:monitor.IsCurrent($script:cycleGeneration, $script:targetWindow)) {
        throw [OperationCanceledException]::new('User activity or foreground window change detected.')
    }
}

function Wait-Cycle {
    param([int]$Milliseconds)
    $timer = [Diagnostics.Stopwatch]::StartNew()
    do {
        Assert-CycleActive
        $remaining = $Milliseconds - $timer.ElapsedMilliseconds
        if ($remaining -gt 0) { Start-Sleep -Milliseconds ([int][Math]::Min(25, $remaining)) }
    } while ($timer.ElapsedMilliseconds -lt $Milliseconds)
    Assert-CycleActive
}

function Get-Delay {
    param([string]$Minimum, [string]$Maximum)
    return Get-Random -Minimum $settings[$Minimum] -Maximum $settings[$Maximum]
}

function Update-BotRectangle {
    $bounds = $notepad.EditorBounds
    $script:rectWidth = [Math]::Min($settings.RECT_WIDTH, $bounds[2])
    $script:rectHeight = [Math]::Min($settings.RECT_HEIGHT, $bounds[3])
    if ($rectWidth -lt 1 -or $rectHeight -lt 1) { throw [OperationCanceledException]::new('Owned editor has no clickable area.') }
    $script:rectLeft = $bounds[0] + [int](($bounds[2] - $rectWidth) / 2)
    $script:rectTop = $bounds[1] + [int](($bounds[3] - $rectHeight) / 2)
}

function Invoke-BotCycle {
    $script:cycleGeneration = $monitor.Generation
    $script:targetWindow = Get-BotWindow
    if ($script:targetWindow -eq [IntPtr]::Zero) { throw [OperationCanceledException]::new('No foreground window.') }
    # Recheck after taking the generation snapshot: activity between the outer idle check
    # and this point must not become the baseline of a new cycle.
    if ($monitor.IdleSeconds -lt $settings.IDLE_TIME_THRESHOLD) {
        throw [OperationCanceledException]::new('User activity detected before cycle startup.')
    }
    $interval = Get-Delay MIN_INTERVAL MAX_INTERVAL
    Write-KmaoLog INFO "Next automatic cycle in $interval seconds."
    Wait-Cycle ($interval * 1000)
    $clicks = Get-Delay MIN_CLICKS MAX_CLICKS
    for ($i = 0; $i -lt $clicks; $i++) {
        Assert-CycleActive
        Update-BotRectangle
        $x = Get-Random -Minimum $rectLeft -Maximum ($rectLeft + $rectWidth)
        $y = Get-Random -Minimum $rectTop -Maximum ($rectTop + $rectHeight)
        if (!$notepad.IsEditorPoint($x, $y)) { throw [OperationCanceledException]::new('Owned editor is covered or inactive.') }
        if (!$monitor.Move($cycleGeneration, $x, $y)) { throw [OperationCanceledException]::new('User activity detected.') }
        Wait-Cycle (Get-Delay CURSOR_MIN_DELAY CURSOR_MAX_DELAY)
        if (!$notepad.IsEditorPoint($x, $y)) { throw [OperationCanceledException]::new('Owned editor is covered or inactive.') }
        if (!$notepad.IsCursorOverEditor()) { throw [OperationCanceledException]::new('Cursor left the owned editor.') }
        Send-BotClick $x $y
        # The target never follows arbitrary foreground windows.
        Assert-CycleActive
        Wait-Cycle (Get-Delay MULTI_CLICK_MIN_DELAY MULTI_CLICK_MAX_DELAY)
    }
    if ((Get-Random -Minimum 0 -Maximum 100) -lt $settings.TYPING_CHANCE) {
        Wait-Cycle (Get-Delay PRE_TYPING_MIN_DELAY PRE_TYPING_MAX_DELAY)
        $phrase = $phrases | Get-Random
        $characters = [Globalization.StringInfo]::GetTextElementEnumerator($phrase)
        while ($characters.MoveNext()) {
            $character = $characters.GetTextElement()
            Assert-CycleActive
            Send-BotText $character.ToString()
            $delay = Get-Delay MIN_CHAR_DELAY MAX_CHAR_DELAY
            if ((Get-Random -Minimum 0 -Maximum 100) -lt $settings.HESITATION_CHANCE) {
                $delay += Get-Delay MIN_HESITATION MAX_HESITATION
            }
            if ($character -eq ' ') { $delay = Get-Delay SPACE_MIN_DELAY SPACE_MAX_DELAY }
            if ($character -match '[.,;:!?()\-"]') { $delay += Get-Delay PUNCT_MIN_DELAY PUNCT_MAX_DELAY }
            Wait-Cycle $delay
        }
        Wait-Cycle (Get-Delay PRE_ENTER_MIN_DELAY PRE_ENTER_MAX_DELAY)
        Send-BotText "`r`n"
        # Operational logs intentionally do not contain typed phrases.
        Write-KmaoLog INFO 'Typing completed.'
    }
    Wait-Cycle (Get-Delay FINAL_MIN_DELAY FINAL_MAX_DELAY)
}

$monitor = $null
$desktop = $null
$notepad = $null
$consoleHidden = $false
$session = $null
$failed = $false
$failureMessage = $null
try {
    Initialize-Kmao bot -ProfileDirectory $ProfileDirectory
    Import-KmaoDesktop
    $session = Enter-KmaoSession -Component bot -HealthToken $HealthToken
    $configPath = Join-Path $KmaoRoot 'config/bot.conf'
    Initialize-KmaoFile $configPath (Join-Path $PSScriptRoot 'config/bot.conf.example')
    $defaults = @{
        MIN_INTERVAL = 30
        MAX_INTERVAL = 240
        RECT_WIDTH = 400
        RECT_HEIGHT = 200
        MIN_CLICKS = 1
        MAX_CLICKS = 4
        TYPING_CHANCE = 70
        IDLE_TIME_THRESHOLD = 60
        MIN_CHAR_DELAY = 40
        MAX_CHAR_DELAY = 200
        HESITATION_CHANCE = 8
        MIN_HESITATION = 300
        MAX_HESITATION = 800
        SPACE_MIN_DELAY = 30
        SPACE_MAX_DELAY = 120
        PUNCT_MIN_DELAY = 50
        PUNCT_MAX_DELAY = 150
        CURSOR_MIN_DELAY = 80
        CURSOR_MAX_DELAY = 200
        MULTI_CLICK_MIN_DELAY = 200
        MULTI_CLICK_MAX_DELAY = 500
        PRE_TYPING_MIN_DELAY = 500
        PRE_TYPING_MAX_DELAY = 1500
        PRE_ENTER_MIN_DELAY = 200
        PRE_ENTER_MAX_DELAY = 600
        FINAL_MIN_DELAY = 200
        FINAL_MAX_DELAY = 800
    }
    $ranges = @{
        MIN_INTERVAL = @(1, 86400)
        MAX_INTERVAL = @(1, 86400)
        RECT_WIDTH = @(1, 32768)
        RECT_HEIGHT = @(1, 32768)
        MIN_CLICKS = @(1, 100)
        MAX_CLICKS = @(1, 100)
        TYPING_CHANCE = @(0, 100)
        IDLE_TIME_THRESHOLD = @(1, 86400)
        MIN_CHAR_DELAY = @(0, 60000)
        MAX_CHAR_DELAY = @(0, 60000)
        HESITATION_CHANCE = @(0, 100)
        MIN_HESITATION = @(0, 60000)
        MAX_HESITATION = @(0, 60000)
        SPACE_MIN_DELAY = @(0, 60000)
        SPACE_MAX_DELAY = @(0, 60000)
        PUNCT_MIN_DELAY = @(0, 60000)
        PUNCT_MAX_DELAY = @(0, 60000)
        CURSOR_MIN_DELAY = @(0, 60000)
        CURSOR_MAX_DELAY = @(0, 60000)
        MULTI_CLICK_MIN_DELAY = @(0, 60000)
        MULTI_CLICK_MAX_DELAY = @(0, 60000)
        PRE_TYPING_MIN_DELAY = @(0, 60000)
        PRE_TYPING_MAX_DELAY = @(0, 60000)
        PRE_ENTER_MIN_DELAY = @(0, 60000)
        PRE_ENTER_MAX_DELAY = @(0, 60000)
        FINAL_MIN_DELAY = @(0, 60000)
        FINAL_MAX_DELAY = @(0, 60000)
    }
    $settings = Read-KmaoConfig $configPath $defaults $ranges
    foreach ($pair in @(
        @('MIN_INTERVAL', 'MAX_INTERVAL'), @('MIN_CLICKS', 'MAX_CLICKS'),
        @('MIN_CHAR_DELAY', 'MAX_CHAR_DELAY'), @('MIN_HESITATION', 'MAX_HESITATION'),
        @('SPACE_MIN_DELAY', 'SPACE_MAX_DELAY'), @('PUNCT_MIN_DELAY', 'PUNCT_MAX_DELAY'),
        @('CURSOR_MIN_DELAY', 'CURSOR_MAX_DELAY'),
        @('MULTI_CLICK_MIN_DELAY', 'MULTI_CLICK_MAX_DELAY'), @('PRE_TYPING_MIN_DELAY', 'PRE_TYPING_MAX_DELAY'),
        @('PRE_ENTER_MIN_DELAY', 'PRE_ENTER_MAX_DELAY'), @('FINAL_MIN_DELAY', 'FINAL_MAX_DELAY')
    )) {
        if ($settings[$pair[0]] -ge $settings[$pair[1]]) { throw "$($pair[0]) must be less than $($pair[1])." }
    }
    $phrasesPath = Join-Path $KmaoRoot 'phrases.txt'
    Initialize-KmaoFile $phrasesPath (Join-Path $PSScriptRoot 'phrases.txt')
    $phrases = @(Get-Content -LiteralPath $phrasesPath -Encoding UTF8 | Where-Object { ![string]::IsNullOrWhiteSpace($_) })
    if ($phrases.Count -eq 0) { throw "Phrase file is empty: $phrasesPath" }
    $monitor = New-KmaoInput -RecordEvents $false -SamplingMilliseconds 200
    $notepad = [Kmao.OwnedNotepad]::new()
    Write-KmaoLog INFO "Owned Notepad window: $($notepad.Window.ToInt64())"
    $version = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'VERSION')).Trim()
    $desktop = [Kmao.TrayController]::new($KmaoLogFile, (Join-Path $PSScriptRoot 'Show-KmaoLogs.ps1'), $version)
    Set-KmaoReady $HealthToken
    Write-KmaoLog INFO "KMAO $version started in tray. Automation is restricted to its own Notepad."
    $consoleHidden = [Kmao.TrayController]::HideOwnedConsole()
    $lastWaitReason = ''
    while (!(Test-KmaoStopRequested $session) -and !$desktop.ExitRequested) {
        $desktop.CheckHealth()
        foreach ($notice in $desktop.DrainNotices()) {
            Write-KmaoLog INFO $notice
            if ($notice -eq 'Run selected.') {
                if (!$notepad.IsOpen -or $notepad.OwnershipLost) { $notepad.Dispose(); $notepad = [Kmao.OwnedNotepad]::new() }
                $notepad.MaximizeAndActivate()
            }
        }
        if (!$desktop.Enabled) {
            if ($lastWaitReason -ne 'stopped') { Write-KmaoLog INFO 'Paused. Select Run in the tray menu to resume.'; $lastWaitReason = 'stopped' }
            Start-Sleep -Milliseconds 100
            continue
        }
        if (!$notepad.IsOpen -or $notepad.OwnershipLost) {
            $desktop.SetEnabled($false)
            Write-KmaoLog WARN 'Owned Notepad was closed or its document was replaced. Use Run to create a new one.'
            continue
        }
        if (!$notepad.IsForeground) {
            if ($lastWaitReason -ne 'focus') { Write-KmaoLog INFO 'Waiting for the owned Notepad document to be in the foreground.'; $lastWaitReason = 'focus' }
            Start-Sleep -Milliseconds 100
            continue
        }
        if ($monitor.IdleSeconds -lt $settings.IDLE_TIME_THRESHOLD) {
            if ($lastWaitReason -ne 'idle') { Write-KmaoLog INFO "Waiting for $($settings.IDLE_TIME_THRESHOLD) seconds of user inactivity."; $lastWaitReason = 'idle' }
            Start-Sleep -Milliseconds 100
            continue
        }
        $lastWaitReason = 'cycle'
        try { Invoke-BotCycle }
        catch [OperationCanceledException] { Write-KmaoLog INFO "Cycle cancelled: $($_.Exception.Message)" }
    }
    $desktop.CheckHealth()
    if (Test-KmaoStopRequested $session) { Write-KmaoLog INFO 'Shutdown requested by the updater.' }
    else { Write-KmaoLog INFO 'Exit requested from the tray.' }
}
catch {
    $failed = $true
    if ($consoleHidden) { [Kmao.TrayController]::ShowConsole() }
    $failureMessage = $_.Exception.Message
    if ($script:KmaoLogFile) { Write-KmaoLog ERROR $_.Exception.ToString() }
    Write-Error -ErrorRecord $_ -ErrorAction Continue
}
finally {
    if ($null -ne $notepad) {
        try {
            $notepad.Dispose()
            if ($notepad.OwnershipLost) { Write-KmaoLog WARN 'Notepad content was replaced by the user; document preserved.' }
            else { Write-KmaoLog INFO 'Owned Notepad discarded without saving.' }
        }
        catch { $failed = $true; Write-KmaoLog ERROR $_.Exception.ToString() }
    }
    if ($null -ne $desktop) {
        try { $desktop.Dispose() }
        catch { $failed = $true; Write-KmaoLog ERROR $_.Exception.ToString() }
    }
    if ($null -ne $monitor) {
        try { $monitor.Dispose() }
        catch {
            $failed = $true
            Write-KmaoLog ERROR $_.Exception.ToString()
            Write-Error -ErrorRecord $_ -ErrorAction Continue
        }
    }
    Exit-KmaoSession $session
    if ($script:KmaoLogFile) { Write-KmaoLog INFO 'Bot stopped.' }
}
if ($failed) {
    if (!$HealthToken -and ('System.Windows.Forms.MessageBox' -as [type])) {
        [System.Windows.Forms.MessageBox]::Show("KMAO could not continue. $failureMessage`nSee logs in the application directory.", 'KMAO Bot', 'OK', 'Error') | Out-Null
    }
    exit 1
}
