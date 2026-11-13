# Portable regression tests; no external framework or Windows input is needed.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../lib/Kmao.Common.ps1')
function Assert-True { param([bool]$Condition, [string]$Message) if (!$Condition) { throw $Message } }
function Assert-Throws {
    param([scriptblock]$Action, [string]$Pattern)
    try { & $Action } catch {
        if ($_.Exception.ToString() -notmatch $Pattern) { throw }
        return
    }
    throw "Expected failure matching: $Pattern"
}
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('kmao-tests-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $temporary | Out-Null
try {
    $repo = [IO.Path]::GetFullPath((Resolve-Path (Join-Path $PSScriptRoot '..')).ProviderPath)
    foreach ($file in Get-ChildItem $repo -Recurse -Filter '*.ps1') {
        $tokens = $null; $errors = $null
        [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors) | Out-Null
        Assert-True (!$errors) "Syntax errors in $($file.FullName): $errors"
    }
    Add-Type -Path (Join-Path $repo 'lib/Kmao.Windows.cs')
    $inputType = [Kmao.WindowsInput].GetNestedType('INPUT', [Reflection.BindingFlags]::NonPublic)
    $size = [Runtime.InteropServices.Marshal]::SizeOf([type]$inputType)
    Assert-True ($size -eq $(if ([IntPtr]::Size -eq 8) { 40 } else { 28 })) 'Incorrect native INPUT ABI size.'

    # Paths and template creation work from an unrelated directory and preserve user edits.
    Push-Location $temporary
    try {
        Initialize-Kmao tests $temporary
        Assert-True (Test-Path (Join-Path $temporary '.kmao-bot/data')) 'Application data directory missing.'
        $configPath = Join-Path $KmaoRoot 'config/kmao.conf'
        Initialize-KmaoFile $configPath (Join-Path $repo 'config/kmao.conf.example')
        Set-Content $configPath 'MOUSE_SAMPLING_INTERVAL=500' -Encoding UTF8
        Initialize-KmaoFile $configPath (Join-Path $repo 'config/kmao.conf.example')
        Assert-True ((Get-Content $configPath) -eq 'MOUSE_SAMPLING_INTERVAL=500') 'User configuration overwritten.'
        $defaults = @{ MOUSE_SAMPLING_INTERVAL = 200; RECORDING_DURATION_MINUTES = 480 }
        $ranges = @{ MOUSE_SAMPLING_INTERVAL = @(1, 60000); RECORDING_DURATION_MINUTES = @(0, 525600) }
        $config = Read-KmaoConfig $configPath $defaults $ranges
        Assert-True ($config.MOUSE_SAMPLING_INTERVAL -eq 500 -and $config.RECORDING_DURATION_MINUTES -eq 480) 'Config/default merge failed.'
        foreach ($bad in @('MOUSE_SAMPLING_INTERVAL=-1', 'MOUSE_SAMPLING_INTERVAL=0', 'MOUSE_SAMPLING_INTERVAL=60001',
            'MOUSE_SAMPLING_INTERVAL=999999999999999', 'RECORDING_DURATION_MINUTES=525601',
            'MOUSE_SAMPLING_INTERVAL="200"', 'UNKNOWN=1', "MOUSE_SAMPLING_INTERVAL=1`nMOUSE_SAMPLING_INTERVAL=2")) {
            Set-Content $configPath $bad -Encoding UTF8
            Assert-Throws { Read-KmaoConfig $configPath $defaults $ranges } 'configuration|Configuration'
        }
        Set-Content $configPath "# comment`n MOUSE_SAMPLING_INTERVAL = 200 `nRECORDING_DURATION_MINUTES=0`n" -Encoding UTF8
        Assert-True ((Read-KmaoConfig $configPath $defaults $ranges).RECORDING_DURATION_MINUTES -eq 0) 'Unlimited duration rejected.'
        Write-KmaoLog ERROR 'diagnostic test'
        Assert-True ((Get-Content $KmaoLogFile -Raw) -match '\[ERROR\].*diagnostic test') 'Operational error log missing.'
    } finally { Pop-Location }

    $tokens = $null; $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'dev.ps1'), [ref]$tokens, [ref]$errors)
    # Load the actual functions without executing the application's entry point.
    foreach ($definition in $ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] }, $false)) {
        . ([scriptblock]::Create($definition.Extent.Text))
    }
    # Validate the shipped bot template against the production defaults, ranges and pair rules.
    foreach ($assignment in $ast.FindAll({ param($node)
        $node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -in @('$defaults', '$ranges')
    }, $true)) { . ([scriptblock]::Create($assignment.Extent.Text)) }
    $settings = Read-KmaoConfig (Join-Path $repo 'config/bot.conf.example') $defaults $ranges
    $pairRule = $ast.FindAll({ param($node)
        $node -is [Management.Automation.Language.ForEachStatementAst] -and $node.Variable.VariablePath.UserPath -eq 'pair'
    }, $true)[0].Extent.Text
    . ([scriptblock]::Create($pairRule))
    $settings.MIN_INTERVAL = $settings.MAX_INTERVAL
    Assert-Throws { . ([scriptblock]::Create($pairRule)) } 'MIN_INTERVAL must be less'

    Add-Type @'
