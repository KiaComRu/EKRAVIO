#include "Common.iss"

[Setup]
AppId={{0E810765-F942-4892-9DC2-99458DEBC77A}
AppName=Ekravio Agent (Prototype)
DefaultDirName={localappdata}\Programs\Ekravio\Agent
DefaultGroupName=Ekravio Agent
PrivilegesRequired=lowest
MinVersion=10.0.22000
OutputBaseFilename=Ekravio-Agent-Setup-x64

[Files]
Source: "{#StageDir}\agent\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#StageDir}\ekravio.ico"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\Ekravio Agent - Start capture"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy RemoteSigned -File ""{app}\Agent-Launcher.ps1"""; WorkingDir: "{app}"; IconFilename: "{app}\ekravio.ico"
Name: "{group}\Ekravio Agent - Local DXGI probe"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy RemoteSigned -File ""{app}\Agent-Launcher.ps1"" -ProbeOnly"; WorkingDir: "{app}"; IconFilename: "{app}\ekravio.ico"
Name: "{group}\Ekravio Agent - Input activity probe"; Filename: "{app}\Ekravio.SessionMonitor.exe"; Parameters: "90 60"; WorkingDir: "{app}"; IconFilename: "{app}\ekravio.ico"
Name: "{group}\Ekravio Agent - Instructions"; Filename: "{app}\Instructions.txt"
