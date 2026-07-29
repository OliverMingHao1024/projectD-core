@echo off
chcp 65001 >nul
setlocal
set "HERE=%~dp0"
pwsh -NoProfile -File "%HERE%uninstall.ps1"
pause
