@echo off
setlocal

:: Self-elevate to admin if not already elevated
net session >nul 2>&1
if %errorLevel% NEQ 0 (
    echo Requesting administrator privileges...
    powershell -Command "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit /b
)

:: Read local version
set OSSVER=unknown
if exist "%~dp0version.txt" set /p OSSVER=<"%~dp0version.txt"

:: Check for updates (fails silently if server unreachable)
cls
echo ============================================================
echo  Navanta OSS Toolkit  v%OSSVER%
echo  patrick hart - hartforge.dev
echo ============================================================
echo.
powershell -ExecutionPolicy Bypass -File "%~dp0update.ps1"
if %ERRORLEVEL% neq 0 goto :EOF
set OSSMANAGED=1

:SELECT_ENV
cls
echo ============================================================
echo  Navanta OSS Toolkit  v%OSSVER%
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
if "%env_choice%"=="1" set OSSENV=onprem& goto GET_CLIENT
if "%env_choice%"=="2" set OSSENV=m365& goto GET_CLIENT
if "%env_choice%"=="3" set OSSENV=hybrid& goto GET_CLIENT
goto SELECT_ENV

:GET_CLIENT
echo.
set /p CLIENTNAME="client name / branch (e.g. MAINST-01): "
rem strip quotes so comparisons and logging can't break on embedded "
if defined CLIENTNAME set "CLIENTNAME=%CLIENTNAME:"=%"
if "%CLIENTNAME%"=="" goto GET_CLIENT

:MENU
cls
echo ============================================================
echo  Navanta OSS Toolkit  v%OSSVER%  [%OSSENV%]  [%CLIENTNAME%]
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
echo  10. Fix Print Spooler             (clear queue and restart spooler)
echo.
echo  -- CONFIG --
echo   C1. Disable Teams Auto-Install       (prevent consumer Teams install)
echo   C2. Disable OneDrive Auto-Install    (prevent consumer OneDrive install)
echo   C3. Disable MS Account Sign-in       (block personal MS account prompts in Office)
echo   C4. Disable Update Auto-Reboot       (stop Windows Update mid-day reboots)
echo   C5. Edge IE Mode Sites               (enable IE mode and manage site list)
echo.
echo  -- DIAG --
echo   D1. System Snapshot              (OS, domain, Outlook version, key reg values)
echo   D2. Exchange Connectivity        (test DC/Exchange/M365 reachability)
echo   D3. Outlook Config Dump          (export Outlook registry to file)
echo   D4. Office License Status        (check Office activation via ospp.vbs)
echo   D5. Event Log Errors             (last 100 errors from App and System logs)
echo   D6. Network Info                 (IP, gateway, DNS, DHCP info for active adapters)
echo   DA. Run All Diag                 (run D1-D6 in sequence)
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
if /i "%choice%"=="10" goto RUN_SPOOLER
if /i "%choice%"=="C1" goto RUN_TEAMS
if /i "%choice%"=="C2" goto RUN_ONEDRIVE
if /i "%choice%"=="C3" goto RUN_MSACCOUNT
if /i "%choice%"=="C4" goto RUN_AUTOREBOOT
if /i "%choice%"=="C5" goto RUN_IEMODE
if /i "%choice%"=="D1" goto RUN_SNAPSHOT
if /i "%choice%"=="D2" goto RUN_EXCHCONN
if /i "%choice%"=="D3" goto RUN_OUTLOOKDUMP
if /i "%choice%"=="D4" goto RUN_LICENSE
if /i "%choice%"=="D5" goto RUN_EVENTLOG
if /i "%choice%"=="D6" goto RUN_NETINFO
if /i "%choice%"=="DA" goto RUN_ALL_DIAG
if /i "%choice%"=="Q"  exit /b
goto MENU

:LOG
if not exist "%~dp0Logs\" mkdir "%~dp0Logs"
setlocal EnableDelayedExpansion
echo !DATE! !TIME:~0,8! ^| !COMPUTERNAME! ^| !CLIENTNAME! ^| !OSSENV! ^| !LOGSCRIPT! >> "%~dp0Logs\OSS-session-log.txt"
endlocal
goto %LOGBACK%

:RUN_AUTODISCOVER
set LOGSCRIPT=outlook-autodiscover & set LOGBACK=RUN_AUTODISCOVER_GO & goto LOG
:RUN_AUTODISCOVER_GO
powershell -ExecutionPolicy Bypass -File "%~dp0fixes\outlook-autodiscover\fix.ps1" -Environment "%OSSENV%"
goto MENU

