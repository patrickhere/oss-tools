@echo off
REM Wrapper to call the Hiren's backup script in scripts\Backup_Hirens.bat
REM See README.md for usage and scenarios.

REM Check for admin and self-elevate if needed
>nul 2>&1 net session
if %errorlevel% neq 0 (
    echo Requesting administrative privileges...
    powershell -NoProfile -ExecutionPolicy Bypass ^
        -Command "Start-Process -FilePath '%~f0' -ArgumentList '%*' -Verb RunAs"
    exit /b
)

"%~dp0scripts\Backup_Hirens.bat" %*
