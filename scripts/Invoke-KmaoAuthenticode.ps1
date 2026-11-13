# Inno invokes this entry for Setup, Uninstall and temporary self-copies.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$SignerScript
)
$ErrorActionPreference = 'Stop'
try {
    . (Join-Path $PSScriptRoot 'Kmao.Authenticode.ps1')
    Invoke-KmaoAuthenticodeSigner -Path $Path -SignerScript $SignerScript
}
catch { Write-Error -ErrorRecord $_ -ErrorAction Continue; exit 1 }
