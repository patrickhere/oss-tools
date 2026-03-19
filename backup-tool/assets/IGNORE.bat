@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM Author: redacted
REM Contact: redacted@example.com
REM Last Updated: 8/17/2020
REM This script is for the sole use of BankOnIT employees.

call :ensureAdmin || goto end

:variables
echo Setting variables...
for /f "delims=" %%A in ('hostname') do set "hostname=%%A"
pushd "%~dp0"
for %%I in ("%~dp0.") do set old=%%~nI

:newcomputer
echo Creating New_Computer.txt...
echo %hostname% > New_Computer.txt

:backup
echo Creating backup of Public Desktop folder (%old%\Backup (New Computer)\Public\Desktop)
mkdir "Backup (New Computer)"
xcopy "%SYSTEMDRIVE%\Users\Public\Desktop\*.*" "Backup (New Computer)\Public\Desktop" /C /E /I /Y

:profile
echo Restoring User Profiles back to system...
echo Running Transwiz.exe
Transwiz.exe
if not exist Logs mkdir Logs
REM Only restore the Public subfolder -- restoring *.* from the backup root would
REM put logs, HTML reports, and restore scripts into C:\Users.
if exist "Public" (
    xcopy "Public\*.*" "%SYSTEMDRIVE%\Users\Public" /C /E /I /Y /EXCLUDE:restore_exclude.txt >> Logs\restorelog.txt
)
copy Logs\restorelog.txt %SYSTEMDRIVE%\BankOnIT\restorelog.txt 2>nul

REM echo Now getting moving outlook profile for one user to Documents\Outlook Files.
REM echo If this doesn't need to be done, or no one has outlook, just press enter.
REM set /p user="User:"
REM IF "%user%"=="" (goto cleanup) ELSE (goto outlook)
:outlook
REM echo Moving Outlook Data file (if present) to %SYSTEMDRIVE%\Users\%user%.old\Documents...
REM IF EXIST "%SYSTEMDRIVE%\Users\%user%.old\AppData\Local\Outlook" THEN move "%SYSTEMDRIVE%\Users\%user%.old\AppData\Local\Outlook\*.*" "%SYSTEMDRIVE%\Users\%user%.old\Documents\Outlook Files" ELSE echo No Outlook files were found.
REM IF EXIST "%SYSTEMDRIVE%\Users\%user%.old\Documents\Outlook Files\" THEN echo Remember to re-import the PST file after you have run through Outlook setup. (Or just replace it in %LOCALAPPDATA%\Microsoft\Outlook) && timeout /T 5

:browsers
echo Restoring browser bookmarks...
if not exist "Browsers\" (
    echo No browser bookmarks in backup -- skipping.
    goto cleanup
)
for /d %%U in ("Browsers\*") do (
    if exist "%%U\Edge\Bookmarks" (
        md "%SYSTEMDRIVE%\Users\%%~nxU\AppData\Local\Microsoft\Edge\User Data\Default" 2>nul
        copy /Y "%%U\Edge\Bookmarks" "%SYSTEMDRIVE%\Users\%%~nxU\AppData\Local\Microsoft\Edge\User Data\Default\Bookmarks" >nul
        echo Edge bookmarks restored for %%~nxU
    )
    if exist "%%U\Chrome\Bookmarks" (
        md "%SYSTEMDRIVE%\Users\%%~nxU\AppData\Local\Google\Chrome\User Data\Default" 2>nul
        copy /Y "%%U\Chrome\Bookmarks" "%SYSTEMDRIVE%\Users\%%~nxU\AppData\Local\Google\Chrome\User Data\Default\Bookmarks" >nul
        echo Chrome bookmarks restored for %%~nxU
    )
    if exist "%%U\Firefox\places.sqlite" (
        md "%SYSTEMDRIVE%\BankOnIT\Firefox\%%~nxU" 2>nul
        copy /Y "%%U\Firefox\places.sqlite" "%SYSTEMDRIVE%\BankOnIT\Firefox\%%~nxU\places.sqlite" >nul
        echo Firefox bookmarks for %%~nxU copied to %SYSTEMDRIVE%\BankOnIT\Firefox\%%~nxU
        echo   To restore: Firefox ^> Bookmarks ^> Manage Bookmarks ^> Import and Backup ^> Restore
    )
)

:cleanup
echo "Moving Old Computer info to %SYSTEMDRIVE%\BankOnIT\Old Computer..."
pushd %SYSTEMDRIVE%\Users
mkdir "%SYSTEMDRIVE%\BankOnIT\Old Computer"

move "%old%.html" "%SYSTEMDRIVE%\BankOnIT\Old Computer\"
move PrinterList.txt "%SYSTEMDRIVE%\BankOnIT\Old Computer\"
move ipconfig.txt "%SYSTEMDRIVE%\BankOnIT\Old Computer\"

echo Restore completed. Restore log is located at %SYSTEMDRIVE%\BankOnIT\restorelog.txt
echo Old Computer info (Belarc Advisor) is located at %SYSTEMDRIVE%\BankOnIT\Old Computer\%old%.html
echo If mapped drives did not copy over, double-click the registry file MappedDrives.reg in the user's folder. Otherwise, this batch file will move it to the %SYSTEMDRIVE%\BankOnIT\Old Computer folder once you press enter.
pause
move "%user%\MappedDrives.reg" "%SYSTEMDRIVE%\BankOnIT\Old Computer\"
goto end

:ensureAdmin
  fsutil dirty query %systemdrive% >nul 2>&1
  if %errorlevel%==0 (
    echo Running as admin...
  ) else (
    echo Running as non-admin...
    echo Please run as admin...
    pause
    exit /b 1
  )
  exit /b 0

:end