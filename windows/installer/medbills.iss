; MedBills Windows installer (Inno Setup 6). Built by .github/workflows/build.yml:
;   ISCC /DAppVersion=1.1.0 windows\installer\medbills.iss
; Installs for the current user (no admin password needed), adds Start menu
; and desktop shortcuts, and bundles the Visual C++ runtime DLLs next to the
; app so it runs on a fresh Windows 10/11 laptop with nothing else installed.

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

[Setup]
AppId={{8F2A6C1E-4B7D-4E3A-9C55-2D1E7A9B3F10}
AppName=MedBills
AppVersion={#AppVersion}
AppVerName=MedBills {#AppVersion}
AppPublisher=MedBills
DefaultDirName={autopf}\MedBills
DefaultGroupName=MedBills
DisableProgramGroupPage=yes
DisableDirPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir=..\..\dist
OutputBaseFilename=MedBills-Setup
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\MedBills.exe
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes

[Tasks]
Name: "desktopicon"; Description: "Put a MedBills icon on the desktop"; GroupDescription: "Shortcuts:"

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\MedBills"; Filename: "{app}\MedBills.exe"
Name: "{autodesktop}\MedBills"; Filename: "{app}\MedBills.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\MedBills.exe"; Description: "Open MedBills now"; Flags: nowait postinstall skipifsilent