public class FakeInputMonitor {
    public long Generation = 1;
    public double IdleSeconds = 1000;
    public int Characters, Clicks, Enters;
    public int CancelAfterCharacter, CancelAfterClick;
    public int Checks, CancelAfterCheck;
    public bool IsCurrent(long generation, System.IntPtr window) {
        Checks++;
        if (CancelAfterCheck > 0 && Checks >= CancelAfterCheck) Generation++;
        return generation == Generation;
    }
    public bool Move(long generation, int x, int y) { return generation == Generation; }
    public bool Click(long generation, System.IntPtr window) {
        if (generation != Generation) return false;
        Clicks++;
        if (CancelAfterClick > 0 && Clicks >= CancelAfterClick) Generation++;
        return true;
    }
    public bool TypeCharacter(long generation, System.IntPtr window, char character) {
        if (generation != Generation) return false;
        Characters++;
        if (CancelAfterCharacter > 0 && Characters >= CancelAfterCharacter) Generation++;
        return true;
    }
    public bool Enter(long generation, System.IntPtr window) {
        if (generation != Generation) return false;
        Enters++; return true;
    }
}
'@
    $desktop = [pscustomobject]@{ Enabled = $true; ExitRequested = $false; ManualStopped = $false }
    $desktop | Add-Member -MemberType ScriptMethod -Name SetEnabled -Value { param($value) $this.Enabled = $value }
    $notepad = [pscustomobject]@{ IsForeground = $true; Window = [IntPtr]1; EditorBounds = @(0, 0, 400, 200); IsOpen = $true; OwnershipLost = $false; Activations = 0; StartupComplete = $false; StartupCharacters = 0 }
    $notepad | Add-Member -MemberType ScriptMethod -Name IsEditorPoint -Value { param($x, $y) return $true }
    $notepad | Add-Member -MemberType ScriptMethod -Name IsCursorOverEditor -Value { return $true }
    $script:monitor = [FakeInputMonitor]::new()
    $script:cycleGeneration = 1L
    $script:targetWindow = [IntPtr]1
    $monitor.CancelAfterCheck = 3
    $timer = [Diagnostics.Stopwatch]::StartNew()
    Assert-Throws { Wait-Cycle 5000 } 'User activity'
    Assert-True ($timer.Elapsed.TotalSeconds -lt 2) 'Long wait was not interrupted promptly.'

    # Mock the OS boundary and timing, preserving the actual production cycle logic.
    function Get-BotWindow { return [IntPtr]1 }
    function Send-BotClick {
        param([int]$X, [int]$Y)
        Assert-CycleActive
        $monitor.Click($cycleGeneration, $targetWindow) | Out-Null
    }
    function Send-BotText {
        param([string]$Text)
        Assert-CycleActive
        if ($Text -eq "`r`n") { $monitor.Enter($cycleGeneration, $targetWindow) | Out-Null }
        else { $monitor.TypeCharacter($cycleGeneration, $targetWindow, $Text[0]) | Out-Null }
    }
    function Get-Delay { param($Minimum, $Maximum) if ($Minimum -eq 'MIN_CLICKS') { return 2 }; return 0 }
    $settings = @{ IDLE_TIME_THRESHOLD = 60; TYPING_CHANCE = 100; HESITATION_CHANCE = 0; RECT_WIDTH = 400; RECT_HEIGHT = 200 }
    $rectLeft = 0; $rectTop = 0; $rectWidth = 400; $rectHeight = 200; $phrases = @('abc')
    $script:monitor = [FakeInputMonitor]::new()
    $monitor.CancelAfterClick = 1
    Assert-Throws { Invoke-BotCycle } 'User activity'
    Assert-True ($monitor.Clicks -eq 1 -and $monitor.Characters -eq 0 -and $monitor.Enters -eq 0) 'Cycle continued after user resumed during clicks.'
    $script:monitor = [FakeInputMonitor]::new()
    $monitor.CancelAfterCharacter = 1
    Assert-Throws { Invoke-BotCycle } 'User activity'
    Assert-True ($monitor.Characters -eq 1 -and $monitor.Enters -eq 0) 'Typing/Enter continued after user activity.'
    $script:monitor = [FakeInputMonitor]::new()
    $monitor.IdleSeconds = 0
    Assert-Throws { Invoke-BotCycle } 'before cycle startup'
    Assert-True ($monitor.Clicks -eq 0) 'Activity between idle check and cycle snapshot was ignored.'
    $script:monitor = [FakeInputMonitor]::new()
    Invoke-BotCycle
    Assert-True ($monitor.Clicks -eq 2 -and $monitor.Characters -eq 3 -and $monitor.Enters -eq 1) 'Uninterrupted cycle failed.'
    $notepad | Add-Member -MemberType ScriptMethod -Name IsCursorOverEditor -Value { return $false } -Force
    $script:monitor = [FakeInputMonitor]::new()
    Assert-Throws { Invoke-BotCycle } 'Cursor left the owned editor'
    Assert-True ($monitor.Clicks -eq 0 -and $monitor.Characters -eq 0) 'A click escaped the owned editor.'
    $notepad | Add-Member -MemberType ScriptMethod -Name IsCursorOverEditor -Value { return $true } -Force
    $desktop.Enabled = $false
    Assert-Throws { Invoke-BotCycle } 'Stopped from tray'
    $desktop.Enabled = $true; $notepad.IsForeground = $false
    Assert-Throws { Invoke-BotCycle } 'Owned Notepad'
    $notepad.IsForeground = $true
    # Physical input turns the icon gray; inactivity reactivates ONLY the owned
    # Notepad. Manual Stop, closed documents and focus refusal must remain paused.
    $notepad | Add-Member -MemberType ScriptMethod -Name MaximizeAndActivate -Value { $this.Activations++; $this.IsForeground = $true }
    $script:monitor = [FakeInputMonitor]::new()
    $script:observedGeneration = $monitor.Generation
    Assert-True (Update-BotActivityState) 'Initial bot state did not run.'
    $monitor.Generation++; $monitor.IdleSeconds = 0
    Assert-True (!(Update-BotActivityState) -and !$desktop.Enabled) 'Physical input did not turn the tray gray.'
    $monitor.IdleSeconds = 59
    Assert-True (!(Update-BotActivityState) -and $notepad.Activations -eq 0) 'Bot resumed before idle threshold.'
    $monitor.IdleSeconds = 60; $notepad.IsForeground = $false
    Assert-True ((Update-BotActivityState) -and $desktop.Enabled -and $notepad.IsForeground -and $notepad.Activations -eq 1) 'Idle resume did not maximize/activate the owned document before turning green.'
    $desktop.ManualStopped = $true; $desktop.Enabled = $false
    Assert-True (!(Update-BotActivityState) -and !$desktop.Enabled -and $notepad.Activations -eq 1) 'Inactivity overrode manual Stop.'
    $desktop.ManualStopped = $false; $notepad.IsOpen = $false
    Assert-True (!(Update-BotActivityState) -and !$desktop.Enabled) 'Closed Notepad resumed automatically.'
    $notepad.IsOpen = $true; $notepad.IsForeground = $false
    $notepad | Add-Member -MemberType ScriptMethod -Name MaximizeAndActivate -Value { $this.Activations++ } -Force
    Assert-True (!(Update-BotActivityState) -and !$desktop.Enabled) 'Foreground refusal enabled automation.'
    $notepad | Add-Member -MemberType ScriptMethod -Name MaximizeAndActivate -Value { $this.IsForeground = $true; $script:monitor.Generation++ } -Force
    Assert-True (!(Update-BotActivityState) -and !$desktop.Enabled) 'User input during focus restoration enabled automation.'
    $script:observedGeneration = $monitor.Generation
    $notepad | Add-Member -MemberType ScriptMethod -Name MaximizeAndActivate -Value { $this.IsForeground = $true; $desktop.ManualStopped = $true } -Force
    Assert-True (!(Update-BotActivityState) -and !$desktop.Enabled) 'Manual Stop during activation was ignored.'
    $desktop.ManualStopped = $false; $desktop.Enabled = $true; $notepad.IsForeground = $true
    $notepad | Add-Member -MemberType ScriptMethod -Name TypeStartupCharacter -Value { $this.StartupCharacters++; $this.StartupComplete = $this.StartupCharacters -ge 21 }
    $script:monitor = [FakeInputMonitor]::new(); $monitor.CancelAfterCheck = 3
    Assert-Throws { Invoke-StartupTyping } 'User activity'
    Assert-True ($notepad.StartupCharacters -eq 1 -and !$notepad.StartupComplete) 'Startup message was pasted or kept typing after physical input.'

    # Exercise the production logger entry point with a fake native producer.
    # Paths/configuration/writer/finally are real; only the OS boundary is replaced.
    $tokens = $null; $errors = $null
    $loggerAst = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'activity_logger.ps1'), [ref]$tokens, [ref]$errors)
    foreach ($definition in $loggerAst.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] }, $false)) {
        . ([scriptblock]::Create($definition.Extent.Text))
    }
    $loggerTry = $loggerAst.EndBlock.Statements | Where-Object { $_ -is [Management.Automation.Language.TryStatementAst] }
    $entry = [scriptblock]::Create($loggerTry.Extent.Text.Replace('$PSScriptRoot', '$repo'))
    Add-Type @'
