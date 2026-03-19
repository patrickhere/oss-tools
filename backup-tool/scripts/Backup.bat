@echo off
REM DEPRECATED -- replaced by Backup.ps1. Do not delete (rollback reference).
setlocal EnableExtensions EnableDelayedExpansion

REM ---------------------------------------------------------------------------
REM  BankOnIT Backup Utility (original by redacted, maintained by Patrick Hart)
REM  Contact: patrick.hart@bankonitusa.com
REM  Last Updated: 11/21/2025
REM 
REM  SUMMARY
REM    * Backs up Belarc report, Transwiz package, public desktop, and ipconfig output
REM    * Generates restore assets (batch + exclusions) and copies Transwiz runtime
REM    * Logs execution details to Backups/<hostname>/backuplog.txt
REM 
REM  USAGE
REM    Backup (Run as Admin).bat [backup_destination]
REM      - Optional BACKUP_DEST environment variable overrides default path
REM      - Destination defaults to %SCRIPT_DIR%\Backups when no overrides provided
REM ---------------------------------------------------------------------------

call :ensureAdmin || goto :end

set "SCRIPT_DIR=%~dp0"
if not defined SCRIPT_DIR (
    echo [ERROR] Unable to determine script directory.
    pause
    goto :end
)

pushd "%SCRIPT_DIR%" >nul 2>&1 || (
    echo [ERROR] Unable to access %SCRIPT_DIR%.
    pause
    goto :end
)

for /f "delims=" %%A in ('hostname') do set "COMPUTER_NAME=%%~A"

set "ROOT_DIR=%SCRIPT_DIR%..\"
set "ASSETS_DIR=%ROOT_DIR%assets\"
set "BIN_DIR=%ASSETS_DIR%bin\"
set "TXT_DIR=%ASSETS_DIR%txt\"

set "BACKUP_DEST_ROOT=%~1"
if not defined BACKUP_DEST_ROOT if defined BACKUP_DEST set "BACKUP_DEST_ROOT=%BACKUP_DEST%"
if not defined BACKUP_DEST_ROOT set "BACKUP_DEST_ROOT=%ROOT_DIR%Backups"

echo.
echo Backup destination root:
echo   Current default: %BACKUP_DEST_ROOT%
set "DEST_INPUT="
set /p "DEST_INPUT=Override destination (leave blank to accept default): "
if defined DEST_INPUT set "BACKUP_DEST_ROOT=%DEST_INPUT%"

for %%B in ("%BACKUP_DEST_ROOT%") do set "BACKUP_ROOT=%%~fB"

if not defined BACKUP_ROOT (
    echo [ERROR] Unable to resolve backup destination.
    pause
    goto :end
)

set "HOST_DIR=%BACKUP_ROOT%\%COMPUTER_NAME%"
set "LOG_DIR=%HOST_DIR%\Logs"
set "BANKONIT_ROOT=%SYSTEMDRIVE%\BankOnIT"
set "BELARC_DIR=%BANKONIT_ROOT%\Belarc Advisor"
set "BELARC_INSTALLER=%BIN_DIR%advisorinstaller.exe"
set "BELARC_START=%BIN_DIR%Start_Belarc.ps1"
set "BELARC_EXEC_PRIMARY=%PROGRAMFILES%\Belarc\BelarcAdvisor\BelarcAdvisor.exe"
set "BELARC_EXEC_SECONDARY=%PROGRAMFILES(X86)%\Belarc\BelarcAdvisor\BelarcAdvisor.exe"
set "TRANSWIZ_EXE=%BIN_DIR%Transwiz_free.exe"
set "RESTORE_SCRIPT_SRC=%ASSETS_DIR%IGNORE.bat"
set "RESTORE_EXCLUDE_TEMPLATE=%TXT_DIR%IGNORE.txt"
set "EXCLUDE_FILE=%TXT_DIR%backup_exclude.txt"
set "EXCLUDE_FILE_RESOLVED="
if exist "%EXCLUDE_FILE%" for %%E in ("%EXCLUDE_FILE%") do set "EXCLUDE_FILE_RESOLVED=%%~fE"

