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
#ifdef Authenticode
SignTool=kmao
SignedUninstaller=yes
SignedUninstallerDir={#OutputDir}\signed-uninstaller
#endif

[Files]
Source: "{#SourceDir}\Start-Kmao.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\update-public-key.xml"; DestDir: "{app}"; Flags: onlyifdoesntexist
Source: "{#SourceDir}\current.json"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\versions\{#AppVersion}\*"; DestDir: "{app}\versions\{#AppVersion}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\KMAO Bot\KMAO Bot"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File ""{app}\Start-Kmao.ps1"" -Component bot"; WorkingDir: "{app}"; AppUserModelID: "Kmao.Bot"; Comment: "Iniciar KMAO Bot"
Name: "{autoprograms}\KMAO Bot\KMAO Bot - Gravar atividade"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\Start-Kmao.ps1"" -Component logger"; WorkingDir: "{app}"; AppUserModelID: "Kmao.Logger"; Comment: "KMAO Bot - gravar atividade"
Name: "{autoprograms}\KMAO Bot\KMAO Bot - Restaurar versao anterior"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\Start-Kmao.ps1"" -Rollback"; WorkingDir: "{app}"; AppUserModelID: "Kmao.Rollback"
Name: "{autoprograms}\KMAO Bot\Desinstalar KMAO Bot"; Filename: "{uninstallexe}"

[InstallDelete]
; Remove only the legacy shortcuts owned by KMAO when reinstalling/upgrading.
Type: files; Name: "{autoprograms}\KMAO Bot\Iniciar bot.lnk"
Type: files; Name: "{autoprograms}\KMAO Bot\Gravar atividade.lnk"
Type: files; Name: "{autoprograms}\KMAO Bot\Restaurar versao anterior.lnk"
Type: files; Name: "{autoprograms}\KMAO Bot\Desinstalar.lnk"

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
      if not CopyFile(ExpandConstant('{app}\current.json'), ExpandConstant('{app}\previous.json'), False) then
        RaiseException('Could not preserve the previous installation state.');
  if CurStep = ssPostInstall then
    DeleteFile(ExpandConstant('{app}\pending.json'));
end;
