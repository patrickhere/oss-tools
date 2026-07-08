@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM Maintained by Patrick Hart - hartforge.dev
REM Last Updated: 10/20/2020 (layout and logging updated 11/21/2025)
REM This script is for the sole use of Navanta employees.

echo Setting variables and changing directory to Backups folder...
for /f "delims=" %%A in ('hostname') do set "hostname=%%A"

set "SCRIPT_DIR=%~dp0"
set "ROOT_DIR=%SCRIPT_DIR%..\"
set "ASSETS_DIR=%ROOT_DIR%assets\"
set "BIN_DIR=%ASSETS_DIR%bin\"
set "TXT_DIR=%ASSETS_DIR%txt\"

pushd "%ROOT_DIR%" >nul 2>&1 || (
    echo [ERROR] Unable to access root directory: %ROOT_DIR%
    pause
    goto end
)

if not exist "Backups" mkdir "Backups"
pushd "Backups" >nul 2>&1 || (
    echo [ERROR] Unable to access Backups directory.
    pause
    goto end
)

if not exist "%hostname%" mkdir "%hostname%"
set "LOG_PATH=%CD%\%hostname%\backuplog.txt"
> "%LOG_PATH%" echo Backup (Hirens) started %date% %time%
call :log "Hostname detected as %hostname%"
cls

echo Please specify the drive where Windows is. This is usually C.
echo If nothing is specified, C drive will be selected.
set /p drive="Drive (e.g. C): "
IF "%drive%"=="" set drive=C
call :log "Windows drive selected: %drive%"
echo.
:userselection
echo Please input user to back up.
set /p user="User:"

IF "%user%"=="" goto nouser

:belarc
call :log "Preparing Belarc Advisor assets..."
if not exist "%SYSTEMDRIVE%\BankOnIT" mkdir "%SYSTEMDRIVE%\BankOnIT"
if exist "%SYSTEMDRIVE%\BankOnIT\Belarc Advisor" (
    call :log "Belarc Advisor already installed under %SYSTEMDRIVE%\BankOnIT\Belarc Advisor"
) else (
    call :log "Belarc Advisor not found. Deploying installer from %BIN_DIR%advisorinstaller.exe"
    mkdir "%SYSTEMDRIVE%\BankOnIT\Belarc Advisor" 2>nul
    if exist "%BIN_DIR%advisorinstaller.exe" (
        copy "%BIN_DIR%advisorinstaller.exe" "%SYSTEMDRIVE%\BankOnIT\Belarc Advisor\" >nul
    ) else (
        call :log "WARNING: Belarc advisorinstaller.exe missing at %BIN_DIR%advisorinstaller.exe"
    )
    if exist "%BIN_DIR%Start_Belarc.ps1" (
        powershell -ExecutionPolicy Bypass -File "%BIN_DIR%Start_Belarc.ps1" >> "%LOG_PATH%" 2>&1
    ) else (
        call :log "WARNING: Start_Belarc.ps1 missing at %BIN_DIR%Start_Belarc.ps1"
    )
)

call :log "Attempting to copy Belarc report HTML..."
if exist "%PROGRAMFILES%\Belarc\BelarcAdvisor\System\tmp\(%hostname%).html" (
    copy "%PROGRAMFILES%\Belarc\BelarcAdvisor\System\tmp\(%hostname%).html" "%hostname%\%hostname%.html" >nul
    call :log "Belarc report copied from Program Files."
)
if exist "%PROGRAMFILES(X86)%\Belarc\BelarcAdvisor\System\tmp\(%hostname%).html" (
    copy "%PROGRAMFILES(X86)%\Belarc\BelarcAdvisor\System\tmp\(%hostname%).html" "%hostname%\%hostname%.html" >nul
    call :log "Belarc report copied from Program Files (x86)."
)

REM choice /M "Skip backing up anything on local drive? This is useful when the local drive is unreadable."
REM set skipdrive=%ERRORLEVEL%

REM if skipdrive EQU 1 goto backup
REM if skipdrive EQU 2 goto ipconfig

:backup
REM echo Copying user office information (Outlook signatures, etc)...
REM xcopy "%drive%:\Users\%user%\AppData\Roaming\Microsoft\Office\*.*" "%hostname%\%user%\AppData\Roaming\Microsoft\Office\" /C /E /I /Y >> "%hostname%\backuplog.txt"
REM xcopy "%drive%:\Users\%user%\AppData\Roaming\Microsoft\Signatures\*.*" "%hostname%\%user%\AppData\Roaming\Microsoft\Signatures\" /C /E /I /Y >> "%hostname%\backuplog.txt"
REM xcopy "%drive%:\Users\%user%\AppData\Roaming\Microsoft\Outlook\*.*" "%hostname%\%user%\AppData\Roaming\Microsoft\Outlook\" /C /E /I /Y >> "%hostname%\backuplog.txt"
REM xcopy "%drive%:\Users\%user%\AppData\Roaming\Microsoft\Templates\*.*" "%hostname%\%user%\AppData\Roaming\Microsoft\Templates\" /C /E /I /Y >> "%hostname%\backuplog.txt"
REM xcopy "%drive%:\Users\%user%\AppData\Local\Microsoft\Outlook\*.*" "%hostname%\%user%\AppData\Local\Microsoft\Outlook\" /C /E /I /Y >> "%hostname%\backuplog.txt"

