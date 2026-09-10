@echo off
rem Double-click: preflight + full launch + checklist. Same as: bash demo/up.sh
rem Pass --check for the preflight only:  demo\up.cmd --check
call "%~dp0gitbash.cmd" demo/up.sh %*
set "RC=%ERRORLEVEL%"
if "%RC%"=="0" ( echo. & echo [OK] ) else ( echo. & echo [FAILED] exit code %RC% - read the lines above )
echo.
pause
exit /b %RC%