call :ensureDir "%BACKUP_ROOT%" || goto :end
call :ensureDir "%HOST_DIR%" || goto :end
call :ensureDir "%LOG_DIR%" || goto :end
call :ensureDir "%BANKONIT_ROOT%" || goto :end

set "LOG_PATH=%HOST_DIR%\backuplog.txt"
> "%LOG_PATH%" echo Backup started %date% %time%
call :log "Backup root set to %BACKUP_ROOT%"
call :log "Initialized backup directories at %HOST_DIR%"

echo.
echo Please input user to back up. If logged in as the current user, leave blank.
set /p "USER_TO_BACKUP=User: "
if not defined USER_TO_BACKUP set "USER_TO_BACKUP=%USERNAME%"
call :log "Backing up profile for user %USER_TO_BACKUP%"

echo.
echo ===== Optional Components =====
echo Press Enter to accept the default value in brackets.
call :promptToggle "Run Belarc Advisor scan and capture report" DO_BELARC 1
call :promptToggle "Launch Transwiz wizard for migration" DO_TRANSWIZ 1
call :promptToggle "Copy Public Desktop contents" DO_PUBLIC_DESKTOP 1
call :promptToggle "Capture ipconfig /all output" DO_IPCONFIG 1

if "%DO_BELARC%"=="1" (
    set "BELARC_REPORT=%HOST_DIR%\%COMPUTER_NAME%.html"
    call :handleBelarc
) else (
    call :log "Skipping Belarc Advisor workflow per technician selection."
)

if "%DO_TRANSWIZ%"=="1" (
    call :runTranswiz
) else (
    call :log "Skipping Transwiz launch per technician selection."
)

if "%DO_IPCONFIG%"=="1" (
    call :log "Capturing network configuration..."
    ipconfig /all > "%HOST_DIR%\ipconfig.txt"
) else (
    call :log "Skipping ipconfig capture per technician selection."
)

set "PUBLIC_DESKTOP=%SYSTEMDRIVE%\Users\Public\Desktop"
if "%DO_PUBLIC_DESKTOP%"=="1" (
    if exist "%PUBLIC_DESKTOP%" (
        call :ensureDir "%HOST_DIR%\Public"
        call :log "Copying Public Desktop..."
        if defined EXCLUDE_FILE_RESOLVED (
            xcopy "%PUBLIC_DESKTOP%\*.*" "%HOST_DIR%\Public\Desktop" /C /E /I /Y /EXCLUDE:"%EXCLUDE_FILE_RESOLVED%" >> "%LOG_PATH%" 2>&1
        ) else (
            call :log "WARNING: Exclude list missing at %EXCLUDE_FILE%. Copying without exclusions."
            xcopy "%PUBLIC_DESKTOP%\*.*" "%HOST_DIR%\Public\Desktop" /C /E /I /Y >> "%LOG_PATH%" 2>&1
        )
    ) else (
        call :log "WARNING: Public desktop path not found at %PUBLIC_DESKTOP%"
    )
) else (
    call :log "Skipping Public Desktop copy per technician selection."
)

call :log "Copying restore assets..."
if exist "%RESTORE_SCRIPT_SRC%" (
    copy "%RESTORE_SCRIPT_SRC%" "%HOST_DIR%\Restore (run as admin).bat" >nul
) else (
    call :log "WARNING: Restore batch template missing at %RESTORE_SCRIPT_SRC%"
)

if exist "%RESTORE_EXCLUDE_TEMPLATE%" (
    copy "%RESTORE_EXCLUDE_TEMPLATE%" "%HOST_DIR%\restore_exclude.txt" >nul
) else (
    call :log "WARNING: Restore exclude template missing at %RESTORE_EXCLUDE_TEMPLATE%"
    type nul > "%HOST_DIR%\restore_exclude.txt"
)

echo %USER_TO_BACKUP%.trans.zip>> "%HOST_DIR%\restore_exclude.txt"
call :ensureDir "%HOST_DIR%\Do Not Restore"

if "%DO_TRANSWIZ%"=="1" (
    if exist "%TRANSWIZ_EXE%" (
        copy "%TRANSWIZ_EXE%" "%HOST_DIR%\Transwiz.exe" >nul
    )
) else (
    call :log "Skipping Transwiz executable copy per technician selection."
)