REM echo Copying user FireFox Profile...
REM xcopy "%drive%:\Users\%user%\AppData\Roaming\Mozilla\Firefox\Profiles\*.*" "%hostname%\%user%\AppData\Roaming\Mozilla\Firefox\Profiles" /C /E /I /Y >> "%hostname%\backuplog.txt"

REM echo Copying user Chrome Information...
REM xcopy "%drive%:\Users\%user%\AppData\Local\Google\Chrome\*.*" "%hostname%\%user%\AppData\Local\Google\Chrome\" /C /E /I /Y /EXCLUDE:%~dp0\backup_exclude_chrome.txt >> "%hostname%\backuplog.txt"

echo Copying Public Desktop...
call :log "Copying Public Desktop from %drive%: to backup."
if exist "%TXT_DIR%backup_exclude.txt" (
    xcopy "%drive%:\Users\Public\Desktop\*.*" "%hostname%\Public\Desktop" /C /E /I /Y /EXCLUDE:"%TXT_DIR%backup_exclude.txt" >> "%LOG_PATH%" 2>&1
) else (
    call :log "WARNING: backup_exclude.txt missing at %TXT_DIR%backup_exclude.txt. Copying without exclusions."
    xcopy "%drive%:\Users\Public\Desktop\*.*" "%hostname%\Public\Desktop" /C /E /I /Y >> "%LOG_PATH%" 2>&1
)

echo Starting Transwiz...
call :log "Launching Transwiz from %BIN_DIR%Transwiz_free.exe"
if exist "%BIN_DIR%Transwiz_free.exe" (
    "%BIN_DIR%Transwiz_free.exe" >> "%LOG_PATH%" 2>&1
) else (
    call :log "ERROR: Transwiz_free.exe missing at %BIN_DIR%Transwiz_free.exe"
)

:ipconfig
echo Running ipconfig /all and saving output to ipconfig.txt...
call :log "Capturing ipconfig /all output..."
ipconfig /all > "%hostname%\ipconfig.txt"

echo.

echo Please input the old name of the computer.
echo NOTE: This is only for identification purposes. Hirens names the computer a random name so it might be hard to identify which computer this backup came from.
echo This is not mandatory however. If you would like to keep the hostname the one Hirens assigned, just leave the field blank.
echo WARNING: If you are running the script twice to backup more than 1 profile, leave the name the same until the last profile is backed up!
echo.
set oldhostname=%hostname%
set /p hostname="Hostname of Old Computer:"
IF "%hostname%"=="" for /f "delims=" %%A in ('hostname') do set "hostname=%%A"
echo Old Hostname: %oldhostname%
echo New Hostname: %hostname%
rename "%oldhostname%" "%hostname%"
rename "%hostname%\%oldhostname%.html" "%hostname%.html"

echo.
echo Copying Restore batch files...
if exist "%ASSETS_DIR%IGNORE.bat" (
    copy "%ASSETS_DIR%IGNORE.bat" "%hostname%\Restore (run as admin).bat" >nul
) else (
    call :log "WARNING: IGNORE.bat (restore template) missing at %ASSETS_DIR%IGNORE.bat"
)

if exist "%TXT_DIR%IGNORE.txt" (
    copy "%TXT_DIR%IGNORE.txt" "%hostname%\restore_exclude.txt" >nul
) else (
    call :log "WARNING: IGNORE.txt (restore_exclude template) missing at %TXT_DIR%IGNORE.txt"
    type nul > "%hostname%\restore_exclude.txt"
)
echo %user%.trans.zip>> "%hostname%\restore_exclude.txt"
mkdir "%hostname%\Do Not Restore" 2>nul
echo Copying Transwiz.exe...
if exist "%BIN_DIR%Transwiz_free.exe" (
    copy "%BIN_DIR%Transwiz_free.exe" "%hostname%\Transwiz.exe" >nul
) else (
    call :log "WARNING: Transwiz_free.exe missing; cannot copy to backup folder."
)

call :log "Backup (Hirens) completed for user %user% on hostname %hostname%"
echo Backup completed. Log is saved at: Backups\%hostname%\backuplog.txt
echo Use %hostname%\restore_exclude.txt to specify files/folders that you do not want restored automatically.
echo e.g you copied a program folder into the backup directory that this script uses.
echo You can also put them into the Do Not Restore directory as well.

:end
pause
endlocal
exit /b 0

:nouser
echo No user specified. Please input a user and try again.
pause
cls
goto userselection

:nodrive
echo.
exit /b 0

:log
set "MESSAGE=%~1"
set "STAMP=%date% %time%"
echo [%STAMP%] %MESSAGE%
>> "%LOG_PATH%" echo [%STAMP%] %MESSAGE%
exit /b 0