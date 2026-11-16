#include "Common.iss"

[Setup]
AppId={{C2C9FDFF-B378-437D-8F67-96D323E73797}
AppName=Ekravio Server (Prototype)
DefaultDirName={autopf}\Ekravio\Server
DefaultGroupName=Ekravio Server
PrivilegesRequired=admin
MinVersion=10.0.17763
OutputBaseFilename=Ekravio-Server-Setup-x64

[Files]
Source: "{#StageDir}\server\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#StageDir}\ekravio.ico"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\Ekravio Server - Configure and start"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy RemoteSigned -File ""{app}\Server-Manager.ps1"""; WorkingDir: "{app}"; IconFilename: "{app}\ekravio.ico"
Name: "{group}\Ekravio Server - Live (localhost)"; Filename: "http://127.0.0.1:8889/stage0/"; IconFilename: "{app}\ekravio.ico"
Name: "{group}\Ekravio Server - Instructions"; Filename: "{app}\Instructions.txt"

[Code]
function ManagePreviousService(const Action: String): Boolean;
var
  ExitCode: Integer;
  Script: String;
begin
  Result := True;
  if not RegKeyExists(HKLM, 'SYSTEM\CurrentControlSet\Services\Ekravio.Media') then
    Exit;
  Script := ExpandConstant('{app}\Server-Manager.ps1');
  if not FileExists(Script) then
  begin
    Result := False;
    Exit;
  end;
  Result := Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
    '-NoProfile -NonInteractive -ExecutionPolicy RemoteSigned -File "' + Script + '" -Action ' + Action,
    ExpandConstant('{app}'), SW_HIDE, ewWaitUntilTerminated, ExitCode) and (ExitCode = 0);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';
  if not ManagePreviousService('Stop') then
    Result := 'Ekravio.Media could not be stopped. Check the installed service path and retry.';
end;

function InitializeUninstall(): Boolean;
begin
  Result := ManagePreviousService('Remove');
  if not Result then
    SuppressibleMsgBox('Ekravio.Media could not be removed. Check the installed service path and retry.', mbError, MB_OK, IDOK);
end;
