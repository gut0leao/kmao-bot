[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$PrivateKeyPath,
    [Parameter(Mandatory = $true)][string]$PublicKeyPath,
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '../dist/release'),
    [string]$IsccPath,
    [switch]$SkipInstaller
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $repo 'lib/Kmao.Update.ps1')
$version = (Get-Content -LiteralPath (Join-Path $repo 'VERSION') -Raw).Trim()
ConvertTo-KmaoVersion $version | Out-Null
if (Test-Path -LiteralPath $OutputDirectory) { throw 'Output directory already exists. Choose a new directory.' }
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$OutputDirectory = (Resolve-Path $OutputDirectory).Path
$rsa = [Security.Cryptography.RSA]::Create()
$public = [Security.Cryptography.RSA]::Create()
try {
    $rsa.FromXmlString([IO.File]::ReadAllText((Resolve-Path $PrivateKeyPath).Path))
    $publicXml = [IO.File]::ReadAllText((Resolve-Path $PublicKeyPath).Path)
    if (([xml]$publicXml).RSAKeyValue.D) { throw 'PublicKeyPath must not contain a private key.' }
    $public.FromXmlString($publicXml)
    if ($rsa.KeySize -lt 3072 -or $rsa.ToXmlString($false) -cne $public.ToXmlString($false)) { throw 'Signing keys do not match or are too small.' }
    $payload = Join-Path $OutputDirectory 'payload'
    & (Join-Path $repo 'Export-Kmao.ps1') -Destination $payload
    $assetName = "kmao-$version.zip"
    Move-Item -LiteralPath "$payload.zip" -Destination (Join-Path $OutputDirectory $assetName)
    $files = [ordered]@{}
    foreach ($file in Get-ChildItem -LiteralPath $payload -File -Recurse | Sort-Object FullName) {
        $name = $file.FullName.Substring($payload.Length + 1).Replace('\', '/')
        $files[$name] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    $manifest = [ordered]@{
        protocol = 1; channel = 'testing'; configurationSchema = 1; version = $version; asset = $assetName
        sha256 = (Get-FileHash -LiteralPath (Join-Path $OutputDirectory $assetName) -Algorithm SHA256).Hash.ToLowerInvariant()
        notes = (Get-Content -LiteralPath (Join-Path $repo 'CHANGELOG.md') -Raw)
        files = $files
    }
    $manifestPath = Join-Path $OutputDirectory 'kmao-manifest.json'
    [IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
    $signature = $rsa.SignData([IO.File]::ReadAllBytes($manifestPath), [Security.Cryptography.HashAlgorithmName]::SHA256, [Security.Cryptography.RSASignaturePadding]::Pkcs1)
    [IO.File]::WriteAllText((Join-Path $OutputDirectory 'kmao-manifest.sig'), [Convert]::ToBase64String($signature), [Text.UTF8Encoding]::new($false))
    Read-KmaoSignedManifest $manifestPath (Join-Path $OutputDirectory 'kmao-manifest.sig') $PublicKeyPath | Out-Null
    $installerSource = Join-Path $OutputDirectory 'installer-source'
    New-Item -ItemType Directory -Path $installerSource | Out-Null
    Copy-Item -LiteralPath (Join-Path $repo 'Start-Kmao.ps1') -Destination $installerSource
    [IO.File]::WriteAllText((Join-Path $installerSource 'update-public-key.xml'), $public.ToXmlString($false), [Text.UTF8Encoding]::new($false))
    Write-KmaoState $installerSource current $version
    $versions = Join-Path $installerSource 'versions'
    New-Item -ItemType Directory -Path $versions | Out-Null
    Copy-Item -LiteralPath $payload -Destination (Join-Path $versions $version) -Recurse
    if (!$SkipInstaller) {
        if (!$IsccPath) { $IsccPath = (Get-Command ISCC.exe -ErrorAction Stop).Source }
        & $IsccPath "/DAppVersion=$version" "/DSourceDir=$installerSource" "/DOutputDir=$OutputDirectory" (Join-Path $repo 'installer/Kmao.iss')
        if ($LASTEXITCODE -ne 0) { throw 'Inno Setup compilation failed.' }
    }
} finally { $rsa.Dispose(); $public.Dispose() }
Write-Host "Release $version built in $OutputDirectory. Nothing was published."
