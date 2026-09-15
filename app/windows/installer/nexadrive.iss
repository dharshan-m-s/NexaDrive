; NexaDrive — Inno Setup installer script.
;
; Build from the repository root:
;   "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" /DMyAppVersion=1.1.0 app\windows\installer\nexadrive.iss
;
; All paths are relative to this file (app/windows/installer).

#ifndef MyAppVersion
  #define MyAppVersion "1.1.0"
#endif

#define MyAppName "NexaDrive"
#define MyAppPublisher "NexaDrive Project"
#define MyAppExeName "nexadrive.exe"
#define MyAppSourceDir "..\..\build\windows\x64\runner\Release"
#define MyAppOutputDir "..\..\..\dist"
#define MyAppIcon "..\..\runner\resources\app_icon.ico"

[Setup]
AppId={{3F4E2A5B-1C2D-4E6F-9A8B-7C6D5E4F3A2B}}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
OutputDir={#MyAppOutputDir}
OutputBaseFilename=NexaDrive-{#MyAppVersion}-windows-x64-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
SetupIconFile={#MyAppIcon}
UninstallDisplayIcon={app}\{#MyAppExeName}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#MyAppSourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{userdesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent