@echo off
setlocal

REM ============================================================================
REM  MANUAL / INTERACTIVE USE ONLY -- for a tech running the installer by hand.
REM  GPO startup deployment must point at BMAInstallerScript.ps1 directly
REM  (Computer Config > Policies > Windows Settings > Scripts > Startup >
REM  "PowerShell Scripts"). Do NOT deploy this .bat via GPO: the self-elevation
REM  and the "pause" at the end will hang or no-op in the non-interactive SYSTEM
REM  session that a startup script runs in.
REM ============================================================================
REM Runs the BMA installer PowerShell script from this same folder, self-
REM elevating to Administrator first if we aren't already.

set "SCRIPT=%~dp0BMAInstallerScript.ps1"

REM --- Optional dry run: pass /dryrun as the first argument to test without installing ---
set "PSARGS="
if /i "%~1"=="/dryrun" set "PSARGS=-DryRun"

REM --- Check for Administrator rights ---
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting Administrator privileges...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -ArgumentList '%~1' -Verb RunAs"
    exit /b
)

REM --- Already elevated: run the installer script ---
if defined PSARGS (echo Running BMA installer [DRY RUN]...) else (echo Running BMA installer...)
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %PSARGS%

set "RC=%errorlevel%"
echo.
echo Done. Log: C:\BankOnIT\Logs\BMAInstall_Log.txt
echo (PowerShell exit code: %RC%)
pause
endlocal
