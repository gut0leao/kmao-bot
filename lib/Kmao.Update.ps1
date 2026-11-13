# Update protocol 1. All downloaded executable content is authenticated before extraction.
function ConvertTo-KmaoVersion {
    param([string]$Value)
    if ($Value -notmatch '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$') { throw "Invalid version: $Value" }
    return [version]$Value
}

function Read-KmaoState {
    param([string]$InstallRoot, [ValidateSet('current', 'previous', 'pending')][string]$Name = 'current')
    $state = Get-Content -LiteralPath (Join-Path $InstallRoot "$Name.json") -Raw -ErrorAction Stop | ConvertFrom-Json
    ConvertTo-KmaoVersion $state.version | Out-Null
    return $state
}

function Write-KmaoState {
    param([string]$InstallRoot, [ValidateSet('current', 'previous', 'pending')][string]$Name, [string]$Version)
    ConvertTo-KmaoVersion $Version | Out-Null
    $target = Join-Path $InstallRoot "$Name.json"
    $temporary = "$target.$([Guid]::NewGuid().ToString('N')).tmp"
    try {
        [IO.File]::WriteAllText($temporary, (@{ version = $Version } | ConvertTo-Json -Compress), [Text.UTF8Encoding]::new($false))
        if (Test-Path -LiteralPath $target) { [IO.File]::Replace($temporary, $target, [NullString]::Value) }
        else { [IO.File]::Move($temporary, $target) }
    }
    finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force } }
}

function Read-KmaoSignedManifest {
    param([string]$ManifestPath, [string]$SignaturePath, [string]$PublicKeyPath)
    $rsa = [Security.Cryptography.RSA]::Create()
    try {
        $rsa.FromXmlString([IO.File]::ReadAllText($PublicKeyPath))
        if ($rsa.KeySize -lt 3072) { throw 'Update signing key must have at least 3072 bits.' }
        $data = [IO.File]::ReadAllBytes($ManifestPath)
        if ($data.Length -gt 262144) { throw 'Update manifest exceeds size limit.' }
        $signature = [Convert]::FromBase64String([IO.File]::ReadAllText($SignaturePath).Trim())
        if (!$rsa.VerifyData($data, $signature, [Security.Cryptography.HashAlgorithmName]::SHA256, [Security.Cryptography.RSASignaturePadding]::Pkcs1)) {
            throw 'Invalid update signature. The package will not be executed.'
        }
    } finally { $rsa.Dispose() }
    $manifest = [Text.Encoding]::UTF8.GetString($data) | ConvertFrom-Json
    ConvertTo-KmaoVersion $manifest.version | Out-Null
    if ($manifest.protocol -ne 1 -or $manifest.channel -ne 'testing' -or $manifest.configurationSchema -ne 1) {
        throw 'Incompatible update protocol, channel or configuration schema. Use a compatible installer.'
    }
    if ($manifest.asset -cne "kmao-$($manifest.version).zip" -or $manifest.sha256 -notmatch '^[a-fA-F0-9]{64}$') { throw 'Invalid update asset metadata.' }
    if (!$manifest.files -or @($manifest.files.PSObject.Properties).Count -gt 1000) { throw 'Invalid update file list.' }
    return $manifest
}

