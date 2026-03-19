@echo off
REM Wrapper to call the main backup script in scripts\Backup.bat
REM See README.md in this folder for usage and scenarios.
REM Check for admin and self-elevate if needed
>nul 2>&1 net session
if %errorlevel% neq 0 (
    echo Requesting administrative privileges...
    if "%~1"=="" (
        powershell -NoProfile -ExecutionPolicy Bypass ^
            -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    ) else (
        powershell -NoProfile -ExecutionPolicy Bypass ^
            -Command "Start-Process -FilePath '%~f0' -ArgumentList '%*' -Verb RunAs"
    )
    exit /b
)

powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%~dp0scripts\Backup.ps1" %*