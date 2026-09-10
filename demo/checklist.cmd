@echo off
rem Pre-demo checklist (clock skew first). Same as: bash demo/checklist.sh
rem Pass --full to include the terminal acceptance (minutes).
call "%~dp0gitbash.cmd" demo/checklist.sh %*
set "RC=%ERRORLEVEL%"
if "%RC%"=="0" ( echo. & echo [OK] ) else ( echo. & echo [FAILED] exit code %RC% - read the lines above )
echo.
pause
exit /b %RC%
