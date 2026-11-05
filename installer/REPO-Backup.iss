; Установщик R.E.P.O. Backup (Inno Setup 6).
; Сборка: ISCC.exe installer\REPO-Backup.iss  ->  dist\REPO-Backup-Setup.exe
; Версию можно передать снаружи: ISCC.exe /DAppVersion=1.2.0 installer\REPO-Backup.iss

#ifndef AppVersion
  #define AppVersion "1.4.0"
#endif

[Setup]
AppId={{6F2B7C41-3E8A-4D5B-9C1E-7A2F4B8D9E10}
AppName=R.E.P.O. Backup
AppVersion={#AppVersion}
AppVerName=R.E.P.O. Backup {#AppVersion}
AppPublisher=TiSkill
AppPublisherURL=https://github.com/TiSkill/repo-backup
AppSupportURL=https://github.com/TiSkill/repo-backup/issues
AppUpdatesURL=https://github.com/TiSkill/repo-backup/releases
; ставим только для текущего пользователя: права администратора не нужны,
; а папка программы доступна для записи (в ней хранятся копии сейвов)
PrivilegesRequired=lowest
DefaultDirName={localappdata}\Programs\REPO Backup
DisableProgramGroupPage=yes
DisableDirPage=auto
SetupIconFile=..\icon.ico
UninstallDisplayIcon={app}\icon.ico
UninstallDisplayName=R.E.P.O. Backup
OutputDir=..\dist
OutputBaseFilename=REPO-Backup-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=no

[Languages]
Name: "ru"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\REPO_Backup.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\REPO Backup.vbs"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\icon.ico"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\README.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\LICENSE"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
; ярлык в «Пуске» — по нему программа находится в поиске Windows.
; AppUserModelID совпадает с тем, что выставляет сама программа: закреп на панели задач работает правильно
Name: "{autoprograms}\R.E.P.O. Backup"; Filename: "{sys}\wscript.exe"; Parameters: """{app}\REPO Backup.vbs"""; WorkingDir: "{app}"; IconFilename: "{app}\icon.ico"; Comment: "Бэкапы сейвов R.E.P.O."; AppUserModelID: "TiSkill.REPOBackup"
Name: "{autodesktop}\R.E.P.O. Backup"; Filename: "{sys}\wscript.exe"; Parameters: """{app}\REPO Backup.vbs"""; WorkingDir: "{app}"; IconFilename: "{app}\icon.ico"; AppUserModelID: "TiSkill.REPOBackup"; Tasks: desktopicon

[UninstallDelete]
; настройки создаёт сама программа, установщик о них не знает
Type: files; Name: "{app}\settings.json"

[Run]
; без skipifsilent: после тихого обновления из программы она запускается снова
Filename: "{sys}\wscript.exe"; Parameters: """{app}\REPO Backup.vbs"""; Description: "{cm:LaunchProgram,R.E.P.O. Backup}"; Flags: postinstall nowait

[Code]
// Закрывает запущенную программу (она работает как powershell.exe с REPO_Backup.ps1).
procedure StopApp();
var Code: Integer;
begin
  Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
    '-NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name=''powershell.exe''\" | ' +
    'Where-Object CommandLine -like ''*REPO_Backup.ps1*'' | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }"',
    '', SW_HIDE, ewWaitUntilTerminated, Code);
end;

// при обновлении закрываем старую версию, чтобы после установки запустилась новая
function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  StopApp();
  Result := '';
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var Saves: String;
begin
  if CurUninstallStep = usUninstall then
    StopApp();
  if CurUninstallStep = usPostUninstall then
  begin
    // копии сейвов — данные пользователя: удаляем только с его согласия
    Saves := ExpandConstant('{app}\saves');
    if DirExists(Saves) then
      if UninstallSilent or (MsgBox('Удалить и сохранённые копии сейвов R.E.P.O.?' + #13#10#13#10 +
          'Если нажать «Нет», они останутся в папке:' + #13#10 + Saves,
          mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDNO) then
        Exit
      else
        DelTree(ExpandConstant('{app}'), True, True, True);
  end;
end;
