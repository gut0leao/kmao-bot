param(
    [string]$HealthToken,
    [string]$ProfileDirectory = [Environment]::GetFolderPath('UserProfile')
)
# KMAO automation. All writable files live in the current user's profile.
$ErrorActionPreference = 'Stop'
# Validate the package before loading shared code; diagnostics are unavailable at this stage.
$missingFiles = @(@('lib/Kmao.Common.ps1', 'lib/Kmao.Configuration.ps1', 'lib/Kmao.Windows.cs', 'lib/Kmao.Desktop.cs', 'lib/Kmao.Notepad.cs', 'Show-KmaoLogs.ps1', 'VERSION', 'config/application.conf.example', 'phrases.txt') | Where-Object {
    !(Test-Path -LiteralPath (Join-Path $PSScriptRoot $_) -PathType Leaf)
})
if ($missingFiles.Count -gt 0) {
    Write-Error ("Incomplete KMAO package. Missing: {0}. Copy the entire portable package, including lib and config. No application log was created." -f ($missingFiles -join ', ')) -ErrorAction Continue
    exit 1
}
. (Join-Path $PSScriptRoot 'lib/Kmao.Common.ps1')
. (Join-Path $PSScriptRoot 'lib/Kmao.Configuration.ps1')

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
    if (!$desktop.Enabled -or $desktop.ManualStopped -or $desktop.ExitRequested) { throw [OperationCanceledException]::new('Stopped from tray.') }
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

function Update-BotConfiguration {
    try {
        $newSettings = Read-KmaoAppConfig $configPath
        $script:settings = $newSettings
        $script:configurationError = $null
        return $true
    }
    catch {
        $message = $_.Exception.Message
        if ($script:configurationError -ne $message) { Write-KmaoLog ERROR "Configuration rejected; bot paused: $message" }
        $script:configurationError = $message
        $desktop.SetEnabled($false)
        return $false
    }
}

function Start-BotRunning {
    param([switch]$Explicit)
    $generation = $monitor.Generation
    if ($desktop.ManualStopped -or $desktop.ExitRequested -or (Test-KmaoStopRequested $session)) { return $false }
    # Load into a temporary table and validate ALL fields before replacing settings.
    if (!(Update-BotConfiguration)) { return $false }
    if (!$Explicit -and $monitor.IdleSeconds -lt $settings.IDLE_TIME_THRESHOLD) { return $false }
    if (!$notepad.IsOpen -or $notepad.OwnershipLost) {
        if (!$Explicit) { return $false }
        $notepad.Dispose()
        $script:notepad = [Kmao.OwnedNotepad]::new()
    }
    $notepad.MaximizeAndActivate()
    if ($desktop.ManualStopped -or $desktop.ExitRequested -or (Test-KmaoStopRequested $session) -or $monitor.Generation -ne $generation -or !$notepad.IsForeground) { return $false }
    $script:observedGeneration = $generation
    $desktop.SetEnabled($true)
    Write-KmaoLog INFO 'Configuration reloaded. Owned Notepad activated; Running.'
    return $desktop.Enabled
}

function Update-BotActivityState {
    $generation = $monitor.Generation
    if ($generation -ne $script:observedGeneration) {
        $script:observedGeneration = $generation
        if ($desktop.Enabled) { Write-KmaoLog INFO 'User activity detected; automatically paused.' }
        $desktop.SetEnabled($false)
        return $false
    }
    if ($desktop.ManualStopped -or !$notepad.IsOpen -or $notepad.OwnershipLost) {
        $desktop.SetEnabled($false)
        return $false
    }
    if ($desktop.Enabled -and !$notepad.IsForeground) {
        $desktop.SetEnabled($false)
        Write-KmaoLog INFO 'Owned Notepad lost focus; automatically paused.'
    }
    if (!$desktop.Enabled) { return Start-BotRunning }
    return $true
}

function Invoke-StartupTyping {
    $script:cycleGeneration = $monitor.Generation
    $script:targetWindow = Get-BotWindow
    while (!$notepad.StartupComplete) {
        Assert-CycleActive
        $notepad.TypeStartupCharacter()
        # Startup remains responsive and stays within the updater readiness budget.
        Wait-Cycle (Get-Delay STARTUP_MIN_CHAR_DELAY STARTUP_MAX_CHAR_DELAY)
    }
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
    $configPath = Initialize-KmaoAppConfig $KmaoRoot
    $script:settings = Get-KmaoConfigDefaults
    $script:configurationError = $null
    $phrasesPath = Join-Path $KmaoRoot 'phrases.txt'
    Initialize-KmaoFile $phrasesPath (Join-Path $PSScriptRoot 'phrases.txt')
    $phrases = @(Get-Content -LiteralPath $phrasesPath -Encoding UTF8 | Where-Object { ![string]::IsNullOrWhiteSpace($_) })
    if ($phrases.Count -eq 0) { throw "Phrase file is empty: $phrasesPath" }
    $monitor = New-KmaoInput -RecordEvents $false -SamplingMilliseconds 200
    $script:observedGeneration = $monitor.Generation
    $notepad = [Kmao.OwnedNotepad]::new()
    Write-KmaoLog INFO "Owned Notepad window: $($notepad.Window.ToInt64())"
    $version = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'VERSION')).Trim()
    $desktop = [Kmao.TrayController]::new($KmaoLogFile, (Join-Path $PSScriptRoot 'Show-KmaoLogs.ps1'), $version, $configPath)
    Set-KmaoReady $HealthToken
    Write-KmaoLog INFO "KMAO $version started in tray. Automation is restricted to its own Notepad."
    $consoleHidden = [Kmao.TrayController]::HideOwnedConsole()
    $documentWarningShown = $false
    if ($monitor.Generation -eq $script:observedGeneration) { Start-BotRunning -Explicit | Out-Null }
    while (!(Test-KmaoStopRequested $session) -and !$desktop.ExitRequested) {
        $desktop.CheckHealth()
        foreach ($notice in $desktop.DrainNotices()) {
            Write-KmaoLog INFO $notice
            if ($notice -eq 'Run selected.') {
                Start-BotRunning -Explicit | Out-Null
                $documentWarningShown = $false
            }
        }
        if (!$notepad.IsOpen -or $notepad.OwnershipLost) {
            $desktop.SetEnabled($false)
            if (!$documentWarningShown) {
                Write-KmaoLog WARN 'Owned Notepad was closed or its document was replaced. Use Run to create a new one.'
                $documentWarningShown = $true
            }
        }
        if (!(Update-BotActivityState)) {
            Start-Sleep -Milliseconds 100
            continue
        }
        try {
            if (!$notepad.StartupComplete) { Invoke-StartupTyping }
            elseif ($monitor.IdleSeconds -ge $settings.IDLE_TIME_THRESHOLD) { Invoke-BotCycle }
            else { Start-Sleep -Milliseconds 100 }
        }
        catch [OperationCanceledException] {
            $desktop.SetEnabled($false)
            Write-KmaoLog INFO "Cycle cancelled: $($_.Exception.Message)"
        }
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
