# Receives absolute Windows/UNC paths from kmao.sh and runs in Windows PowerShell.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateSet('doctor', 'test', 'keygen', 'build', 'export')][string]$Action,
    [Parameter(Mandatory = $true)][string]$RepositoryPath,
    [string]$PrivateKeyPath,
    [string]$PublicKeyPath,
    [string]$OutputDirectory,
    [string]$IsccPath,
    [switch]$SkipInstaller
)
$ErrorActionPreference = 'Stop'
try {
    if ($env:OS -ne 'Windows_NT') { throw 'This bridge must be executed by powershell.exe from Windows, not Linux pwsh.' }
    $RepositoryPath = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $RepositoryPath).ProviderPath)
    Set-Location -LiteralPath $RepositoryPath
    . (Join-Path $RepositoryPath 'scripts/Kmao.BuildTools.ps1')
    if (!$PrivateKeyPath) { $PrivateKeyPath = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.kmao-signing/private.xml' }
    if (!$PublicKeyPath) { $PublicKeyPath = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.kmao-signing/public.xml' }
    switch ($Action) {
        doctor {
            Write-Host "Windows PowerShell: $($PSVersionTable.PSVersion)"
            Write-Host "Repository: $RepositoryPath"
            try { Write-Host "Inno Setup: $(Resolve-KmaoIscc $IsccPath)" }
            catch { Write-Warning $_.Exception.Message }
        }
        test {
            & (Join-Path $RepositoryPath 'tests/Test-Core.ps1')
            & (Join-Path $RepositoryPath 'tests/Test-Updates.ps1')
            & (Join-Path $RepositoryPath 'tests/Test-Lifecycle.ps1')
            & (Join-Path $RepositoryPath 'tests/Test-WslBuild.ps1')
        }
        keygen {
            # Windows ACL protection is not available for files on the WSL filesystem.
            if ($PrivateKeyPath.StartsWith('\\')) { throw 'Generate signing keys on a Windows drive (/mnt/c/...) or use the default Windows profile location.' }
            & (Join-Path $RepositoryPath 'scripts/New-KmaoSigningKey.ps1') -PrivateKeyPath $PrivateKeyPath -PublicKeyPath $PublicKeyPath
        }
        build {
            if (!$OutputDirectory) { $OutputDirectory = Join-Path $RepositoryPath 'dist/release' }
            & (Join-Path $RepositoryPath 'scripts/Build-KmaoRelease.ps1') -PrivateKeyPath $PrivateKeyPath -PublicKeyPath $PublicKeyPath -OutputDirectory $OutputDirectory -IsccPath $IsccPath -SkipInstaller:$SkipInstaller
        }
        export {
            if (!$OutputDirectory) { $OutputDirectory = Join-Path $RepositoryPath 'dist/kmao-portable' }
            & (Join-Path $RepositoryPath 'Export-Kmao.ps1') -Destination $OutputDirectory
        }
    }
}
catch { Write-Error -ErrorRecord $_ -ErrorAction Continue; exit 1 }