:RUN_WORKPLACEJOIN
set LOGSCRIPT=block-aad-workplacejoin & set LOGBACK=RUN_WORKPLACEJOIN_GO & goto LOG
:RUN_WORKPLACEJOIN_GO
powershell -ExecutionPolicy Bypass -File "%~dp0fixes\block-aad-workplacejoin\fix.ps1" -Environment "%OSSENV%"
goto MENU

:RUN_WAM
set LOGSCRIPT=disable-wam & set LOGBACK=RUN_WAM_GO & goto LOG
:RUN_WAM_GO
powershell -ExecutionPolicy Bypass -File "%~dp0fixes\disable-wam\fix.ps1" -Environment "%OSSENV%"
goto MENU

:RUN_CREDS
set LOGSCRIPT=credential-cleanup & set LOGBACK=RUN_CREDS_GO & goto LOG
:RUN_CREDS_GO
powershell -ExecutionPolicy Bypass -File "%~dp0fixes\credential-cleanup\fix.ps1"
goto MENU

:RUN_PROFILE
set LOGSCRIPT=outlook-profile-rebuild & set LOGBACK=RUN_PROFILE_GO & goto LOG
:RUN_PROFILE_GO
powershell -ExecutionPolicy Bypass -File "%~dp0fixes\outlook-profile-rebuild\fix.ps1"
goto MENU

:RUN_OFFICECACHE
set LOGSCRIPT=clear-office-cache & set LOGBACK=RUN_OFFICECACHE_GO & goto LOG
:RUN_OFFICECACHE_GO
powershell -ExecutionPolicy Bypass -File "%~dp0fixes\clear-office-cache\fix.ps1"
goto MENU

:RUN_TEAMSCACHE
set LOGSCRIPT=reset-teams-cache & set LOGBACK=RUN_TEAMSCACHE_GO & goto LOG
:RUN_TEAMSCACHE_GO
powershell -ExecutionPolicy Bypass -File "%~dp0fixes\reset-teams-cache\fix.ps1"
goto MENU

:RUN_DNS
set LOGSCRIPT=flush-dns-winsock & set LOGBACK=RUN_DNS_GO & goto LOG
:RUN_DNS_GO
powershell -ExecutionPolicy Bypass -File "%~dp0fixes\flush-dns-winsock\fix.ps1"
goto MENU

:RUN_NAVPANE
set LOGSCRIPT=reset-outlook-navpane & set LOGBACK=RUN_NAVPANE_GO & goto LOG
:RUN_NAVPANE_GO
powershell -ExecutionPolicy Bypass -File "%~dp0fixes\reset-outlook-navpane\fix.ps1"
goto MENU

:RUN_SPOOLER
set LOGSCRIPT=fix-print-spooler & set LOGBACK=RUN_SPOOLER_GO & goto LOG
:RUN_SPOOLER_GO
powershell -ExecutionPolicy Bypass -File "%~dp0fixes\fix-print-spooler\fix.ps1"
goto MENU

:RUN_TEAMS
set LOGSCRIPT=disable-teams-autoinstall & set LOGBACK=RUN_TEAMS_GO & goto LOG
:RUN_TEAMS_GO
powershell -ExecutionPolicy Bypass -File "%~dp0config\disable-teams-autoinstall\config.ps1"
goto MENU

:RUN_ONEDRIVE
set LOGSCRIPT=disable-onedrive-autoinstall & set LOGBACK=RUN_ONEDRIVE_GO & goto LOG
:RUN_ONEDRIVE_GO
powershell -ExecutionPolicy Bypass -File "%~dp0config\disable-onedrive-autoinstall\config.ps1"
goto MENU

:RUN_MSACCOUNT
set LOGSCRIPT=disable-ms-account-signin & set LOGBACK=RUN_MSACCOUNT_GO & goto LOG
:RUN_MSACCOUNT_GO
powershell -ExecutionPolicy Bypass -File "%~dp0config\disable-ms-account-signin\config.ps1"
goto MENU

:RUN_AUTOREBOOT
set LOGSCRIPT=disable-update-autoreboot & set LOGBACK=RUN_AUTOREBOOT_GO & goto LOG
:RUN_AUTOREBOOT_GO
powershell -ExecutionPolicy Bypass -File "%~dp0config\disable-update-autoreboot\config.ps1"
goto MENU