public class FakeRecorder {
    public bool FailHealth, FailDispose, Disposed;
    private int drained;
    public void CheckHealth() { if (FailHealth) throw new System.IO.IOException("simulated capture failure"); }
    public string[] Drain() {
        if (drained == 0) { drained++; return new string[] { "1727621415,mc,10,20," }; }
        if (Disposed && drained == 1) { drained++; return new string[] { "1727621416,sc,10,20," }; }
        return new string[0];
    }
    public void Dispose() { Disposed = true; if (FailDispose) throw new System.IO.IOException("simulated unhook failure"); }
}
'@
    $realInitialize = ${function:Initialize-Kmao}
    function Initialize-Kmao { param($Component) & $realInitialize $Component $temporary }
    function Import-KmaoWindows { }
    function Enter-KmaoSession { return $null }
    function Set-KmaoReady { }
    function New-KmaoInput {
        param($RecordEvents, $SamplingMilliseconds)
        if ($scenario -eq 'startup') { throw 'simulated hook installation failure' }
        $script:producer = [FakeRecorder]::new()
        $producer.FailHealth = $scenario -eq 'capture'
        $producer.FailDispose = $scenario -eq 'cleanup'
        return $producer
    }
    # Accelerate the duration boundary; parser/range validation is tested above.
    function Read-KmaoConfig { return @{ MOUSE_SAMPLING_INTERVAL = 200; RECORDING_DURATION_MINUTES = 0.001 } }
    foreach ($scenario in @('success', 'startup', 'capture', 'cleanup')) {
        $recorder = $null; $writer = $null; $failed = $false; $eventCount = 0L; $pendingWrites = 0
        . $entry 2>$null
        Assert-True ($failed -eq ($scenario -ne 'success')) "Incorrect logger failure status: $scenario"
        $probe = [IO.File]::Open($logFile, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        $probe.Dispose()
        if ($scenario -ne 'startup') {
            Assert-True $producer.Disposed "Producer was not disposed: $scenario"
            $recorded = @(Import-Csv $logFile)
            Assert-True ($recorded.Count -eq 2 -and $recorded[1].e -eq 'sc') "Final events lost during cleanup: $scenario"
        }
        if ($scenario -ne 'success') {
            Assert-True ((Get-Content $KmaoLogFile -Raw) -match 'simulated') "Actual error missing from diagnostics: $scenario"
        }
    }
    Write-Host 'PASS: syntax, C# compilation/ABI, paths, configuration, logs, cancellation and logger lifecycle.'

} finally {
    Remove-Item -LiteralPath $temporary -Recurse -Force
}
