@echo off
chcp 65001 >nul
setlocal
set "HERE=%~dp0"
pwsh -NoProfile -ExecutionPolicy Bypass -File "%HERE%setup.ps1"
if %errorlevel% neq 0 (
    echo.
    echo Setup failed. See messages above.
    pause
    exit /b 1
)
echo.
echo Setup complete. Restart terminal and IDE tools.
pause
