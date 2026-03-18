@echo off
setlocal

:: Self-elevate to admin if not already elevated
net session >nul 2>&1
if %errorLevel% NEQ 0 (
    echo Requesting administrator privileges...
    powershell -Command "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit /b
)

:SELECT_ENV
cls
echo ============================================================
echo  BankOnIT OSS Toolkit  v1.1
echo  patrick hart - hartforge.dev
echo ============================================================
echo.
echo  client mail environment:
echo.
echo   1. on-premises exchange only
echo   2. microsoft 365 (cloud only)
echo   3. hybrid (exchange + m365)
echo.
set /p env_choice="select environment: "
if "%env_choice%"=="1" set OSSENV=onprem & goto MENU
if "%env_choice%"=="2" set OSSENV=m365 & goto MENU
if "%env_choice%"=="3" set OSSENV=hybrid & goto MENU
goto SELECT_ENV

:MENU
cls
echo ============================================================
echo  BankOnIT OSS Toolkit  v1.1  [%OSSENV%]
echo  patrick hart - hartforge.dev
echo ============================================================
echo.
echo  -- FIXES --
echo   1. Outlook Autodiscover          (configure autodiscover for %OSSENV%)
echo   2. Block AAD Workplace Join      (suppress Entra ID device registration nag)
echo   3. Disable WAM                   (stop Office routing auth through WAM)
echo   4. Credential Cleanup            (purge stale Exchange/Office creds)
echo   5. Outlook Profile Rebuild       (delete and recreate Outlook profile)
echo   6. Clear Office Cache            (nuke Office identity/license cache)
echo   7. Reset Teams Cache             (clear Teams cache folders)
echo   8. Flush DNS / Winsock Reset     (flush DNS cache and reset winsock)
echo   9. Reset Outlook Nav Pane        (fix corrupt Outlook navigation pane)
echo.
echo  -- CONFIG --
echo   C1. Disable Teams Auto-Install       (prevent consumer Teams install)
echo   C2. Disable OneDrive Auto-Install    (prevent consumer OneDrive install)
echo   C3. Disable MS Account Sign-in       (block personal MS account prompts in Office)
echo   C4. Disable Update Auto-Reboot       (stop Windows Update mid-day reboots)
echo.
echo  -- DIAG --
echo   D1. System Snapshot              (OS, domain, Outlook version, key reg values)
echo   D2. Exchange Connectivity        (test DC/Exchange/M365 reachability)
echo   D3. Outlook Config Dump          (export Outlook registry to file on desktop)
echo.
echo   Q. Quit
echo.
set /p choice="select option: "

if /i "%choice%"=="1"  goto RUN_AUTODISCOVER
if /i "%choice%"=="2"  goto RUN_WORKPLACEJOIN
if /i "%choice%"=="3"  goto RUN_WAM
if /i "%choice%"=="4"  goto RUN_CREDS
if /i "%choice%"=="5"  goto RUN_PROFILE
if /i "%choice%"=="6"  goto RUN_OFFICECACHE
if /i "%choice%"=="7"  goto RUN_TEAMSCACHE
if /i "%choice%"=="8"  goto RUN_DNS
if /i "%choice%"=="9"  goto RUN_NAVPANE
if /i "%choice%"=="C1" goto RUN_TEAMS
if /i "%choice%"=="C2" goto RUN_ONEDRIVE
if /i "%choice%"=="C3" goto RUN_MSACCOUNT
if /i "%choice%"=="C4" goto RUN_AUTOREBOOT
if /i "%choice%"=="D1" goto RUN_SNAPSHOT
if /i "%choice%"=="D2" goto RUN_EXCHCONN
if /i "%choice%"=="D3" goto RUN_OUTLOOKDUMP
if /i "%choice%"=="Q"  exit /b
goto MENU

:RUN_AUTODISCOVER
powershell -ExecutionPolicy Bypass -File "%~dp0fixes\outlook-autodiscover\fix.ps1" -Environment "%OSSENV%"
goto MENU

:RUN_WORKPLACEJOIN
powershell -ExecutionPolicy Bypass -File "%~dp0fixes\block-aad-workplacejoin\fix.ps1" -Environment "%OSSENV%"
goto MENU

:RUN_WAM
powershell -ExecutionPolicy Bypass -File "%~dp0fixes\disable-wam\fix.ps1" -Environment "%OSSENV%"
goto MENU

:RUN_CREDS
powershell -ExecutionPolicy Bypass -File "%~dp0fixes\credential-cleanup\fix.ps1"
goto MENU

:RUN_PROFILE
powershell -ExecutionPolicy Bypass -File "%~dp0fixes\outlook-profile-rebuild\fix.ps1"
goto MENU

:RUN_OFFICECACHE
powershell -ExecutionPolicy Bypass -File "%~dp0fixes\clear-office-cache\fix.ps1"
goto MENU

:RUN_TEAMSCACHE
powershell -ExecutionPolicy Bypass -File "%~dp0fixes\reset-teams-cache\fix.ps1"
goto MENU

:RUN_DNS
powershell -ExecutionPolicy Bypass -File "%~dp0fixes\flush-dns-winsock\fix.ps1"
goto MENU

:RUN_NAVPANE
powershell -ExecutionPolicy Bypass -File "%~dp0fixes\reset-outlook-navpane\fix.ps1"
goto MENU

:RUN_TEAMS
powershell -ExecutionPolicy Bypass -File "%~dp0config\disable-teams-autoinstall\config.ps1"
goto MENU

:RUN_ONEDRIVE
powershell -ExecutionPolicy Bypass -File "%~dp0config\disable-onedrive-autoinstall\config.ps1"
goto MENU

:RUN_MSACCOUNT
powershell -ExecutionPolicy Bypass -File "%~dp0config\disable-ms-account-signin\config.ps1"
goto MENU

:RUN_AUTOREBOOT
powershell -ExecutionPolicy Bypass -File "%~dp0config\disable-update-autoreboot\config.ps1"
goto MENU

:RUN_SNAPSHOT
powershell -ExecutionPolicy Bypass -File "%~dp0diag\system-snapshot\diag.ps1"
goto MENU

:RUN_EXCHCONN
powershell -ExecutionPolicy Bypass -File "%~dp0diag\exchange-connectivity\diag.ps1" -Environment "%OSSENV%"
goto MENU

:RUN_OUTLOOKDUMP
powershell -ExecutionPolicy Bypass -File "%~dp0diag\outlook-config-dump\diag.ps1"
goto MENU
