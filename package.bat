@echo off
echo packaging OSS toolkit to desktop...
rem stage a clean copy first - Logs\ has client-identifying session data and
rem Backups\ can be huge; neither belongs in a shareable artifact
powershell -Command "$stage = Join-Path $env:TEMP 'navanta-oss-pkg'; if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }; New-Item -ItemType Directory -Path $stage | Out-Null; robocopy '%~dp0.' $stage /E /XD Logs Backups .git /XF *.zip /NFL /NDL /NJH /NJS | Out-Null; if ($LASTEXITCODE -ge 8) { exit 1 }; Compress-Archive -Path \"$stage\*\" -DestinationPath '%USERPROFILE%\Desktop\Navanta-OSS.zip' -Force; Remove-Item $stage -Recurse -Force; exit 0"
if %ERRORLEVEL% neq 0 (
    echo.
    echo ERROR: packaging failed. check that the destination is writable.
) else (
    echo.
    echo done. Navanta-OSS.zip is on your desktop. logs and backups excluded.
)
echo.
pause
