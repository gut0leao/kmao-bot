# Real cryptography and packages; mocks are limited to network, process startup and UI.
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Resolve-Path (Join-Path $PSScriptRoot '..')).ProviderPath)
. (Join-Path $repo 'lib/Kmao.Common.ps1')
. (Join-Path $repo 'lib/Kmao.Update.ps1')
. (Join-Path $repo 'scripts/Kmao.BuildTools.ps1')
function Assert-True { param([bool]$Condition, [string]$Message) if (!$Condition) { throw $Message } }
function Assert-Throws {
    param([scriptblock]$Action, [string]$Pattern)
    try { & $Action } catch { if ($_.Exception.ToString() -notmatch $Pattern) { throw }; return }
    throw "Expected failure matching: $Pattern"
}
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('kmao-updates-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $temporary | Out-Null
$rsa = $null
try {
    $private = Join-Path $temporary 'private.xml'
    $public = Join-Path $temporary 'public.xml'
    & (Join-Path $repo 'scripts/New-KmaoSigningKey.ps1') -PrivateKeyPath $private -PublicKeyPath $public
    Assert-Throws { & (Join-Path $repo 'scripts/New-KmaoSigningKey.ps1') -PrivateKeyPath (Join-Path $temporary 'same-key.xml') -PublicKeyPath (Join-Path $temporary 'same-key.xml') } 'must be different'
    Assert-Throws { & (Join-Path $repo 'scripts/New-KmaoSigningKey.ps1') -PrivateKeyPath $private -PublicKeyPath $public } 'overwrite'
    Assert-Throws { & (Join-Path $repo 'scripts/New-KmaoSigningKey.ps1') -PrivateKeyPath (Join-Path $repo 'forbidden.private.xml') -PublicKeyPath (Join-Path $temporary 'other-public.xml') } 'outside the repository'
    $release = Join-Path $temporary 'release'
    & (Join-Path $repo 'scripts/Build-KmaoRelease.ps1') -PrivateKeyPath $private -PublicKeyPath $public -OutputDirectory $release -SkipInstaller -AllowUnsigned
    $manifestPath = Join-Path $release 'kmao-manifest.json'
    $signaturePath = Join-Path $release 'kmao-manifest.sig'
    $original = [IO.File]::ReadAllText($manifestPath)
    $originalSignature = [IO.File]::ReadAllText($signaturePath)
    $manifest = Read-KmaoSignedManifest $manifestPath $signaturePath $public
    $archive = Join-Path $release $manifest.asset
    $expanded = Join-Path $temporary 'expanded'
    Expand-KmaoVerifiedPackage $archive $manifest $expanded
    Assert-True (Test-Path (Join-Path $expanded 'Launch-Kmao.ps1')) 'Signed payload did not extract.'
    $rsa = [Security.Cryptography.RSA]::Create()
    $rsa.FromXmlString([IO.File]::ReadAllText($private))
    function Save-TestManifest {
        param($Value)
        [IO.File]::WriteAllText($manifestPath, ($Value | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
        $signature = $rsa.SignData([IO.File]::ReadAllBytes($manifestPath), [Security.Cryptography.HashAlgorithmName]::SHA256, [Security.Cryptography.RSASignaturePadding]::Pkcs1)
        [IO.File]::WriteAllText($signaturePath, [Convert]::ToBase64String($signature))
    }
    [IO.File]::AppendAllText($manifestPath, ' ')
    Assert-Throws { Read-KmaoSignedManifest $manifestPath $signaturePath $public } 'signature'
    [IO.File]::WriteAllText($manifestPath, $original)
    $wrong = New-KmaoRsaKey
    try {
        $wrongPublic = Join-Path $temporary 'wrong-public.xml'
        [IO.File]::WriteAllText($wrongPublic, $wrong.ToXmlString($false))
        Assert-Throws { Read-KmaoSignedManifest $manifestPath $signaturePath $wrongPublic } 'signature'
    } finally { $wrong.Dispose() }
    $badSchema = $original | ConvertFrom-Json
    $badSchema.configurationSchema = 2
    Save-TestManifest $badSchema
    Assert-Throws { Read-KmaoSignedManifest $manifestPath $signaturePath $public } 'Incompatible'
    [IO.File]::WriteAllText($manifestPath, $original)
    [IO.File]::WriteAllText($signaturePath, $originalSignature)
    $badArchive = Join-Path $temporary 'damaged.zip'
    [IO.File]::WriteAllBytes($badArchive, [byte[]](1, 2, 3))
    Assert-Throws { Expand-KmaoVerifiedPackage $badArchive $manifest (Join-Path $temporary 'bad-hash') } 'SHA256'
    $traversal = $original | ConvertFrom-Json
    $traversal.files | Add-Member -NotePropertyName '../escape.ps1' -NotePropertyValue ('0' * 64)
    Assert-Throws { Expand-KmaoVerifiedPackage $archive $traversal (Join-Path $temporary 'bad-path') } 'Unsafe'
    Assert-True (!(Test-Path (Join-Path $temporary 'escape.ps1'))) 'Zip traversal escaped destination.'
    $missing = $original | ConvertFrom-Json
    $missing.files.PSObject.Properties.Remove('dev.ps1')
    Assert-Throws { Expand-KmaoVerifiedPackage $archive $missing (Join-Path $temporary 'unlisted') } 'Unexpected'

    $install = Join-Path $temporary 'installed'
    New-Item -ItemType Directory $install | Out-Null
    Copy-Item $public (Join-Path $install 'update-public-key.xml')
    Write-KmaoState $install current '0.2.0'
    Write-KmaoState $install previous '0.1.0'
    Assert-True ((Read-KmaoState $install).version -eq '0.2.0') 'Atomic current state failed.'
    Assert-Throws { Write-KmaoState $install current '../bad' } 'Invalid version'
    $new = $original | ConvertFrom-Json; $new.version = '0.2.1'; $new.asset = 'kmao-0.2.1.zip'
    Save-TestManifest $new
    $workspace = Join-Path $temporary 'offer'
    New-Item -ItemType Directory $workspace | Out-Null
    function New-TestRelease {
        param([string]$Version, [bool]$Prerelease)
        $assets = @('kmao-manifest.json', 'kmao-manifest.sig', "kmao-$Version.zip") | ForEach-Object {
            @{ name = $_; browser_download_url = "https://github.com/gut0leao/kmao-bot/releases/download/v$Version/$_" }
        }
        return @{ tag_name = "v$Version"; draft = $false; prerelease = $Prerelease; assets = $assets }
    }
    # Windows PowerShell 5.1 emits a JSON array as one pipeline object.
    # Do not let the mock enumerate it: that hides real channel-selection failures.
    function Invoke-RestMethod { return ,@((New-TestRelease '9.0.0' $false), (New-TestRelease '0.2.1' $true), (New-TestRelease '0.1.0' $true)) }
    $script:fixtureManifest = $manifestPath
    $script:fixtureSignature = $signaturePath
    function Receive-KmaoFile {
        param($Url, $Destination)
        $source = if ($Url.EndsWith('.sig')) { $script:fixtureSignature } else { $script:fixtureManifest }
        Copy-Item -LiteralPath $source -Destination $Destination -Force
    }
    $offer = Get-KmaoUpdateOffer $install $workspace
    Assert-True ($null -ne $offer -and $offer.Manifest.version -eq '0.2.1') 'Testing channel failed to select a newer prerelease from a non-enumerated API array.'
    $unexpected = New-TestRelease '0.2.1' $true
    $unexpected.assets[0].browser_download_url = 'https://example.com/evil.json'
    Assert-Throws { Get-KmaoAssetUrl $unexpected 'kmao-manifest.json' } 'origin'
    function Invoke-RestMethod { return ,@((New-TestRelease '0.2.1' $true)) }
    Assert-True ((Get-KmaoUpdateOffer $install $workspace).Manifest.version -eq '0.2.1') 'A single prerelease in the API array was missed.'
    function Invoke-RestMethod { return ,@() }
    Assert-True ($null -eq (Get-KmaoUpdateOffer $install $workspace)) 'An empty API array produced an update offer.'
    function Invoke-RestMethod { throw 'simulated offline' }
    Assert-Throws { Get-KmaoUpdateOffer $install $workspace } 'offline'

    # UI refusal and offline checking must still dispatch the installed component.
    $launcherRoot = Join-Path $temporary 'launcher-fixture'
    New-Item -ItemType Directory $launcherRoot | Out-Null
    Set-Content (Join-Path $launcherRoot 'dev.ps1') 'param($HealthToken); Set-Content (Join-Path $PSScriptRoot started) yes'
    $tokens = $null; $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'Launch-Kmao.ps1'), [ref]$tokens, [ref]$errors)
    $body = $ast.EndBlock.Statements | Where-Object { $_ -is [Management.Automation.Language.TryStatementAst] }
    $entry = [scriptblock]::Create($body.Extent.Text.Replace('$PSScriptRoot', '$launcherRoot'))
    $realInitialize = ${function:Initialize-Kmao}
    function Initialize-Kmao { param($Component) & $realInitialize $Component $temporary }
    function Confirm-KmaoUpdate { return $false }
    function Get-KmaoUpdateOffer { if ($scenario -eq 'offline') { throw 'simulated offline' }; return @{ Manifest = @{ version = '0.2.1'; notes = 'test' } } }
    foreach ($scenario in @('refusal', 'offline')) {
        $InstallRoot = $install; $Component = 'bot'; $SkipUpdateCheck = $false; $Rollback = $false
        $workspace = $null; $handedOff = $false; $componentStarted = $false
        . $entry
        Assert-True (Test-Path (Join-Path $launcherRoot started)) "Installed component did not start after $scenario."
        Remove-Item (Join-Path $launcherRoot started)
        Assert-True (!$handedOff) "Update ran after $scenario."
    }

    # Startup failure rolls the pointer back before relaunching the previous version.
    foreach ($version in @('0.2.0', '0.2.1')) {
        $folder = Join-Path $install "versions/$version"
        New-Item -ItemType Directory $folder -Force | Out-Null
        Set-Content (Join-Path $folder 'Launch-Kmao.ps1') '# fixture'
    }
    $personal = Join-Path $temporary 'personal.conf'; Set-Content $personal 'preserve-me'
    function Stop-KmaoComponents { $script:shutdownRequested = $true }
    function Start-KmaoValidatedComponent {
        param($InstallRoot, $Component)
        if ($failStartup -and (Read-KmaoState $InstallRoot).version -eq '0.2.1') { throw 'simulated startup failure' }
        $script:startedVersion = (Read-KmaoState $InstallRoot).version
    }
    $failStartup = $false
    Switch-KmaoVersion $install '0.2.1' bot
    Assert-True ((Read-KmaoState $install).version -eq '0.2.1' -and (Read-KmaoState $install previous).version -eq '0.2.0') 'Successful activation did not retain previous version.'
    Write-KmaoState $install current '0.2.0'
    $failStartup = $true; $shutdownRequested = $false
    Assert-Throws { Switch-KmaoVersion $install '0.2.1' logger } 'startup failure'
    Assert-True ((Read-KmaoState $install).version -eq '0.2.0' -and $startedVersion -eq '0.2.0' -and $shutdownRequested) 'Startup failure did not restore/restart the previous version.'
    Assert-True ((Get-Content $personal) -eq 'preserve-me') 'Personal configuration was changed.'
    Assert-True (!(Test-Path (Join-Path $install 'pending.json'))) 'Activation journal remained after recovery.'
    # An interrupted worker is recovered by the real stable dispatcher on next startup.
    Copy-Item (Join-Path $repo 'Start-Kmao.ps1') (Join-Path $install 'Start-Kmao.ps1')
    Set-Content (Join-Path $install 'versions/0.2.0/Launch-Kmao.ps1') 'param($InstallRoot,$Component,[switch]$SkipUpdateCheck,[switch]$Rollback,$HealthToken); Set-Content (Join-Path $InstallRoot recovered.txt) $Component'
    Write-KmaoState $install current '0.2.1'
    Write-KmaoState $install pending '0.2.0'
    & (Join-Path $install 'Start-Kmao.ps1') -Component logger
    Assert-True ((Read-KmaoState $install).version -eq '0.2.0' -and (Get-Content (Join-Path $install recovered.txt)) -eq 'logger') 'Dispatcher did not recover interrupted activation.'
    Write-Host 'PASS: signed build, signature/key/hash checks, extraction, channel selection, offline/refusal, activation and rollback.'
}
finally {
    if ($null -ne $rsa) { $rsa.Dispose() }
    Remove-Item -LiteralPath $temporary -Recurse -Force
}
