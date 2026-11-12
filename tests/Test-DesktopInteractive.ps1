# Explicit interactive test: creates its own Notepad; never types into an unrelated app.
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'This test requires the interactive Windows desktop.' }
$repo = [IO.Path]::GetFullPath((Resolve-Path (Join-Path $PSScriptRoot '..')).ProviderPath)
. (Join-Path $repo 'lib/Kmao.Common.ps1')
Import-KmaoDesktop
$note = $null
try {
    $note = [Kmao.OwnedNotepad]::new()
    if (!$note.IsOpen) { throw 'Owned Notepad did not open.' }
    $root = [Windows.Automation.AutomationElement]::FromHandle($note.Window)
    $windowPattern = $root.GetCurrentPattern([Windows.Automation.WindowPattern]::Pattern)
    if ($windowPattern.Current.WindowVisualState -ne [Windows.Automation.WindowVisualState]::Maximized) { throw 'Owned Notepad was not maximized.' }
    $document = $root.FindFirst([Windows.Automation.TreeScope]::Descendants,
        [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::ControlTypeProperty, [Windows.Automation.ControlType]::Document))
    if ($null -eq $document) {
        $document = $root.FindFirst([Windows.Automation.TreeScope]::Descendants,
            [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::ControlTypeProperty, [Windows.Automation.ControlType]::Edit))
    }
    $pattern = $null
    if (!$document.TryGetCurrentPattern([Windows.Automation.TextPattern]::Pattern, [ref]$pattern)) { throw 'Owned Notepad text cannot be verified.' }
    $text = $pattern.DocumentRange.GetText(-1)
    if ($text -notmatch '^KMAO BOT running\.\.\.') { throw 'Initial message was not written into the owned Notepad.' }
    $unicode = 'a' + [char]0x00E7 + [char]0x00E3 + 'o ' + [char]::ConvertFromUtf32(0x1F916)
    $note.AppendText('Scoped Unicode test: + ^ % { } ' + $unicode)
    $text = $pattern.DocumentRange.GetText(-1)
    if ($text -notmatch 'Scoped Unicode test: \+ \^ % \{ \}' -or !$text.Contains($unicode)) { throw 'Scoped Unicode typing failed.' }
    $bounds = $note.EditorBounds
    if ($bounds[2] -lt 1 -or $bounds[3] -lt 1) { throw 'Owned editor bounds are invalid.' }
    $note.MaximizeAndActivate()
    Start-Sleep -Milliseconds 100
    if (!$note.IsEditorPoint(($bounds[0] + [int]($bounds[2] / 2)), ($bounds[1] + [int]($bounds[3] / 2)))) { throw 'Owned editor hit test rejected its own visible center.' }
    $note.ClickEditor(($bounds[0] + [int]($bounds[2] / 2)), ($bounds[1] + [int]($bounds[3] / 2)))
    $note.Dispose()
    Write-Host 'PASS: isolated maximized Notepad, initial message, scoped text and discard without saving.'
}
finally { if ($null -ne $note) { $note.Dispose() } }
