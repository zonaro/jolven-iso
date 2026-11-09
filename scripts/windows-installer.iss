; Inno Setup script for the portable Flutter Windows release bundle.
; Run through scripts/package-windows.ps1 after flutter build windows --release.
#ifndef AppVersion
  #error AppVersion must be supplied with /DAppVersion=...
#endif

[Setup]
AppId=Jolven.ISO.Builder
AppName=Jolven ISO Builder
AppVersion={#AppVersion}
AppPublisher=Jolven
AppPublisherURL=https://github.com/zonaro/jolven-iso
DefaultDirName={localappdata}\Programs\Jolven ISO Builder
DefaultGroupName=Jolven ISO Builder
UninstallDisplayIcon={app}\jolven_iso.exe
OutputBaseFilename=Jolven-ISO-Builder-{#AppVersion}-Windows-x64-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Jolven ISO Builder"; Filename: "{app}\jolven_iso.exe"

[Run]
Filename: "{app}\jolven_iso.exe"; Description: "Abrir Jolven ISO Builder"; Flags: nowait postinstall skipifsilent
