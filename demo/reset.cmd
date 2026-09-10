@echo off
rem Stage recovery. Same as: bash demo/reset.sh [--soft|--full|--cold]
rem Default --soft (app layer only, < 2 min). --cold asks for confirmation and destroys CA state.
call "%~dp0gitbash.cmd" demo/reset.sh %*
set "RC=%ERRORLEVEL%"
if "%RC%"=="0" ( echo. & echo [OK] ) else ( echo. & echo [FAILED] exit code %RC% - read the lines above )
echo.
pause
exit /b %RC%
