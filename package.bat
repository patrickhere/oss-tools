@echo off
echo packaging OSS toolkit to desktop...
powershell -Command "Compress-Archive -Path '%~dp0' -DestinationPath '%USERPROFILE%\Desktop\Navanta-OSS.zip' -Force"
if %ERRORLEVEL% neq 0 (
    echo.
    echo ERROR: packaging failed. check that the destination is writable.
) else (
    echo.
    echo done. Navanta-OSS.zip is on your desktop.
)
echo.
pause
