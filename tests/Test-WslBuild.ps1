# Exercise Windows cryptography/ZIP/.NET I/O with output on the WSL UNC filesystem.
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).ProviderPath)
if ($env:OS -ne 'Windows_NT' -or !$repo.StartsWith('\\')) {
    Write-Host 'SKIP: UNC build regression requires Windows PowerShell accessing a WSL checkout.'
    return
}
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('kmao-wsl-build-' + [Guid]::NewGuid().ToString('N'))
$output = Join-Path $repo ('dist/wsl-build-test-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temporary | Out-Null
try {
    $private = Join-Path $temporary 'private.xml'
    $public = Join-Path $temporary 'public.xml'
    & (Join-Path $repo 'scripts/New-KmaoSigningKey.ps1') -PrivateKeyPath $private -PublicKeyPath $public
    . (Join-Path $repo 'scripts/Kmao.BuildTools.ps1')
    $compiler = $null
    try { $compiler = Resolve-KmaoIscc }
    catch { Write-Host 'SKIP: installer compilation (Inno Setup not installed); testing signed ZIP only.' }
    & (Join-Path $repo 'scripts/Invoke-KmaoFromWsl.ps1') -Action build -RepositoryPath $repo -PrivateKeyPath $private -PublicKeyPath $public -OutputDirectory $output -IsccPath $compiler -SkipInstaller:(!$compiler)
    $manifestPath = Join-Path $output 'kmao-manifest.json'
    . (Join-Path $repo 'lib/Kmao.Update.ps1')
    $manifest = Read-KmaoSignedManifest $manifestPath (Join-Path $output 'kmao-manifest.sig') $public
    if (!(Test-Path -LiteralPath (Join-Path $output $manifest.asset))) { throw 'Signed package was not created on the WSL filesystem.' }
    if ($compiler) {
        if (!(Test-Path -LiteralPath (Join-Path $output "kmao-setup-$($manifest.version).exe"))) { throw 'Installer was not compiled.' }
        Write-Host 'PASS: Inno Setup compiles the Windows installer directly from the WSL checkout.'
    }
    Write-Host 'PASS: signed Windows build writes valid artifacts directly to the WSL repository.'
}
finally {
    Remove-Item -LiteralPath $temporary -Recurse -Force
    if (Test-Path -LiteralPath $output) { Remove-Item -LiteralPath $output -Recurse -Force }
}
