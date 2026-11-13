[CmdletBinding()]
param(
    [ValidateSet('bot', 'logger')][string]$Component = 'bot',
    [string]$InstallRoot,
    [switch]$SkipUpdateCheck,
    [switch]$Rollback,
    [string]$HealthToken
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib/Kmao.Common.ps1')
. (Join-Path $PSScriptRoot 'lib/Kmao.Update.ps1')
$workspace = $null
$handedOff = $false
try {
    Initialize-Kmao launcher
    if ($InstallRoot -and (!$SkipUpdateCheck -or $Rollback)) {
        try {
            if ($Rollback) {
                $previous = (Read-KmaoState $InstallRoot previous).version
                $question = "Restore KMAO $previous and restart $Component? Active KMAO recordings will be closed cleanly."
                $offer = @{ Rollback = $true }
            }
            else {
                Write-KmaoLog INFO "Checking testing-channel updates. Installed: $((Read-KmaoState $InstallRoot).version)."
                $workspace = Join-Path $KmaoRoot ('updates/' + [Guid]::NewGuid().ToString('N'))
                New-Item -ItemType Directory -Path $workspace -Force | Out-Null
                $offer = Get-KmaoUpdateOffer $InstallRoot $workspace
                if ($null -ne $offer) {
                    Write-KmaoLog INFO "Update available: $($offer.Manifest.version)."
                    $current = (Read-KmaoState $InstallRoot).version
                    $question = "Installed: $current`nAvailable: $($offer.Manifest.version)`n`n$($offer.Manifest.notes)`n`nUpdate now? Active KMAO recordings will be closed cleanly."
                }
                else { Write-KmaoLog INFO 'No newer published prerelease is available in the testing channel.' }
            }
            if ($null -ne $offer) {
                if (Confirm-KmaoUpdate $question) {
                    # An updater process remains independent of the component it may need to stop.
                    $arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -InstallRoot "{1}" -Component {2}' -f (Join-Path $PSScriptRoot 'Apply-KmaoUpdate.ps1'), $InstallRoot, $Component
                    if ($Rollback) { $arguments += ' -Rollback' }
                    else {
                        $offer.Url | Set-Content -LiteralPath (Join-Path $workspace 'download-url.txt') -Encoding UTF8
                        $arguments += ' -Workspace "' + $workspace + '"'
                    }
                    Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $arguments | Out-Null
                    $handedOff = $true
                    return
                }
                else { Write-KmaoLog INFO 'Update or rollback declined by the user.' }
            }
        }
        catch { Write-KmaoLog WARN "Update check failed; continuing installed version. $($_.Exception.Message)" }
    }
    $scriptName = if ($Component -eq 'bot') { 'dev.ps1' } else { 'activity_logger.ps1' }
    $global:LASTEXITCODE = 0
    & (Join-Path $PSScriptRoot $scriptName) -HealthToken $HealthToken
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
catch { Write-Error -ErrorRecord $_ -ErrorAction Continue; exit 1 }
finally {
    if (!$handedOff -and $workspace -and (Test-Path -LiteralPath $workspace)) { Remove-Item -LiteralPath $workspace -Recurse -Force }
}
