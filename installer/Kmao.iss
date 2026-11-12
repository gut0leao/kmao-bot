#ifndef AppVersion
  #error AppVersion is required
#endif
#ifndef SourceDir
  #error SourceDir is required
#endif
#ifndef OutputDir
  #error OutputDir is required
#endif

[Setup]
AppId={{9AF58EA2-57E7-46CF-8435-07B3901F6DAA}
AppName=KMAO Bot
AppVersion={#AppVersion}
AppPublisher=gut0leao
DefaultDirName={localappdata}\Programs\KMAO Bot
PrivilegesRequired=lowest
DisableProgramGroupPage=yes
OutputDir={#OutputDir}
OutputBaseFilename=kmao-setup-{#AppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
MinVersion=10.0
CloseApplications=no
RestartApplications=no
AppMutex=Local\Kmao.Component.bot,Local\Kmao.Component.logger,Local\Kmao.Update
SetupMutex=Local\Kmao.Install
UninstallDisplayName=KMAO Bot
LicenseFile=..\LICENSE

[Files]
Source: "{#SourceDir}\Start-Kmao.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\update-public-key.xml"; DestDir: "{app}"; Flags: onlyifdoesntexist
Source: "{#SourceDir}\current.json"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\versions\{#AppVersion}\*"; DestDir: "{app}\versions\{#AppVersion}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\KMAO Bot\Iniciar bot"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\Start-Kmao.ps1"" -Component bot"; WorkingDir: "{app}"
Name: "{autoprograms}\KMAO Bot\Gravar atividade"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\Start-Kmao.ps1"" -Component logger"; WorkingDir: "{app}"
Name: "{autoprograms}\KMAO Bot\Restaurar versao anterior"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\Start-Kmao.ps1"" -Rollback"; WorkingDir: "{app}"
Name: "{autoprograms}\KMAO Bot\Desinstalar"; Filename: "{uninstallexe}"

[UninstallDelete]
; Versions downloaded after installation are application code, never user data.
Type: filesandordirs; Name: "{app}\versions"
Type: files; Name: "{app}\previous.json"
Type: files; Name: "{app}\pending.json"

[Code]
procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssInstall then
    if FileExists(ExpandConstant('{app}\current.json')) then
      if not FileCopy(ExpandConstant('{app}\current.json'), ExpandConstant('{app}\previous.json'), False) then
        RaiseException('Could not preserve the previous installation state.');
  if CurStep = ssPostInstall then
    DeleteFile(ExpandConstant('{app}\pending.json'));
end;