function Expand-KmaoVerifiedPackage {
    param([string]$ArchivePath, $Manifest, [string]$Destination)
    if ((Get-FileHash -LiteralPath $ArchivePath -Algorithm SHA256).Hash -ine $Manifest.sha256) { throw 'Package SHA256 does not match signed manifest.' }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($ArchivePath)
    $expected = @{}
    foreach ($property in $Manifest.files.PSObject.Properties) {
        $name = $property.Name
        if ($name -notmatch '^[a-zA-Z0-9_./-]+$' -or $name -match '(^/|(^|/)\.\.?(/|$))' -or $expected.ContainsKey($name) -or $property.Value -notmatch '^[a-fA-F0-9]{64}$') {
            $zip.Dispose(); throw 'Unsafe or duplicate manifest file path.'
        }
        $expected[$name] = $property.Value
    }
    try {
        if (Test-Path -LiteralPath $Destination) { throw 'Extraction destination already exists.' }
        New-Item -ItemType Directory -Path $Destination | Out-Null
        $seen = @{}; $total = 0L
        foreach ($entry in $zip.Entries) {
            $name = $entry.FullName.Replace('\', '/')
            if ($name.EndsWith('/')) { continue }
            if (!$expected.ContainsKey($name) -or $seen.ContainsKey($name) -or (($entry.ExternalAttributes -shr 16) -band 0xF000) -eq 0xA000) { throw 'Unexpected, duplicate or symbolic-link entry in package.' }
            $total += $entry.Length
            if ($total -gt 134217728) { throw 'Expanded package exceeds 128 MiB.' }
            $target = Join-Path $Destination $name
            New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $target, $false)
            if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ine $expected[$name]) { throw "File hash mismatch: $name" }
            $seen[$name] = $true
        }
        if ($seen.Count -ne $expected.Count) { throw 'Incomplete update package.' }
        foreach ($required in @('VERSION', 'Launch-Kmao.ps1', 'Apply-KmaoUpdate.ps1', 'dev.ps1', 'activity_logger.ps1', 'lib/Kmao.Common.ps1', 'lib/Kmao.Update.ps1', 'lib/Kmao.Windows.cs', 'config/bot.conf.example', 'config/kmao.conf.example', 'phrases.txt')) {
            if (!$seen.ContainsKey($required)) { throw "Required package file is missing: $required" }
        }
        if ((Get-Content -LiteralPath (Join-Path $Destination 'VERSION') -Raw).Trim() -cne $Manifest.version) { throw 'Package version differs from manifest.' }
        # Syntax errors must not become the active installation.
        foreach ($file in Get-ChildItem -LiteralPath $Destination -Recurse -Filter '*.ps1') {
            $tokens = $null; $errors = $null
            [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors) | Out-Null
            if ($errors) { throw "Package contains invalid PowerShell: $($file.Name)" }
        }
    } finally { $zip.Dispose() }
}

function Get-KmaoAssetUrl {
    param($Release, [string]$Name)
    $assets = @($Release.assets | Where-Object { $_.name -ceq $Name })
    if ($assets.Count -ne 1) { throw "Missing or duplicate release asset: $Name" }
    $url = [string]$assets[0].browser_download_url
    $prefix = 'https://github.com/gut0leao/kmao-bot/releases/download/' + [Uri]::EscapeDataString([string]$Release.tag_name) + '/'
    if ($url -cne ($prefix + [Uri]::EscapeDataString($Name))) { throw 'Unexpected release download origin.' }
    return $url
}

function Receive-KmaoFile {
    param([string]$Url, [string]$Destination)
    if (!$Url.StartsWith('https://github.com/gut0leao/kmao-bot/releases/download/', [StringComparison]::Ordinal)) { throw 'Untrusted download URL.' }
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $Destination -TimeoutSec 30 -MaximumRedirection 5 -Headers @{ 'User-Agent' = 'KMAO-Bot' } -ErrorAction Stop | Out-Null
    if ((Get-Item -LiteralPath $Destination).Length -gt 67108864) { throw 'Download exceeds 64 MiB.' }
}

function Get-KmaoUpdateOffer {
    param([string]$InstallRoot, [string]$Workspace)
    $current = Read-KmaoState $InstallRoot
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    # Explicit prerelease selection: GitHub's /latest endpoint excludes prereleases.
    # In Windows PowerShell 5.1, Invoke-RestMethod emits a JSON array as one
    # pipeline object. Capture the response first so @() enumerates its elements,
    # rather than wrapping that array inside another array and filtering it as one release.
    $response = Invoke-RestMethod -Uri 'https://api.github.com/repos/gut0leao/kmao-bot/releases?per_page=100' -TimeoutSec 8 -Headers @{ 'User-Agent' = 'KMAO-Bot'; Accept = 'application/vnd.github+json' } -ErrorAction Stop
    $releases = @($response)
    $candidates = @($releases | Where-Object { !$_.draft -and $_.prerelease -and $_.tag_name -match '^v\d+\.\d+\.\d+$' -and (ConvertTo-KmaoVersion $_.tag_name.Substring(1)) -gt (ConvertTo-KmaoVersion $current.version) } | Sort-Object { ConvertTo-KmaoVersion $_.tag_name.Substring(1) } -Descending)
    foreach ($release in $candidates) {
        $manifestPath = Join-Path $Workspace 'manifest.json'
        $signaturePath = Join-Path $Workspace 'manifest.sig'
        Receive-KmaoFile (Get-KmaoAssetUrl $release 'kmao-manifest.json') $manifestPath
        Receive-KmaoFile (Get-KmaoAssetUrl $release 'kmao-manifest.sig') $signaturePath
        $manifest = Read-KmaoSignedManifest $manifestPath $signaturePath (Join-Path $InstallRoot 'update-public-key.xml')
        if ($release.tag_name -cne "v$($manifest.version)") { throw 'Release tag does not match signed version.' }
        return @{ Manifest = $manifest; Url = (Get-KmaoAssetUrl $release $manifest.asset); Workspace = $Workspace }
    }
    return $null
}

