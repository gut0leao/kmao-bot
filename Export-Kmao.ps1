# Build a portable directory and ZIP containing only application files and templates.
[CmdletBinding()]
param(
    [string]$Destination = (Join-Path $PSScriptRoot 'dist/kmao-portable'),
    [switch]$SkipArchive
)
$ErrorActionPreference = 'Stop'

$files = @(
    'host/Kmao.Bot.cs', 'tests/Test-BotHost.ps1', 'tests/Test-BotHostInteractive.ps1',
    'VERSION', 'CHANGELOG.md', 'Start-Kmao.ps1', 'Launch-Kmao.ps1', 'Apply-KmaoUpdate.ps1',
    'lib/Kmao.Update.ps1', 'lib/Kmao.Desktop.cs', 'lib/Kmao.Notepad.cs', 'Show-KmaoLogs.ps1',
    'tests/Test-Desktop.ps1', 'tests/Test-DesktopInteractive.ps1', 'tests/Test-BotDesktopLifecycle.ps1',
    'dev.bat', 'dev.ps1', 'init_recording.bat', 'activity_logger.ps1',
    'lib/Kmao.Common.ps1', 'lib/Kmao.Windows.cs',
    'lib/Kmao.Configuration.ps1', 'config/application.conf.example', 'tests/Test-Configuration.ps1',
    'config/bot.conf.example', 'config/kmao.conf.example', 'phrases.txt',
    'INSTALLATION.md', 'TRAY_BOT.md',
    'scripts/Publish-KmaoRelease.py', 'tests/test_publish_release.py',
    'scripts/kmao.sh', 'scripts/Invoke-KmaoFromWsl.ps1', 'scripts/Kmao.BuildTools.ps1',
    'scripts/Kmao.Authenticode.ps1', 'scripts/Invoke-KmaoAuthenticode.ps1', 'scripts/Sign-KmaoFile.ps1',
    'CODE_SIGNING.md', 'tests/Test-Authenticode.ps1',
    'scripts/New-KmaoSigningKey.ps1', 'scripts/Build-KmaoRelease.ps1', 'installer/Kmao.iss',
    'tests/Test-WslBuild.ps1',
    'tests/Test-Updates.ps1', 'tests/Test-Lifecycle.ps1', 'tests/fixtures/SessionWorker.ps1',
    'README.md', 'ROADMAP.md', 'LICENSE', 'ACTIVITY_LOGGER_SPEC.md', 'Export-Kmao.ps1',
    'tests/Test-Core.ps1', 'tests/Test-Windows.ps1'
)
foreach ($file in $files) {
    if (!(Test-Path -LiteralPath (Join-Path $PSScriptRoot $file) -PathType Leaf)) {
        throw "Package source is incomplete. Missing: $file"
    }
}
$Destination = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Destination)
$archive = "$Destination.zip"
if ((Test-Path -LiteralPath $Destination) -or (Test-Path -LiteralPath $archive)) {
    throw "Destination already exists. Choose a new directory with -Destination: $Destination"
}
New-Item -ItemType Directory -Path $Destination -Force | Out-Null
foreach ($file in $files) {
    $target = Join-Path $Destination $file
    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination $target
}
if (!$SkipArchive) { Compress-Archive -Path (Join-Path $Destination '*') -DestinationPath $archive }
Write-Host "Portable directory: $Destination"
if (!$SkipArchive) { Write-Host "Portable ZIP: $archive" }
Write-Host 'Copy or extract the entire package, preserving the lib and config subdirectories.'
