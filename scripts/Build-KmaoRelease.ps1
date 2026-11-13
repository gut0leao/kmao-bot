[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$PrivateKeyPath,
    [Parameter(Mandatory = $true)][string]$PublicKeyPath,
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '../dist/release'),
    [string]$IsccPath,
    [switch]$SkipInstaller,
    [string]$AuthenticodeSigner,
    [switch]$AllowUnsigned
)
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Resolve-Path (Join-Path $PSScriptRoot '..')).ProviderPath)
. (Join-Path $repo 'lib/Kmao.Update.ps1')
. (Join-Path $PSScriptRoot 'Kmao.BuildTools.ps1')
. (Join-Path $PSScriptRoot 'Kmao.Authenticode.ps1')
if ($AuthenticodeSigner -and $AllowUnsigned) { throw 'AuthenticodeSigner and AllowUnsigned are mutually exclusive.' }
if (!$AuthenticodeSigner -and !$AllowUnsigned) {
    throw 'A trusted Authenticode signer is required for release builds. Configure -AuthenticodeSigner, or use -AllowUnsigned only for development (not Smart App Control compatible).'
}
if ($AuthenticodeSigner) {
    if ($env:OS -ne 'Windows_NT' -or $PSVersionTable.PSEdition -ne 'Desktop') { throw 'Authenticode release builds require Windows PowerShell 5.1. Use the WSL build bridge.' }
    $AuthenticodeSigner = (Resolve-Path -LiteralPath $AuthenticodeSigner -ErrorAction Stop).ProviderPath
    if ([IO.Path]::GetExtension($AuthenticodeSigner) -ne '.ps1') { throw 'AuthenticodeSigner must be a PowerShell provider script accepting -Path.' }
}
else { Write-Warning 'DEVELOPMENT BUILD: no Windows Authenticode signature. Do not publish for Smart App Control users.' }
if (!$SkipInstaller) { $IsccPath = Resolve-KmaoIscc $IsccPath }
$version = (Get-Content -LiteralPath (Join-Path $repo 'VERSION') -Raw).Trim()
ConvertTo-KmaoVersion $version | Out-Null
if (Test-Path -LiteralPath $OutputDirectory) { throw 'Output directory already exists. Choose a new directory.' }
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$OutputDirectory = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $OutputDirectory).ProviderPath)
$rsa = [Security.Cryptography.RSA]::Create()
$public = [Security.Cryptography.RSA]::Create()
try {
    $rsa.FromXmlString([IO.File]::ReadAllText((Resolve-Path -LiteralPath $PrivateKeyPath).ProviderPath))
    $publicXml = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $PublicKeyPath).ProviderPath)
    if (([xml]$publicXml).RSAKeyValue.D) { throw 'PublicKeyPath must not contain a private key.' }
    $public.FromXmlString($publicXml)
    if ($rsa.KeySize -lt 3072 -or $rsa.ToXmlString($false) -cne $public.ToXmlString($false)) { throw 'Signing keys do not match or are too small.' }
    $payload = Join-Path $OutputDirectory 'payload'
    & (Join-Path $repo 'Export-Kmao.ps1') -Destination $payload -SkipArchive
    if ($env:OS -eq 'Windows_NT' -and $PSVersionTable.PSEdition -eq 'Desktop') { New-KmaoCompiledRuntime $payload }
    if ($AuthenticodeSigner) {
        foreach ($file in Get-ChildItem -LiteralPath $payload -File -Recurse | Where-Object { $_.Extension -in @('.ps1', '.dll', '.exe') }) {
            if ($file.Extension -eq '.ps1') {
                # BOM keeps signed UTF-8 scripts unambiguous in Windows PowerShell 5.1.
                [IO.File]::WriteAllText($file.FullName, [IO.File]::ReadAllText($file.FullName), [Text.UTF8Encoding]::new($true))
            }
            Invoke-KmaoAuthenticodeSigner $file.FullName $AuthenticodeSigner
        }
    }
    $assetName = "kmao-$version.zip"
    # Hash and archive the final, signed bytes. No payload mutation is allowed after this.
    Compress-Archive -Path (Join-Path $payload '*') -DestinationPath (Join-Path $OutputDirectory $assetName)
    $files = [ordered]@{}
    foreach ($file in Get-ChildItem -LiteralPath $payload -File -Recurse | Sort-Object FullName) {
        $name = $file.FullName.Substring($payload.Length + 1).Replace('\', '/')
        $files[$name] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    $history = [IO.File]::ReadAllText((Join-Path $repo 'CHANGELOG.md'))
    $entry = [regex]::Match($history, '(?ms)^##\s+' + [regex]::Escape($version) + '\s*\r?\n(?<body>.*?)(?=^##\s|\z)')
    if (!$entry.Success) { throw "CHANGELOG.md has no release notes for $version." }
    $notes = $entry.Groups['body'].Value.Trim()
    [IO.File]::WriteAllText((Join-Path $OutputDirectory 'kmao-release-notes.md'), $notes + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    $manifest = [ordered]@{
        protocol = 1; channel = 'testing'; configurationSchema = 1; version = $version; asset = $assetName
        sha256 = (Get-FileHash -LiteralPath (Join-Path $OutputDirectory $assetName) -Algorithm SHA256).Hash.ToLowerInvariant()
        notes = $notes
        files = $files
    }
    $manifestPath = Join-Path $OutputDirectory 'kmao-manifest.json'
    [IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
    $signature = $rsa.SignData([IO.File]::ReadAllBytes($manifestPath), [Security.Cryptography.HashAlgorithmName]::SHA256, [Security.Cryptography.RSASignaturePadding]::Pkcs1)
    [IO.File]::WriteAllText((Join-Path $OutputDirectory 'kmao-manifest.sig'), [Convert]::ToBase64String($signature), [Text.UTF8Encoding]::new($false))
    Read-KmaoSignedManifest $manifestPath (Join-Path $OutputDirectory 'kmao-manifest.sig') $PublicKeyPath | Out-Null
    $installerSource = Join-Path $OutputDirectory 'installer-source'
    New-Item -ItemType Directory -Path $installerSource | Out-Null
    Copy-Item -LiteralPath (Join-Path $payload 'Start-Kmao.ps1') -Destination $installerSource
    [IO.File]::WriteAllText((Join-Path $installerSource 'update-public-key.xml'), $public.ToXmlString($false), [Text.UTF8Encoding]::new($false))
    Write-KmaoState $installerSource current $version
    $versions = Join-Path $installerSource 'versions'
    New-Item -ItemType Directory -Path $versions | Out-Null
    Copy-Item -LiteralPath $payload -Destination (Join-Path $versions $version) -Recurse
    if (!$SkipInstaller) {
        $compilerArguments = @("/DAppVersion=$version", "/DSourceDir=$installerSource", "/DOutputDir=$OutputDirectory")
        if ($AuthenticodeSigner) {
            New-Item -ItemType Directory -Path (Join-Path $OutputDirectory 'signed-uninstaller') | Out-Null
            $compilerArguments += '/DAuthenticode=1'
            $compilerArguments += '/Skmao=' + (Get-KmaoInnoSignCommand $AuthenticodeSigner)
        }
        $compilerArguments += (Join-Path $repo 'installer/Kmao.iss')
        & $IsccPath @compilerArguments
        if ($LASTEXITCODE -ne 0) { throw 'Inno Setup compilation failed.' }
        if ($AuthenticodeSigner) {
            Assert-KmaoAuthenticodeSignature (Join-Path $OutputDirectory "kmao-setup-$version.exe")
            $uninstallers = @(Get-ChildItem -LiteralPath (Join-Path $OutputDirectory 'signed-uninstaller') -Filter '*.exe')
            if (!$uninstallers.Count) { throw 'No signed uninstaller was produced.' }
            foreach ($file in $uninstallers) { Assert-KmaoAuthenticodeSignature $file.FullName }
        }
    }
} finally { $rsa.Dispose(); $public.Dispose() }
if ($AllowUnsigned) { Write-Warning 'This output is a development build without Authenticode.' }
Write-Host "Release $version built in $OutputDirectory. Nothing was published."