:RUN_IEMODE
set LOGSCRIPT=edge-ie-mode-sites & set LOGBACK=RUN_IEMODE_GO & goto LOG
:RUN_IEMODE_GO
powershell -ExecutionPolicy Bypass -File "%~dp0config\edge-ie-mode-sites\config.ps1"
goto MENU

:RUN_SNAPSHOT
set LOGSCRIPT=system-snapshot & set LOGBACK=RUN_SNAPSHOT_GO & goto LOG
:RUN_SNAPSHOT_GO
powershell -ExecutionPolicy Bypass -File "%~dp0diag\system-snapshot\diag.ps1" -ClientName "%CLIENTNAME%" -OutputDir "%~dp0Logs"
goto MENU

:RUN_EXCHCONN
set LOGSCRIPT=exchange-connectivity & set LOGBACK=RUN_EXCHCONN_GO & goto LOG
:RUN_EXCHCONN_GO
powershell -ExecutionPolicy Bypass -File "%~dp0diag\exchange-connectivity\diag.ps1" -Environment "%OSSENV%" -ClientName "%CLIENTNAME%" -OutputDir "%~dp0Logs"
goto MENU

:RUN_OUTLOOKDUMP
set LOGSCRIPT=outlook-config-dump & set LOGBACK=RUN_OUTLOOKDUMP_GO & goto LOG
:RUN_OUTLOOKDUMP_GO
powershell -ExecutionPolicy Bypass -File "%~dp0diag\outlook-config-dump\diag.ps1" -ClientName "%CLIENTNAME%" -OutputDir "%~dp0Logs"
goto MENU

:RUN_LICENSE
set LOGSCRIPT=office-license-status & set LOGBACK=RUN_LICENSE_GO & goto LOG
:RUN_LICENSE_GO
powershell -ExecutionPolicy Bypass -File "%~dp0diag\office-license-status\diag.ps1" -ClientName "%CLIENTNAME%" -OutputDir "%~dp0Logs"
goto MENU

:RUN_EVENTLOG
set LOGSCRIPT=event-log-errors & set LOGBACK=RUN_EVENTLOG_GO & goto LOG
:RUN_EVENTLOG_GO
powershell -ExecutionPolicy Bypass -File "%~dp0diag\event-log-errors\diag.ps1" -ClientName "%CLIENTNAME%" -OutputDir "%~dp0Logs"
goto MENU

:RUN_NETINFO
set LOGSCRIPT=network-info & set LOGBACK=RUN_NETINFO_GO & goto LOG
:RUN_NETINFO_GO
powershell -ExecutionPolicy Bypass -File "%~dp0diag\network-info\diag.ps1" -ClientName "%CLIENTNAME%" -OutputDir "%~dp0Logs"
goto MENU

:RUN_ALL_DIAG
set LOGSCRIPT=run-all-diag & set LOGBACK=RUN_ALL_DIAG_GO & goto LOG
:RUN_ALL_DIAG_GO
echo running all diag tools -- output files will appear in the Logs folder.
echo.
powershell -ExecutionPolicy Bypass -File "%~dp0diag\system-snapshot\diag.ps1"       -ClientName "%CLIENTNAME%" -OutputDir "%~dp0Logs" -NonInteractive
powershell -ExecutionPolicy Bypass -File "%~dp0diag\exchange-connectivity\diag.ps1" -Environment "%OSSENV%" -ClientName "%CLIENTNAME%" -OutputDir "%~dp0Logs" -NonInteractive
powershell -ExecutionPolicy Bypass -File "%~dp0diag\outlook-config-dump\diag.ps1"   -ClientName "%CLIENTNAME%" -OutputDir "%~dp0Logs" -NonInteractive
powershell -ExecutionPolicy Bypass -File "%~dp0diag\office-license-status\diag.ps1" -ClientName "%CLIENTNAME%" -OutputDir "%~dp0Logs" -NonInteractive
powershell -ExecutionPolicy Bypass -File "%~dp0diag\event-log-errors\diag.ps1"      -ClientName "%CLIENTNAME%" -OutputDir "%~dp0Logs" -NonInteractive
powershell -ExecutionPolicy Bypass -File "%~dp0diag\network-info\diag.ps1"          -ClientName "%CLIENTNAME%" -OutputDir "%~dp0Logs" -NonInteractive
echo.
echo all diag tools complete.
pause
goto MENU
