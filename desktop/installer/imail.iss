#define MyAppName "iMail"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "!THUTE Solutions"
#define MyAppExeName "iMail.exe"

[Setup]
AppId={{F05C7F78-A139-4AD6-A87C-90ED8671F0B7}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\iMail
DefaultGroupName=iMail
DisableProgramGroupPage=yes
OutputDir=..\artifacts\installer
OutputBaseFilename=iMail-Setup-x64
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayName=iMail

[Files]
Source: "..\artifacts\win-x64\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\iMail"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\iMail"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch iMail"; Flags: nowait postinstall skipifsilent
