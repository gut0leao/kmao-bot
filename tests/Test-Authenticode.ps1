# No trust-store changes or private keys. Real signature validation needs the issuer.
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Resolve-Path (Join-Path $PSScriptRoot '..')).ProviderPath)
. (Join-Path $repo 'scripts/Kmao.Authenticode.ps1')
. (Join-Path $repo 'scripts/Kmao.BuildTools.ps1')
function Assert-Throws {
    param([scriptblock]$Action, [string]$Pattern)
    try { & $Action } catch { if ($_.Exception.ToString() -notmatch $Pattern) { throw }; return }
    throw "Expected failure matching: $Pattern"
}
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('kmao-authenticode-' + [Guid]::NewGuid().ToString('N'))
try {
    $output = Join-Path $temporary 'release'
    Assert-Throws { & (Join-Path $repo 'scripts/Build-KmaoRelease.ps1') -PrivateKeyPath missing -PublicKeyPath missing -OutputDirectory $output -SkipInstaller } 'trusted Authenticode signer is required'
    if (Test-Path -LiteralPath $output) { throw 'Unsigned release refusal created output.' }
    Assert-Throws { & (Join-Path $repo 'scripts/Build-KmaoRelease.ps1') -PrivateKeyPath missing -PublicKeyPath missing -OutputDirectory $output -SkipInstaller -AllowUnsigned -AuthenticodeSigner fake } 'mutually exclusive'
    # Feed signature metadata through the real policy validator. These fixtures
    # test policy rejection only, never claim a certificate is publicly trusted.
    $signatureFixture = [pscustomobject]@{ Status = 'NotSigned'; StatusMessage = 'fixture'; SignerCertificate = $null; TimeStamperCertificate = $null }
    function Get-AuthenticodeSignature { param($LiteralPath) return $signatureFixture }
    Assert-Throws { Assert-KmaoAuthenticodeSignature 'fixture.ps1' } 'verification failed'
    $oids = [Security.Cryptography.OidCollection]::new()
    $oids.Add([Security.Cryptography.Oid]::new('1.3.6.1.5.5.7.3.3')) | Out-Null
    $extension = [Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]::new($oids, $false)
    $signatureFixture.Status = 'Valid'
    $signatureFixture.SignerCertificate = [pscustomobject]@{ Extensions = @($extension) }
    Assert-Throws { Assert-KmaoAuthenticodeSignature 'fixture.ps1' } 'no trusted timestamp'
    $signatureFixture.TimeStamperCertificate = 'fixture'
    Assert-KmaoAuthenticodeSignature 'fixture.ps1'
    $signatureFixture.SignerCertificate = [pscustomobject]@{ Extensions = @() }
    Assert-Throws { Assert-KmaoAuthenticodeSignature 'fixture.ps1' } 'no explicit Code Signing'
    $signatureFixture.Status = 'HashMismatch'
    Assert-Throws { Assert-KmaoAuthenticodeSignature 'fixture.ps1' } 'verification failed'
    if ($env:OS -eq 'Windows_NT' -and $PSVersionTable.PSEdition -eq 'Desktop') {
        $payload = Join-Path $temporary 'payload'
        New-Item -ItemType Directory (Join-Path $payload 'lib') -Force | Out-Null
        foreach ($name in @('Kmao.Windows.cs', 'Kmao.Desktop.cs', 'Kmao.Notepad.cs', 'Kmao.Common.ps1')) {
            Copy-Item -LiteralPath (Join-Path $repo "lib/$name") -Destination (Join-Path $payload 'lib')
        }
        New-KmaoCompiledRuntime $payload
        Get-ChildItem -LiteralPath (Join-Path $payload 'lib') -Filter '*.cs' | Remove-Item
        $worker = Join-Path $temporary 'load-runtime.ps1'
        @'
param($Payload)
$ErrorActionPreference = 'Stop'
. (Join-Path $Payload 'lib/Kmao.Common.ps1')
Import-KmaoDesktop
$expected = Join-Path $Payload 'lib/Kmao.Runtime.dll'
if ([Kmao.WindowsInput].Assembly.Location -ne $expected -or [Kmao.OwnedNotepad].Assembly.Location -ne $expected -or [Kmao.TrayController].Assembly.Location -ne $expected) { throw 'Runtime was not loaded from the precompiled DLL.' }
'@ | Set-Content -LiteralPath $worker -Encoding UTF8
        & (Join-Path $PSHOME 'powershell.exe') -NoProfile -ExecutionPolicy Bypass -File $worker -Payload $payload
        if ($LASTEXITCODE -ne 0) { throw 'Precompiled runtime load failed.' }
        # A callback returning success without a real signature must not pass.
        $provider = Join-Path $temporary 'noop-provider.ps1'
        'param($Path); exit 0' | Set-Content -LiteralPath $provider
        $arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Path "{1}" -SignerScript "{2}"' -f (Join-Path $repo 'scripts/Invoke-KmaoAuthenticode.ps1'), (Join-Path $payload 'lib/Kmao.Runtime.dll'), $provider
        $rejected = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden -RedirectStandardError (Join-Path $temporary 'rejected.err') -RedirectStandardOutput (Join-Path $temporary 'rejected.out')
        try { if ($rejected.ExitCode -eq 0) { throw 'Unsigned provider output was accepted.' } }
        finally { $rejected.Dispose() }
        $command = Get-KmaoInnoSignCommand 'C:\sign folder\provider$test.ps1'
        if (!$command.Contains('provider$$test.ps1') -or !$command.EndsWith('-Path $f')) { throw 'Inno signing command does not preserve literal paths or the file placeholder.' }
        $compiler = $null
        try { $compiler = Resolve-KmaoIscc } catch { }
        if ($compiler) {
            'param($Path); [IO.File]::WriteAllText((Join-Path $PSScriptRoot "callback.invoked"), "called"); exit 0' | Set-Content -LiteralPath $provider
            $probe = Join-Path $temporary 'signing-probe.iss'
            @'
[Setup]
AppName=KMAO Signature Test
AppVersion=0.0.0
DefaultDirName={tmp}\KmaoSignatureTest
PrivilegesRequired=lowest
OutputBaseFilename=signature-test
SignTool=kmao
SignToolRetryCount=0
SignedUninstaller=yes
'@ | Set-Content -LiteralPath $probe -Encoding UTF8
            $compilerArguments = @(('/O' + $temporary), ('/Skmao=' + (Get-KmaoInnoSignCommand $provider)), $probe)
            # Expected rejection by the actual compiler; no installer is launched.
            $savedPreference = $ErrorActionPreference
            try {
                $ErrorActionPreference = 'Continue'
                & $compiler @compilerArguments > (Join-Path $temporary 'compiler.log') 2>&1
                $compileExit = $LASTEXITCODE
            }
            finally { $ErrorActionPreference = $savedPreference }
            if ($compileExit -eq 0 -or !(Test-Path -LiteralPath (Join-Path $temporary 'callback.invoked'))) {
                throw ('Inno signing callback was not invoked/rejected correctly: ' + [IO.File]::ReadAllText((Join-Path $temporary 'compiler.log')))
            }
            Write-Host 'PASS: Inno Setup invokes the signing wrapper and rejects an unsigned uninstaller; no installer was run.'
        }
        Write-Host 'PASS: precompiled Windows runtime loads without C# sources; signing callback rejects unsigned output.'
    }
    Write-Host 'PASS: release refuses unsigned output by default; Authenticode policy rejects missing/invalid signatures, missing code EKU and timestamps.'
}
finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Recurse -Force } }
