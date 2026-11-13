# Migration, complete commented configuration and atomic reload; no Windows input/UI.
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Resolve-Path (Join-Path $PSScriptRoot '..')).ProviderPath)
. (Join-Path $repo 'lib/Kmao.Common.ps1')
. (Join-Path $repo 'lib/Kmao.Configuration.ps1')
function Assert-True { param([bool]$Value, [string]$Message) if (!$Value) { throw $Message } }
function Assert-Throws { param([scriptblock]$Action, [string]$Pattern) try { & $Action } catch { if ($_.Exception.Message -notmatch $Pattern) { throw }; return }; throw "Expected error: $Pattern" }
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('kmao-config-' + [Guid]::NewGuid().ToString('N'))
try {
    Initialize-Kmao tests $temporary
    $folder = Join-Path $KmaoRoot 'config'
    Set-Content (Join-Path $folder 'bot.conf') "MIN_INTERVAL=7`nMAX_INTERVAL=12`nIDLE_TIME_THRESHOLD=13" -Encoding UTF8
    Set-Content (Join-Path $folder 'kmao.conf') "MOUSE_SAMPLING_INTERVAL=456`nRECORDING_DURATION_MINUTES=11" -Encoding UTF8
    $oldBot = [IO.File]::ReadAllBytes((Join-Path $folder 'bot.conf'))
    $oldLogger = [IO.File]::ReadAllBytes((Join-Path $folder 'kmao.conf'))
    $configPath = Initialize-KmaoAppConfig $KmaoRoot
    $values = Read-KmaoAppConfig $configPath
    Assert-True ($values.MIN_INTERVAL -eq 7 -and $values.MAX_INTERVAL -eq 12 -and $values.IDLE_TIME_THRESHOLD -eq 13 -and $values.MOUSE_SAMPLING_INTERVAL -eq 456 -and $values.RECORDING_DURATION_MINUTES -eq 11) 'Migration lost custom bot/logger values.'
    Assert-True ([Convert]::ToBase64String($oldBot) -eq [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $folder 'bot.conf')))) 'Legacy bot configuration changed.'
    Assert-True ([Convert]::ToBase64String($oldLogger) -eq [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $folder 'kmao.conf')))) 'Legacy logger configuration changed.'
    $lines = @(Get-Content -LiteralPath $configPath -Encoding UTF8)
    $keys = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^([A-Z_]+)=') {
            $keys += $matches[1]
            Assert-True ($i -gt 0 -and $lines[$i-1] -match '^# .+') "Configuration $($matches[1]) lacks a preceding comment."
        }
    }
    Assert-True ($keys.Count -eq (Get-KmaoConfigDefaults).Count) 'User file does not contain all parameters.'
    $original = [IO.File]::ReadAllText($configPath)
    Set-Content -LiteralPath $configPath -Value ($original.Replace('IDLE_TIME_THRESHOLD=13', 'IDLE_TIME_THRESHOLD=5')) -Encoding UTF8
    Initialize-KmaoAppConfig $KmaoRoot | Out-Null
    Assert-True ((Read-KmaoAppConfig $configPath).IDLE_TIME_THRESHOLD -eq 5) 'Initialization overwrote user edits.'
    foreach ($bad in @('MIN_INTERVAL=240', 'STARTUP_MAX_CHAR_DELAY=1', 'TYPING_CHANCE=101', 'UNKNOWN_OPTION=1', "IDLE_TIME_THRESHOLD=2`nIDLE_TIME_THRESHOLD=3")) {
        Set-Content -LiteralPath $configPath -Value $bad -Encoding UTF8
        Assert-Throws { Read-KmaoAppConfig $configPath } 'must be|Unknown|Duplicate'
    }
    # Load the actual reload/state functions, using fake desktop and Notepad only.
    $tokens = $null; $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'dev.ps1'), [ref]$tokens, [ref]$errors)
    foreach ($definition in $ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] }, $false)) { . ([scriptblock]::Create($definition.Extent.Text)) }
    $desktop = [pscustomobject]@{ Enabled = $false; ManualStopped = $false; ExitRequested = $false }
    $desktop | Add-Member ScriptMethod SetEnabled { param($value) $this.Enabled = $value }
    $notepad = [pscustomobject]@{ IsOpen = $true; OwnershipLost = $false; IsForeground = $false; Activations = 0 }
    $notepad | Add-Member ScriptMethod MaximizeAndActivate { $this.IsForeground = $true; $this.Activations++ }
    $monitor = [pscustomobject]@{ Generation = 1; IdleSeconds = 6 }
    $session = $null; $script:configurationError = $null
    $script:settings = Get-KmaoConfigDefaults
    Set-Content -LiteralPath $configPath -Value 'IDLE_TIME_THRESHOLD=5' -Encoding UTF8
    Assert-True (Start-BotRunning) 'Idle resume ignored the freshly changed idle threshold.'
    Assert-True ($desktop.Enabled -and $settings.IDLE_TIME_THRESHOLD -eq 5 -and $notepad.Activations -eq 1) 'Config was not applied before Running.'
    $desktop.Enabled = $false
    Set-Content -LiteralPath $configPath -Value "IDLE_TIME_THRESHOLD=8`nTYPING_CHANCE=10" -Encoding UTF8
    Assert-True (Start-BotRunning -Explicit) 'Explicit Run failed to reload configuration.'
    Assert-True ($settings.IDLE_TIME_THRESHOLD -eq 8 -and $settings.TYPING_CHANCE -eq 10) 'Explicit Run kept stale configuration.'
    $desktop.Enabled = $false; $before = $notepad.Activations
    Set-Content -LiteralPath $configPath -Value 'TYPING_CHANCE=999' -Encoding UTF8
    Assert-True (!(Start-BotRunning -Explicit) -and !$desktop.Enabled -and $notepad.Activations -eq $before -and $settings.TYPING_CHANCE -eq 10) 'Invalid reload turned green, stole focus or partially replaced valid settings.'
    Set-Content -LiteralPath $configPath -Value 'TYPING_CHANCE=20' -Encoding UTF8
    Assert-True ((Start-BotRunning -Explicit) -and $settings.TYPING_CHANCE -eq 20) 'Bot did not recover after correcting configuration.'
    Write-Host 'PASS: complete commented user config, legacy preservation, validation, reload on manual/idle Run and safe recovery from invalid settings.'
}
finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Recurse -Force } }
