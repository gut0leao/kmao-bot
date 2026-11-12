function Resolve-KmaoIscc {
    param([string]$Path)
    if ($Path) {
        if (!(Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Inno Setup compiler not found: $Path" }
        return (Resolve-Path -LiteralPath $Path).ProviderPath
    }
    $command = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    foreach ($base in @(${env:ProgramFiles(x86)}, $env:ProgramFiles, $env:LOCALAPPDATA)) {
        if (!$base) { continue }
        foreach ($relative in @('Inno Setup 6/ISCC.exe', 'Programs/Inno Setup 6/ISCC.exe')) {
            $candidate = Join-Path $base $relative
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
        }
    }
    throw 'Inno Setup 6 was not found in Windows. Install it or specify --iscc /mnt/c/.../ISCC.exe when using WSL.'
}

function New-KmaoRsaKey {
    # .NET Framework's RSACryptoServiceProvider exposes KeySize as read-only.
    if ($env:OS -eq 'Windows_NT') {
        $key = [Security.Cryptography.RSACryptoServiceProvider]::new(3072)
        $key.PersistKeyInCsp = $false
    }
    else {
        $key = [Security.Cryptography.RSA]::Create()
        $key.KeySize = 3072
    }
    return $key
}
