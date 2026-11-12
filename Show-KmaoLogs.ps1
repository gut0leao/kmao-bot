param([Parameter(Mandatory = $true)][string]$LogPath)
$ErrorActionPreference = 'Stop'
try {
    $Host.UI.RawUI.WindowTitle = 'KMAO Bot - Logs'
    Write-Host "Following $LogPath"
    Write-Host 'Press Ctrl+C or close this window to stop following. The bot keeps running.'
    Get-Content -LiteralPath $LogPath -Encoding UTF8 -Tail 50 -Wait
}
catch { Write-Error -ErrorRecord $_ -ErrorAction Continue; Read-Host 'Press Enter to close' | Out-Null; exit 1 }
