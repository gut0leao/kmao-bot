# Optional provider for a Code Signing certificate exposed by a Windows token/HSM.
# Configure the public thumbprint and timestamp URL in the environment. No PFX/PIN arguments.
[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$Path)
$ErrorActionPreference = 'Stop'
try {
    . (Join-Path $PSScriptRoot 'Kmao.Authenticode.ps1')
    $thumbprint = $env:KMAO_AUTHENTICODE_THUMBPRINT -replace '\s', ''
    if ($thumbprint -notmatch '^[a-fA-F0-9]{40}$') { throw 'Set KMAO_AUTHENTICODE_THUMBPRINT to the Code Signing certificate thumbprint.' }
    $timestamp = $env:KMAO_AUTHENTICODE_TIMESTAMP_URL
    $uri = $null
    if (![Uri]::TryCreate($timestamp, [UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -notin @('http', 'https') -or $uri.UserInfo) {
        throw 'Set KMAO_AUTHENTICODE_TIMESTAMP_URL to the timestamp service supplied by the certificate provider.'
    }
    $certificate = Get-Item -LiteralPath "Cert:\CurrentUser\My\$thumbprint" -ErrorAction Stop
    if (!$certificate.HasPrivateKey -or $certificate.NotBefore -gt (Get-Date) -or $certificate.NotAfter -le (Get-Date)) {
        throw 'The Code Signing certificate must be valid and have an accessible private key.'
    }
    $codeSigning = @(Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert | Where-Object { $_.Thumbprint -eq $thumbprint })
    if ($codeSigning.Count -ne 1) { throw 'The selected certificate is not a Code Signing certificate.' }
    $Path = (Resolve-Path -LiteralPath $Path).ProviderPath
    # Inno signs PE files; PowerShell's SIP also supports .ps1 files. Token/HSM
    # middleware may prompt the user for a PIN; this script never captures it.
    $result = Set-AuthenticodeSignature -LiteralPath $Path -Certificate $certificate -HashAlgorithm SHA256 -TimestampServer $timestamp -IncludeChain NotRoot -ErrorAction Stop
    if ($result.Status -ne 'Valid') { throw "Signing failed: $($result.Status) $($result.StatusMessage)" }
    Assert-KmaoAuthenticodeSignature $Path
}
catch { Write-Error -ErrorRecord $_ -ErrorAction Continue; exit 1 }
