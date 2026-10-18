; Build with Inno Setup 6 after the native Release build.
#ifndef AppVersion
  #define AppVersion "1.0.3"
#endif
#ifndef BinaryDir
  #define BinaryDir "..\build-windows\Release"
#endif
[Setup]
AppId={{D4674B0D-320B-43DA-AEB5-E245D9518F01}
AppName=ARose ScreenSaver
AppVersion={#AppVersion}
AppPublisher=CooLajz
AppPublisherURL=https://github.com/CooLajz/ARose-ScreenSaver
DefaultDirName={autopf}\ARose ScreenSaver
UsePreviousAppDir=no
DefaultGroupName=ARose ScreenSaver
PrivilegesRequired=admin
MinVersion=10.0.22000
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\dist\releases
OutputBaseFilename=ARose-ScreenSaver-v{#AppVersion}-Windows-x64-Setup
UninstallDisplayIcon={app}\ARose.scr
SetupIconFile=ARose.ico
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no
[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "czech"; MessagesFile: "compiler:Languages\Czech.isl"
[Files]
Source: "{#BinaryDir}\ARose.scr"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#BinaryDir}\ARose.scr"; DestDir: "{sys}"; Flags: ignoreversion
Source: "{#BinaryDir}\ARose Control.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#BinaryDir}\WinSparkle.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\LICENSE"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\THIRD_PARTY_NOTICES.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\.build\updaters\WinSparkle-0.9.4\COPYING*"; DestDir: "{app}\Licenses\WinSparkle"; Flags: ignoreversion
[Registry]
Root: HKLM; Subkey: "Software\CooLajz\ARose"; ValueType: string; ValueName: "InstallPath"; ValueData: "{app}"; Flags: uninsdeletevalue
[Icons]
Name: "{group}\ARose"; Filename: "{app}\ARose Control.exe"; IconFilename: "{app}\ARose.scr"
Name: "{group}\ARose Preview"; Filename: "{app}\ARose Control.exe"; Parameters: "/preview"
Name: "{group}\{cm:UninstallProgram,ARose}"; Filename: "{uninstallexe}"
[Run]
Filename: "{app}\ARose Control.exe"; Description: "{cm:LaunchProgram,ARose}"; Flags: nowait postinstall skipifsilent runasoriginaluser
Filename: "{sys}\rundll32.exe"; Parameters: "desk.cpl,InstallScreenSaver ""{sys}\ARose.scr"""; Description: "{cm:SaverSettings}"; Flags: nowait postinstall skipifsilent runasoriginaluser unchecked
[UninstallRun]
Filename: "{app}\ARose Control.exe"; Parameters: "/remove-installed-tasks"; Flags: runhidden waituntilterminated; RunOnceId: "DisableWeekly"
[CustomMessages]
english.SaverSettings=Select ARose in screen saver settings
czech.SaverSettings=Vybrat ARose v nastavení spořiče obrazovky
[Code]
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var Selected: string;
begin
  if CurUninstallStep = usUninstall then
    if RegQueryStringValue(HKCU, 'Control Panel\Desktop', 'SCRNSAVE.EXE', Selected) then
      if (CompareText(Selected, ExpandConstant('{app}\ARose.scr')) = 0) or
         (CompareText(Selected, ExpandConstant('{sys}\ARose.scr')) = 0) then
        RegDeleteValue(HKCU, 'Control Panel\Desktop', 'SCRNSAVE.EXE');
end;
