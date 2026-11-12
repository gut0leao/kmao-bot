[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$InstallRoot,
    [ValidateSet('bot', 'logger')][string]$Component = 'bot',
    [string]$Workspace,
    [switch]$Rollback
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib/Kmao.Common.ps1')
. (Join-Path $PSScriptRoot 'lib/Kmao.Update.ps1')
$gate = $null; $locked = $false; $staging = $null; $activationAttempted = $false; $cleanupWorkspace = $null
try {
    Initialize-Kmao updater
    if ($Workspace) {
        $updatesRoot = [IO.Path]::GetFullPath((Join-Path $KmaoRoot 'updates')) + [IO.Path]::DirectorySeparatorChar
        $Workspace = [IO.Path]::GetFullPath($Workspace)
        if (!$Workspace.StartsWith($updatesRoot, [StringComparison]::OrdinalIgnoreCase) -or (Split-Path -Leaf $Workspace) -notmatch '^[a-f0-9]{32}$') {
            $Workspace = $null
            throw 'Invalid update workspace.'
        }
        $cleanupWorkspace = $Workspace
    }
    $gate = Get-KmaoUpdateMutex
    try { $locked = $gate.WaitOne(0) } catch [Threading.AbandonedMutexException] { $locked = $true }
    if (!$locked) { throw 'Another KMAO update is in progress.' }
    if (Test-KmaoInstallerRunning) { throw 'KMAO installer is running. Update postponed.' }
    if ($Rollback) {
        $targetVersion = (Read-KmaoState $InstallRoot previous).version
    }
    else {
        # Revalidate in the worker; no launcher-provided object is trusted as executable content.
        $manifest = Read-KmaoSignedManifest (Join-Path $Workspace 'manifest.json') (Join-Path $Workspace 'manifest.sig') (Join-Path $InstallRoot 'update-public-key.xml')
        $targetVersion = $manifest.version
        if ((ConvertTo-KmaoVersion $targetVersion) -le (ConvertTo-KmaoVersion (Read-KmaoState $InstallRoot).version)) { throw 'This update is already installed or is older than the installed version.' }
        $archive = Join-Path $Workspace $manifest.asset
        Receive-KmaoFile (Get-Content -LiteralPath (Join-Path $Workspace 'download-url.txt') -Raw).Trim() $archive
        $staging = Join-Path $InstallRoot ('versions/.staging-' + [Guid]::NewGuid().ToString('N'))
        Expand-KmaoVerifiedPackage $archive $manifest $staging
        $destination = Join-Path $InstallRoot "versions/$targetVersion"
        if (Test-Path -LiteralPath $destination) {
            # A previous failed activation may have left this version installed. Never reuse
            # unverified leftovers: compare every file against the newly authenticated payload.
            $leftovers = @(Get-ChildItem -LiteralPath $destination -File -Recurse)
            if ($leftovers.Count -ne @($manifest.files.PSObject.Properties).Count) { throw 'Existing target version is inconsistent. Remove it manually after inspection.' }
            foreach ($property in $manifest.files.PSObject.Properties) {
                if ((Get-FileHash -LiteralPath (Join-Path $destination $property.Name) -Algorithm SHA256).Hash -ine $property.Value) { throw 'Existing target version was modified.' }
            }
        }
        else { Move-Item -LiteralPath $staging -Destination $destination; $staging = $null }
    }
    if ($targetVersion -ceq (Read-KmaoState $InstallRoot).version) { throw 'The requested version is already active.' }
    Stop-KmaoComponents
    $activationAttempted = $true
    Switch-KmaoVersion $InstallRoot $targetVersion $Component
}
catch {
    if ($script:KmaoLogFile) { Write-KmaoLog ERROR $_.Exception.ToString() }
    Write-Error -ErrorRecord $_ -ErrorAction Continue
    if ($locked -and !$activationAttempted) {
        # A failed download or refused package must not prevent using the installed version.
        $componentMutex = [Threading.Mutex]::new($false, "Local\Kmao.Component.$Component")
        $available = $false
        try {
            try { $available = $componentMutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $available = $true }
            if ($available) { $componentMutex.ReleaseMutex() }
        } finally { $componentMutex.Dispose() }
        if ($available) {
            try { Start-KmaoValidatedComponent $InstallRoot $Component }
            catch { Write-KmaoLog ERROR "Current version could not start: $($_.Exception.Message)" }
        }
    }
    exit 1
}
finally {
    if ($staging -and (Test-Path -LiteralPath $staging)) { Remove-Item -LiteralPath $staging -Recurse -Force }
    if ($cleanupWorkspace -and (Test-Path -LiteralPath $cleanupWorkspace)) { Remove-Item -LiteralPath $cleanupWorkspace -Recurse -Force }
    if ($locked) { $gate.ReleaseMutex() }
    if ($null -ne $gate) { $gate.Dispose() }
}