call :log "Backup artifacts saved to %HOST_DIR%"
call :log "Use restore_exclude.txt or 'Do Not Restore' directory to omit items during restore."

popd >nul 2>&1
call :log "Backup process finished."
call :summarizeLog
goto :end

:log
set "MESSAGE=%~1"
set "STAMP=%date% %time%"
echo [%STAMP%] %MESSAGE%
>> "%LOG_PATH%" echo [%STAMP%] %MESSAGE%
exit /b 0

:summarizeLog
if not exist "%LOG_PATH%" (
    echo.
    echo ===== Backup Summary =====
    echo Log file missing. No summary available.
    exit /b 0
)

set "WARN_COUNT=0"
set "ERROR_COUNT=0"
for /f %%G in ('findstr /i "WARNING" "%LOG_PATH%" ^| find /c /v ""') do set "WARN_COUNT=%%G"
for /f %%G in ('findstr /i "ERROR" "%LOG_PATH%" ^| find /c /v ""') do set "ERROR_COUNT=%%G"

echo.
echo ===== Backup Summary =====
echo Warnings logged : %WARN_COUNT%
echo Errors logged   : %ERROR_COUNT%
if not "%WARN_COUNT%"=="0" echo Review %LOG_PATH% for warning details.
if not "%ERROR_COUNT%"=="0" echo Investigate errors before proceeding.
call :log "Warnings logged: %WARN_COUNT%, Errors logged: %ERROR_COUNT%"
exit /b 0

:promptToggle
set "PROMPT_TEXT=%~1"
set "PROMPT_VAR=%~2"
set "PROMPT_DEFAULT=%~3"
set "PROMPT_VALUE="

if "%PROMPT_DEFAULT%"=="1" (
    set "PROMPT_HINT=Y"
) else (
    set "PROMPT_HINT=N"
)

:promptToggleLoop
set /p "PROMPT_VALUE=%PROMPT_TEXT%? [%PROMPT_HINT%]: "
if "%PROMPT_VALUE%"=="" (
    set "%PROMPT_VAR%=%PROMPT_DEFAULT%"
    goto :promptToggleDone
)

for %%O in (%PROMPT_VALUE%) do set "PROMPT_VALUE=%%~O"
set "PROMPT_VALUE=%PROMPT_VALUE:~0,1%"
set "PROMPT_VALUE=%PROMPT_VALUE:u=U%"
set "PROMPT_VALUE=%PROMPT_VALUE:l=L%"

if /I "%PROMPT_VALUE%"=="Y" (
    set "%PROMPT_VAR%=1"
    goto :promptToggleDone
)
if /I "%PROMPT_VALUE%"=="N" (
    set "%PROMPT_VAR%=0"
    goto :promptToggleDone
)

echo Please respond with Y or N.
goto :promptToggleLoop

:promptToggleDone
if "%PROMPT_VAR%"=="1" (
    call :log "%PROMPT_TEXT%: enabled"
) else (
    call :log "%PROMPT_TEXT%: skipped"
)
exit /b 0

:copyBelarcReport
set "SRC=%~1"
set "DEST=%~2"
set "FLAG_NAME=%~3"
if not defined FLAG_NAME set "FLAG_NAME=BELARC_REPORT_FOUND"

if exist "%SRC%" (
    copy "%SRC%" "%DEST%" >nul
    if errorlevel 1 (
        call :log "WARNING: Failed to copy Belarc report from %SRC%"
    ) else (
        call :log "Belarc report copied from %SRC%"
        call set "%FLAG_NAME%=1"
    )
)
exit /b 0

:handleBelarc
call :log "Preparing Belarc Advisor assets..."
call :ensureDir "%BELARC_DIR%"
if exist "%BELARC_INSTALLER%" (
    copy "%BELARC_INSTALLER%" "%BELARC_DIR%\" >nul
) else (
    call :log "WARNING: Belarc installer missing at %BELARC_INSTALLER%"
)

call :runBelarcScan

