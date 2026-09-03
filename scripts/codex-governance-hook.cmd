@echo off
setlocal

for %%I in ("%~dp0..") do set "PROJECTD_ROOT=%%~fI"
set "PROJECTD_PWSH=C:\Program Files\PowerShell\7\pwsh.exe"

if not exist "%PROJECTD_PWSH%" (
    >&2 echo projectD Codex hook launcher: PowerShell 7 was not found.
    exit /b 1
)

if /I "%~1"=="host" goto host
if /I "%~1"=="policy" goto policy

>&2 echo projectD Codex hook launcher: expected mode host or policy.
exit /b 64

:host
if /I "%~2"=="PreToolUse" goto host_run
if /I "%~2"=="PostToolUse" goto host_run
>&2 echo projectD Codex hook launcher: expected a supported host event.
exit /b 64

:host_run
"%PROJECTD_PWSH%" -NoProfile -NonInteractive -File "%PROJECTD_ROOT%\scripts\governance-host-operation-hook.ps1" -HostName codex -ProjectRoot "%PROJECTD_ROOT%" -ExpectedEventName "%~2"
exit /b %ERRORLEVEL%

:policy
"%PROJECTD_PWSH%" -NoProfile -NonInteractive -File "%PROJECTD_ROOT%\scripts\governance-command-policy-hook.ps1" -ProjectRoot "%PROJECTD_ROOT%" -HostName codex
exit /b %ERRORLEVEL%