function Stop-KmaoComponents {
    param([int]$TimeoutSeconds = 20)
    foreach ($component in @('bot', 'logger')) {
        try {
            $stop = [Threading.EventWaitHandle]::OpenExisting("Local\Kmao.Stop.$component")
            try { $stop.Set() | Out-Null } finally { $stop.Dispose() }
        } catch [Threading.WaitHandleCannotBeOpenedException] { }
    }
    $timer = [Diagnostics.Stopwatch]::StartNew()
    foreach ($component in @('bot', 'logger')) {
        $mutex = [Threading.Mutex]::new($false, "Local\Kmao.Component.$component")
        $locked = $false
        try {
            $remaining = [int][Math]::Max(0, $TimeoutSeconds * 1000 - $timer.ElapsedMilliseconds)
            try { $locked = $mutex.WaitOne($remaining) } catch [Threading.AbandonedMutexException] { $locked = $true }
            if (!$locked) { throw "KMAO $component did not finish cleanup. Update postponed; no process was killed." }
        } finally { if ($locked) { $mutex.ReleaseMutex() }; $mutex.Dispose() }
    }
}

function Start-KmaoInstalledComponent {
    param([string]$InstallRoot, [string]$Component, [string]$HealthToken)
    if ($InstallRoot.Contains('"')) { throw 'Invalid installation path.' }
    $arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Component {1} -SkipUpdateCheck' -f (Join-Path $InstallRoot 'Start-Kmao.ps1'), $Component
    if ($Component -eq 'bot') { $arguments = '-STA -WindowStyle Hidden ' + $arguments }
    if ($HealthToken) { $arguments += ' -HealthToken ' + $HealthToken }
    return Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $arguments -PassThru
}

function Start-KmaoValidatedComponent {
    param([string]$InstallRoot, [string]$Component)
    $token = [Guid]::NewGuid().ToString('N')
    $health = [Threading.EventWaitHandle]::new($false, [Threading.EventResetMode]::ManualReset, "Local\Kmao.Health.$token")
    try {
        $process = Start-KmaoInstalledComponent $InstallRoot $Component $token
        $timer = [Diagnostics.Stopwatch]::StartNew()
        while (!$health.WaitOne(100)) {
            if ($process.HasExited -or $timer.Elapsed.TotalSeconds -ge 30) { throw 'Version failed startup validation.' }
        }
        if ($process.HasExited) { throw 'Component exited during startup validation.' }
    } finally { $health.Dispose() }
}

function Switch-KmaoVersion {
    param([string]$InstallRoot, [string]$Version, [string]$Component)
    ConvertTo-KmaoVersion $Version | Out-Null
    $old = (Read-KmaoState $InstallRoot).version
    if (!(Test-Path -LiteralPath (Join-Path $InstallRoot "versions/$Version/Launch-Kmao.ps1"))) { throw 'Target version is not installed.' }
    Write-KmaoState $InstallRoot previous $old
    Write-KmaoState $InstallRoot pending $old
    Write-KmaoState $InstallRoot current $Version
    try {
        Start-KmaoValidatedComponent $InstallRoot $Component
        Remove-Item -LiteralPath (Join-Path $InstallRoot 'pending.json') -Force
        Write-KmaoLog INFO "Version $Version started successfully; previous version: $old"
    }
    catch {
        $startupError = $_
        # Do not change the pointer while a failed new instance still owns a session.
        Stop-KmaoComponents
        Write-KmaoState $InstallRoot current $old
        Remove-Item -LiteralPath (Join-Path $InstallRoot 'pending.json') -Force -ErrorAction SilentlyContinue
        Write-KmaoLog ERROR "Activation failed; restored version $old. $($startupError.Exception.Message)"
        try { Start-KmaoValidatedComponent $InstallRoot $Component }
        catch { Write-KmaoLog ERROR "Previous version is restored but could not start: $($_.Exception.Message)" }
        throw $startupError
    }
}

function Confirm-KmaoUpdate {
    param([string]$Question)
    Add-Type -AssemblyName System.Windows.Forms
    return ([System.Windows.Forms.MessageBox]::Show($Question, 'KMAO Bot - update', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question) -eq [System.Windows.Forms.DialogResult]::Yes)
}
