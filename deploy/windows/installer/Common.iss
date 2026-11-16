[Setup]
AppVersion=0.1.0
AppPublisher=Ekravio
ArchitecturesAllowed=x64os
ArchitecturesInstallIn64BitMode=x64os
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
SetupIconFile={#StageDir}\ekravio.ico
UninstallDisplayIcon={app}\ekravio.ico
DisableProgramGroupPage=yes
OutputDir={#PackageDir}

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"
