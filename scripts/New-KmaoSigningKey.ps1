[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$PrivateKeyPath,
    [Parameter(Mandatory = $true)][string]$PublicKeyPath
)
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')) + [IO.Path]::DirectorySeparatorChar
$privatePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($PrivateKeyPath)
$PublicKeyPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($PublicKeyPath)
if ($privatePath -ieq $PublicKeyPath) { throw 'Private and public key paths must be different.' }
if ($privatePath.StartsWith($repo, [StringComparison]::OrdinalIgnoreCase)) { throw 'Store the private signing key outside the repository.' }
if ((Test-Path -LiteralPath $privatePath) -or (Test-Path -LiteralPath $PublicKeyPath)) { throw 'Refusing to overwrite an existing signing key.' }
$rsa = [Security.Cryptography.RSA]::Create()
try {
    $rsa.KeySize = 3072
    foreach ($path in @($privatePath, $PublicKeyPath)) { New-Item -ItemType Directory -Path (Split-Path -Parent ([IO.Path]::GetFullPath($path))) -Force | Out-Null }
    [IO.File]::WriteAllText($privatePath, $rsa.ToXmlString($true), [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText([IO.Path]::GetFullPath($PublicKeyPath), $rsa.ToXmlString($false), [Text.UTF8Encoding]::new($false))
    if ($env:OS -eq 'Windows_NT') {
        $acl = Get-Acl -LiteralPath $privatePath
        $acl.SetAccessRuleProtection($true, $false)
        $acl.SetAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.WindowsIdentity]::GetCurrent().Name, 'FullControl', 'Allow'))
        Set-Acl -LiteralPath $privatePath -AclObject $acl
    }
    else { & chmod 600 $privatePath; if ($LASTEXITCODE -ne 0) { throw 'Could not restrict private key permissions.' } }
} finally { $rsa.Dispose() }
Write-Host 'Keys created. Back up the private key securely; distribute only the public key.'
