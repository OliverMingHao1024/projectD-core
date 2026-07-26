@echo off
chcp 65001 >nul
setlocal
set "HERE=%~dp0"
echo.
echo projectD-core global setup for Claude Code and Codex
echo.
pwsh -NoProfile -ExecutionPolicy Bypass -File "%HERE%setup.ps1"
set "SETUP_EXIT=%ERRORLEVEL%"
if not "%SETUP_EXIT%"=="0" (
    echo.
    echo Setup failed. See messages above.
    pause
    exit /b %SETUP_EXIT%
)
echo.
echo Setup complete. Restart Claude Code, Codex, terminals, and IDE tools.
pause
