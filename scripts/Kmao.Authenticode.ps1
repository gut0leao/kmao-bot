# Build-time Authenticode support. Never import roots or change Windows protection.
function Assert-KmaoAuthenticodeSignature {
    param([Parameter(Mandatory = $true)][string]$Path)
    $signature = Get-AuthenticodeSignature -LiteralPath $Path -ErrorAction Stop
    if ($signature.Status -ne 'Valid' -or !$signature.SignerCertificate) {
        throw "Authenticode verification failed for $Path ($($signature.Status)): $($signature.StatusMessage)"
    }
    $extension = $signature.SignerCertificate.Extensions | Where-Object { $_.Oid.Value -eq '2.5.29.37' }
    $codeSigning = $false
    if ($extension) {
        $eku = [Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]::new()
        $eku.CopyFrom($extension)
        $codeSigning = @($eku.EnhancedKeyUsages | Where-Object { $_.Value -eq '1.3.6.1.5.5.7.3.3' }).Count -gt 0
    }
    if (!$codeSigning) { throw "Authenticode signer has no explicit Code Signing EKU: $Path" }
    if (!$signature.TimeStamperCertificate) { throw "Authenticode signature has no trusted timestamp: $Path" }
}

function Invoke-KmaoAuthenticodeSigner {
    param([string]$Path, [string]$SignerScript)
    # A separate Windows PowerShell process gives local/token/cloud providers the
    # same contract and prevents a callback's exit from terminating the builder.
    & (Join-Path $PSHOME 'powershell.exe') -NoLogo -NoProfile -ExecutionPolicy Bypass -File $SignerScript -Path $Path | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "Authenticode provider failed for $Path (exit $LASTEXITCODE)." }
    Assert-KmaoAuthenticodeSignature $Path
}

function New-KmaoCompiledRuntime {
    param([string]$Payload)
    if ($env:OS -ne 'Windows_NT' -or $PSVersionTable.PSEdition -ne 'Desktop') {
        throw 'Compiling the release runtime requires Windows PowerShell 5.1. Use ./scripts/kmao.sh build from WSL.'
    }
    foreach ($assembly in @('System.Windows.Forms', 'System.Drawing', 'UIAutomationClient', 'UIAutomationTypes', 'WindowsBase')) {
        Add-Type -AssemblyName $assembly
    }
    $references = @('System.dll', 'System.Core.dll',
        [System.Windows.Forms.Application].Assembly.Location,
        [System.Drawing.Bitmap].Assembly.Location,
        [System.Windows.Automation.AutomationElement].Assembly.Location,
        [System.Windows.Automation.ControlType].Assembly.Location,
        [System.Windows.Threading.Dispatcher].Assembly.Location) | Select-Object -Unique
    $sources = @('Kmao.Windows.cs', 'Kmao.Desktop.cs', 'Kmao.Notepad.cs') | ForEach-Object { Join-Path $Payload "lib/$_" }
    Add-Type -Path $sources -ReferencedAssemblies $references -OutputAssembly (Join-Path $Payload 'lib/Kmao.Runtime.dll') -OutputType Library -ErrorAction Stop
}

function New-KmaoBotHost {
    param([string]$Payload)
    if ($env:OS -ne 'Windows_NT' -or $PSVersionTable.PSEdition -ne 'Desktop') { throw 'Compiling the bot host requires Windows PowerShell 5.1.' }
    $version = [IO.File]::ReadAllText((Join-Path $Payload 'VERSION')).Trim()
    if ($version -notmatch '^\d+\.\d+\.\d+$') { throw 'Invalid host version.' }
    foreach ($assembly in @('System.Windows.Forms', 'System.Drawing', 'UIAutomationClient', 'UIAutomationTypes', 'WindowsBase')) { Add-Type -AssemblyName $assembly }
    $metadata = Join-Path ([IO.Path]::GetTempPath()) ('kmao-host-version-' + [Guid]::NewGuid().ToString('N') + '.cs')
    try {
        [IO.File]::WriteAllText($metadata, ('[assembly:System.Reflection.AssemblyVersion("{0}.0")][assembly:System.Reflection.AssemblyFileVersion("{0}.0")]' -f $version))
        $references = @('System.dll', 'System.Core.dll', [Management.Automation.PowerShell].Assembly.Location,
            [System.Windows.Forms.Application].Assembly.Location, [System.Drawing.Bitmap].Assembly.Location,
            [System.Windows.Automation.AutomationElement].Assembly.Location, [System.Windows.Automation.ControlType].Assembly.Location,
            [System.Windows.Threading.Dispatcher].Assembly.Location) | Select-Object -Unique
        # The native app owns its UI/automation types. The separate runtime DLL
        # remains for the logger and direct PowerShell development entry points.
        $sources = @((Join-Path $Payload 'host/Kmao.Bot.cs'), $metadata)
        foreach ($name in @('Kmao.Windows.cs', 'Kmao.Desktop.cs', 'Kmao.Notepad.cs')) { $sources += Join-Path $Payload "lib/$name" }
        Add-Type -Path $sources -ReferencedAssemblies $references -OutputAssembly (Join-Path $Payload 'Kmao.Bot.exe') -OutputType WindowsApplication -ErrorAction Stop
        [IO.File]::WriteAllText((Join-Path $Payload 'Kmao.Bot.exe.config'), '<?xml version="1.0"?><configuration><startup useLegacyV2RuntimeActivationPolicy="true"><supportedRuntime version="v4.0" sku=".NETFramework,Version=v4.6"/></startup></configuration>')
    }
    finally { Remove-Item -LiteralPath $metadata -Force }
}

function Get-KmaoInnoSignCommand {
    param([string]$SignerScript)
    # Inno expands $q to a quote and $f to the quoted file name. Escape literal
    # dollar signs in paths; never interpolate the file name into PowerShell code.
    $powershell = (Join-Path $PSHOME 'powershell.exe').Replace('$', '$$')
    $callback = (Join-Path $PSScriptRoot 'Invoke-KmaoAuthenticode.ps1').Replace('$', '$$')
    $provider = $SignerScript.Replace('$', '$$')
    return ('$q{0}$q -NoLogo -NoProfile -ExecutionPolicy Bypass -File $q{1}$q -SignerScript $q{2}$q -Path $f' -f $powershell, $callback, $provider)
}
