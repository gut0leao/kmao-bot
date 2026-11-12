param([string]$CommonPath, [string]$ReadyPath, [int]$CleanupMilliseconds = 0)
$ErrorActionPreference = 'Stop'
. $CommonPath
$session = $null
try {
    $session = Enter-KmaoSession bot
    Set-Content -LiteralPath $ReadyPath 'ready'
    while (!(Test-KmaoStopRequested $session)) { Start-Sleep -Milliseconds 25 }
    Start-Sleep -Milliseconds $CleanupMilliseconds
}
finally { Exit-KmaoSession $session }
