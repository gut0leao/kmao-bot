# KMAO automation. All writable files live in the current user's profile.
$ErrorActionPreference = 'Stop'
# Validate the package before loading shared code; diagnostics are unavailable at this stage.
$missingFiles = @(@('lib/Kmao.Common.ps1', 'lib/Kmao.Windows.cs', 'config/bot.conf.example', 'phrases.txt') | Where-Object {
    !(Test-Path -LiteralPath (Join-Path $PSScriptRoot $_) -PathType Leaf)
})
if ($missingFiles.Count -gt 0) {
    Write-Error ("Incomplete KMAO package. Missing: {0}. Copy the entire portable package, including lib and config. No application log was created." -f ($missingFiles -join ', ')) -ErrorAction Continue
    exit 1
}
. (Join-Path $PSScriptRoot 'lib/Kmao.Common.ps1')

function Get-BotWindow { return [Kmao.WindowsInput]::ForegroundWindow }

function Assert-CycleActive {
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

function Invoke-BotCycle {
    $script:cycleGeneration = $monitor.Generation
    $script:targetWindow = Get-BotWindow
    if ($script:targetWindow -eq [IntPtr]::Zero) { throw [OperationCanceledException]::new('No foreground window.') }
    # Recheck after taking the generation snapshot: activity between the outer idle check
    # and this point must not become the baseline of a new cycle.
    if ($monitor.IdleSeconds -lt $settings.IDLE_TIME_THRESHOLD) {
        throw [OperationCanceledException]::new('User activity detected before cycle startup.')
    }
    Wait-Cycle ((Get-Delay MIN_INTERVAL MAX_INTERVAL) * 1000)
    $clicks = Get-Delay MIN_CLICKS MAX_CLICKS
    for ($i = 0; $i -lt $clicks; $i++) {
        Assert-CycleActive
        $x = Get-Random -Minimum $rectLeft -Maximum ($rectLeft + $settings.RECT_WIDTH)
        $y = Get-Random -Minimum $rectTop -Maximum ($rectTop + $settings.RECT_HEIGHT)
        if (!$monitor.Move($cycleGeneration, $x, $y)) { throw [OperationCanceledException]::new('User activity detected.') }
        Wait-Cycle (Get-Delay CURSOR_MIN_DELAY CURSOR_MAX_DELAY)
        if (!$monitor.Click($cycleGeneration, $targetWindow)) { throw [OperationCanceledException]::new('User activity or window change detected.') }
        # A bot click may legitimately activate a new window. Physical input is still
        # tracked independently; subsequent typing is bound to this foreground window.
        $script:targetWindow = Get-BotWindow
        if ($targetWindow -eq [IntPtr]::Zero) { throw [OperationCanceledException]::new('No foreground window after click.') }
        Wait-Cycle (Get-Delay MULTI_CLICK_MIN_DELAY MULTI_CLICK_MAX_DELAY)
    }
    if ((Get-Random -Minimum 0 -Maximum 100) -lt $settings.TYPING_CHANCE) {
        Wait-Cycle (Get-Delay PRE_TYPING_MIN_DELAY PRE_TYPING_MAX_DELAY)
        $phrase = $phrases | Get-Random
        foreach ($character in $phrase.ToCharArray()) {
            Assert-CycleActive
            if (!$monitor.TypeCharacter($cycleGeneration, $targetWindow, $character)) {
                throw [OperationCanceledException]::new('User activity or window change detected.')
            }
            $delay = Get-Delay MIN_CHAR_DELAY MAX_CHAR_DELAY
            if ((Get-Random -Minimum 0 -Maximum 100) -lt $settings.HESITATION_CHANCE) {
                $delay += Get-Delay MIN_HESITATION MAX_HESITATION
            }
            if ($character -eq ' ') { $delay = Get-Delay SPACE_MIN_DELAY SPACE_MAX_DELAY }
            if ($character -match '[.,;:!?()\-"]') { $delay += Get-Delay PUNCT_MIN_DELAY PUNCT_MAX_DELAY }
            Wait-Cycle $delay
        }
        Wait-Cycle (Get-Delay PRE_ENTER_MIN_DELAY PRE_ENTER_MAX_DELAY)
        if (!$monitor.Enter($cycleGeneration, $targetWindow)) { throw [OperationCanceledException]::new('User activity or window change detected before Enter.') }
        # Operational logs intentionally do not contain typed phrases.
        Write-KmaoLog INFO 'Typing completed.'
    }
    Wait-Cycle (Get-Delay FINAL_MIN_DELAY FINAL_MAX_DELAY)
}

$monitor = $null
$failed = $false
try {
    Initialize-Kmao bot
    Import-KmaoWindows
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
    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    if ($settings.RECT_WIDTH -gt $bounds.Width -or $settings.RECT_HEIGHT -gt $bounds.Height) {
        throw 'Click rectangle must fit inside the primary screen.'
    }
    $rectLeft = $bounds.Left + [int](($bounds.Width - $settings.RECT_WIDTH) / 2)
    $rectTop = $bounds.Top + [int](($bounds.Height - $settings.RECT_HEIGHT) / 2)
    $monitor = New-KmaoInput -RecordEvents $false -SamplingMilliseconds 200
    Write-KmaoLog INFO 'Bot started. Press Ctrl+C to stop.'
    while ($true) {
        if ($monitor.IdleSeconds -lt $settings.IDLE_TIME_THRESHOLD -or [Kmao.WindowsInput]::ForegroundWindow -eq [IntPtr]::Zero) {
            Start-Sleep -Milliseconds 100
            continue
        }
        try { Invoke-BotCycle }
        catch [OperationCanceledException] { Write-KmaoLog INFO "Cycle cancelled: $($_.Exception.Message)" }
    }
}
catch {
    $failed = $true
    if ($script:KmaoLogFile) { Write-KmaoLog ERROR $_.Exception.ToString() }
    Write-Error -ErrorRecord $_ -ErrorAction Continue
}
finally {
    if ($null -ne $monitor) {
        try { $monitor.Dispose() }
        catch {
            $failed = $true
            Write-KmaoLog ERROR $_.Exception.ToString()
            Write-Error -ErrorRecord $_ -ErrorAction Continue
        }
    }
    if ($script:KmaoLogFile) { Write-KmaoLog INFO 'Bot stopped.' }
}
if ($failed) { exit 1 }
