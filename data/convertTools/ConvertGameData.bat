@echo off
setlocal

cd /d "%~dp0"

powershell.exe ^
    -NoProfile ^
    -ExecutionPolicy Bypass ^
    -File "%~dp0ConvertGameData.ps1"

set EXIT_CODE=%ERRORLEVEL%

echo.
if %EXIT_CODE% EQU 0 (
    echo Game data conversion completed.
) else (
    echo Game data conversion failed.
)

echo.
pause

exit /b %EXIT_CODE%