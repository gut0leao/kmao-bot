# Native process identity and embedded PowerShell behavior; no Notepad or real bot session.
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT' -or $PSVersionTable.PSEdition -ne 'Desktop') { Write-Host 'SKIP: native bot host requires Windows PowerShell 5.1.'; return }
$repo = [IO.Path]::GetFullPath((Resolve-Path (Join-Path $PSScriptRoot '..')).ProviderPath)
. (Join-Path $repo 'scripts/Kmao.Authenticode.ps1')
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('kmao-host-test-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory (Join-Path $temporary 'host') -Force | Out-Null
try {
    Copy-Item -LiteralPath (Join-Path $repo 'host/Kmao.Bot.cs') -Destination (Join-Path $temporary 'host')
    Copy-Item -LiteralPath (Join-Path $repo 'VERSION') -Destination $temporary
    New-Item -ItemType Directory (Join-Path $temporary 'lib') | Out-Null
    foreach ($name in @('Kmao.Windows.cs', 'Kmao.Desktop.cs', 'Kmao.Notepad.cs')) { Copy-Item -LiteralPath (Join-Path $repo "lib/$name") -Destination (Join-Path $temporary 'lib') }
    New-KmaoBotHost $temporary
    $exe = Join-Path $temporary 'Kmao.Bot.exe'
    $info = [Diagnostics.FileVersionInfo]::GetVersionInfo($exe)
    $version = [IO.File]::ReadAllText((Join-Path $repo 'VERSION')).Trim()
    if ($info.FileDescription -ne 'KMAO Bot' -or $info.ProductName -ne 'KMAO Bot' -or $info.FileVersion -ne "$version.0") { throw 'Native host has incorrect Windows product metadata.' }
    @'
param($HealthToken, $ProfileDirectory)
$ErrorActionPreference = 'Stop'
Write-Host 'host-output-fixture'
Write-Warning 'host-warning-fixture'
try {
    @{ Process = [Diagnostics.Process]::GetCurrentProcess().ProcessName; HostName = $Host.Name; Edition = $PSVersionTable.PSEdition; Apartment = [Threading.Thread]::CurrentThread.ApartmentState.ToString(); TrayAssembly = [Kmao.TrayController].Assembly.Location; InputAssembly = [Kmao.WindowsInput].Assembly.Location } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $ProfileDirectory 'result.json')
    exit 7
}
finally { Set-Content -LiteralPath (Join-Path $ProfileDirectory 'cleanup.txt') -Value 'cleaned' }
'@ | Set-Content -LiteralPath (Join-Path $temporary 'dev.ps1') -Encoding UTF8
    $arguments = '-ProfileDirectory "{0}" -HealthToken {1}' -f $temporary, [Guid]::NewGuid().ToString('N')
    $worker = Start-Process $exe -ArgumentList $arguments -PassThru -Wait -RedirectStandardOutput (Join-Path $temporary 'stdout.txt') -RedirectStandardError (Join-Path $temporary 'stderr.txt')
    try { if ($worker.ExitCode -ne 7) { throw ("Native host lost script exit code: $($worker.ExitCode). " + [IO.File]::ReadAllText((Join-Path $temporary 'stderr.txt'))) } } finally { $worker.Dispose() }
    $result = Get-Content -LiteralPath (Join-Path $temporary 'result.json') -Raw | ConvertFrom-Json
    if ($result.Process -ne 'Kmao.Bot' -or $result.HostName -ne 'KMAO Bot' -or $result.Edition -ne 'Desktop' -or $result.Apartment -ne 'STA') { throw 'Bot was not hosted inside the native STA process with Windows PowerShell.' }
    if ($result.TrayAssembly -ne $exe -or $result.InputAssembly -ne $exe) { throw 'Native host did not embed the tray and automation code.' }
    if (!(Test-Path -LiteralPath (Join-Path $temporary 'cleanup.txt'))) { throw 'Script exit skipped finally cleanup.' }
    if ([IO.File]::ReadAllText((Join-Path $temporary 'stdout.txt')) -notmatch 'host-output-fixture') { throw 'Host output was not supported.' }
    'param($HealthToken, $ProfileDirectory); throw "host-failure-fixture"' | Set-Content -LiteralPath (Join-Path $temporary 'dev.ps1') -Encoding UTF8
    $worker = Start-Process $exe -ArgumentList $arguments -PassThru -Wait -RedirectStandardError (Join-Path $temporary 'failure.txt')
    try { if ($worker.ExitCode -ne 1) { throw 'Script failure was not propagated.' } } finally { $worker.Dispose() }
    $logs = @(Get-ChildItem -LiteralPath (Join-Path $temporary '.kmao-bot/logs') -Filter 'host-*.log')
    if (!$logs.Count -or [IO.File]::ReadAllText($logs[0].FullName) -notmatch 'host-failure-fixture') { throw 'Host failure did not create a diagnostic log.' }
    # Exercise the production launcher's native branch without spawning another
    # bot or touching the user's profile. Updates remain before this handoff.
    $tokens = $null; $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'Launch-Kmao.ps1'), [ref]$tokens, [ref]$errors)
    $body = $ast.EndBlock.Statements | Where-Object { $_ -is [Management.Automation.Language.TryStatementAst] }
    $launcherRoot = $temporary
    $entry = [scriptblock]::Create($body.Extent.Text.Replace('$PSScriptRoot', '$launcherRoot'))
    $script:launchCapture = $null
    function Initialize-Kmao { param($Component) }
    function Start-Process {
        param($FilePath, $ArgumentList, [switch]$Wait, [switch]$PassThru)
        $script:launchCapture = @{ File = $FilePath; Arguments = $ArgumentList; Wait = $Wait.IsPresent; PassThru = $PassThru.IsPresent }
        $process = [pscustomobject]@{ ExitCode = 0 }
        $process | Add-Member -MemberType ScriptMethod -Name Dispose -Value { }
        return $process
    }
    $InstallRoot = $null; $SkipUpdateCheck = $true; $Rollback = $false; $Component = 'bot'; $HealthToken = [Guid]::NewGuid().ToString('N')
    $workspace = $null; $handedOff = $false
    . $entry
    if ($launchCapture.File -ne $exe -or !$launchCapture.Wait -or !$launchCapture.PassThru -or $launchCapture.Arguments -notcontains $HealthToken) { throw 'Launcher lost the native process wait or updater health token.' }
    Write-Host 'PASS: KMAO Bot executable metadata, native process identity, embedded PowerShell STA, output, exit/finally cleanup and failure logs.'
}
finally { Remove-Item -LiteralPath $temporary -Recurse -Force }
