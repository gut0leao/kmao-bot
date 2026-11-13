# Complete application configuration. Loaded after Kmao.Common.ps1.
function Get-KmaoConfigDefaults {
    $values = @{}
    foreach ($line in Get-Content -LiteralPath (Join-Path $PSScriptRoot '../config/application.conf.example') -Encoding UTF8 -ErrorAction Stop) {
        if ($line -match '^([A-Z_]+)=([0-9]+)$') { $values[$matches[1]] = [int]$matches[2] }
    }
    return $values
}

function Read-KmaoAppConfig {
    param([string]$Path)
    $defaults = Get-KmaoConfigDefaults
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
        STARTUP_MIN_CHAR_DELAY = @(0, 60000)
        STARTUP_MAX_CHAR_DELAY = @(0, 60000)
        MOUSE_SAMPLING_INTERVAL = @(1, 60000)
        RECORDING_DURATION_MINUTES = @(0, 525600)
    }
    $values = Read-KmaoConfig $Path $defaults $ranges
    foreach ($pair in @(
        @('MIN_INTERVAL', 'MAX_INTERVAL'), @('MIN_CLICKS', 'MAX_CLICKS'),
        @('MIN_CHAR_DELAY', 'MAX_CHAR_DELAY'), @('MIN_HESITATION', 'MAX_HESITATION'),
        @('SPACE_MIN_DELAY', 'SPACE_MAX_DELAY'), @('PUNCT_MIN_DELAY', 'PUNCT_MAX_DELAY'),
        @('CURSOR_MIN_DELAY', 'CURSOR_MAX_DELAY'),
        @('MULTI_CLICK_MIN_DELAY', 'MULTI_CLICK_MAX_DELAY'), @('PRE_TYPING_MIN_DELAY', 'PRE_TYPING_MAX_DELAY'),
        @('PRE_ENTER_MIN_DELAY', 'PRE_ENTER_MAX_DELAY'), @('FINAL_MIN_DELAY', 'FINAL_MAX_DELAY'),
        @('STARTUP_MIN_CHAR_DELAY', 'STARTUP_MAX_CHAR_DELAY')
    )) {
        if ($values[$pair[0]] -ge $values[$pair[1]]) { throw "$($pair[0]) must be less than $($pair[1])." }
    }
    return $values
}

function Initialize-KmaoAppConfig {
    param([string]$Root)
    $path = Join-Path $Root 'config/application.conf'
    if (Test-Path -LiteralPath $path) { return $path }
    $values = Get-KmaoConfigDefaults
    # Only explicitly set legacy values are migrated; original files remain for rollback.
    foreach ($name in @('bot.conf', 'kmao.conf')) {
        $legacy = Join-Path $Root "config/$name"
        if (Test-Path -LiteralPath $legacy) {
            $parsed = Read-KmaoAppConfig $legacy
            foreach ($line in Get-Content -LiteralPath $legacy -Encoding UTF8) {
                if ($line -match '^\s*([A-Z_]+)\s*=') { $values[$matches[1]] = $parsed[$matches[1]] }
            }
        }
    }
    $template = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../config/application.conf.example') -Encoding UTF8
    $lines = foreach ($line in $template) {
        if ($line -match '^([A-Z_]+)=') { $matches[1] + '=' + $values[$matches[1]] } else { $line }
    }
    New-Item -ItemType Directory (Split-Path -Parent $path) -Force | Out-Null
    $temporary = $path + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [IO.File]::WriteAllLines($temporary, [string[]]$lines, [Text.UTF8Encoding]::new($true))
        Read-KmaoAppConfig $temporary | Out-Null
        try { [IO.File]::Move($temporary, $path) }
        catch { if (!(Test-Path -LiteralPath $path)) { throw } }
    }
    finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force } }
    Write-KmaoLog INFO "Application configuration ready: $path. Legacy files preserved."
    return $path
}