call :log "Searching for Belarc reports..."
set "BELARC_REPORT_FOUND=0"
for %%B in (
    "%PROGRAMFILES%\Belarc\BelarcAdvisor\System\tmp\(%COMPUTER_NAME%).html"
    "%PROGRAMFILES(X86)%\Belarc\BelarcAdvisor\System\tmp\(%COMPUTER_NAME%).html"
    "%PROGRAMDATA%\Belarc\BelarcAdvisor\System\tmp\(%COMPUTER_NAME%).html"
) do (
    call :copyBelarcReport "%%~B" "%BELARC_REPORT%" BELARC_REPORT_FOUND
)

if "%BELARC_REPORT_FOUND%"=="0" (
    call :log "WARNING: Belarc report not found in known locations."
) else (
    call :log "Belarc report saved to %BELARC_REPORT%"
)
exit /b 0

:runTranswiz
if exist "%TRANSWIZ_EXE%" (
    call :log "Launching Transwiz wizard..."
    "%TRANSWIZ_EXE%"
    if errorlevel 1 (
        call :log "WARNING: Transwiz exited with error level %errorlevel%"
    ) else (
        call :log "Transwiz completed successfully."
    )
) else (
    call :log "ERROR: Missing Transwiz executable at %TRANSWIZ_EXE%"
)
exit /b 0

:runBelarcScan
set "BELARC_SCAN_ATTEMPT=0"

:runBelarcScanLoop
set "BELARC_SCAN_PATH="
for %%P in ("%BELARC_EXEC_PRIMARY%" "%BELARC_EXEC_SECONDARY%") do (
    if exist "%%~P" (
        set "BELARC_SCAN_PATH=%%~P"
        goto :runBelarcScanFound
    )
)
if "%BELARC_SCAN_ATTEMPT%"=="1" (
    call :log "WARNING: Unable to locate BelarcAdvisor.exe. Skipping automated scan."
    exit /b 0
)
set "BELARC_SCAN_ATTEMPT=1"
call :log "Belarc Advisor executable not found. Attempting installation..."
call :installBelarc
goto :runBelarcScanLoop

:runBelarcScanFound
call :log "Running Belarc Advisor to generate latest report..."
"%BELARC_SCAN_PATH%" >> "%LOG_PATH%" 2>&1
if errorlevel 1 (
    call :log "WARNING: Belarc Advisor exited with error level %errorlevel%"
) else (
    call :log "Belarc Advisor scan completed."
)
exit /b 0

:installBelarc
call :log "Installing Belarc Advisor assets..."
call :ensureDir "%BELARC_DIR%"
if exist "%BELARC_INSTALLER%" (
    copy "%BELARC_INSTALLER%" "%BELARC_DIR%\" >nul
) else (
    call :log "WARNING: Belarc installer missing at %BELARC_INSTALLER%."
    exit /b 1
)
if exist "%BELARC_START%" (
    powershell -ExecutionPolicy Bypass -File "%BELARC_START%" >> "%LOG_PATH%" 2>&1
    if errorlevel 1 (
        call :log "WARNING: Belarc start script returned error level %errorlevel%"
        exit /b 1
    ) else (
        call :log "Belarc installer executed silently."
    )
) else (
    call :log "WARNING: Start_Belarc.ps1 missing at %BELARC_START%"
    exit /b 1
)
exit /b 0

:ensureDir
set "TARGET_DIR=%~1"
if not exist "%TARGET_DIR%" (
    mkdir "%TARGET_DIR%" >nul 2>&1
    if errorlevel 1 (
        echo [ERROR] Unable to create directory: %TARGET_DIR%
        exit /b 1
    )
)
exit /b 0

:ensureAdmin
>nul 2>&1 net session
if %errorlevel% neq 0 (
    echo.
    echo [ERROR] Administrative privileges are required to run this script.
    echo Right-click the batch file and choose "Run as administrator."
    pause
    exit /b 1
)
exit /b 0

:end
echo.
echo Backup completed. Log saved at: %HOST_DIR%\backuplog.txt
echo Use %HOST_DIR%\restore_exclude.txt to specify files/folders that should not be restored automatically.
echo You can also place them into the "Do Not Restore" directory.
pause
endlocal
exit /b 0