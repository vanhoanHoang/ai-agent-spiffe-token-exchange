@echo off
rem Load images from a USB folder. Same as: bash demo/import-images.sh <dir>
rem Example:  demo\import-images.cmd E:\spiffe-lab
call "%~dp0gitbash.cmd" demo/import-images.sh %*
set "RC=%ERRORLEVEL%"
if "%RC%"=="0" ( echo. & echo [OK] ) else ( echo. & echo [FAILED] exit code %RC% - read the lines above )
echo.
pause
exit /b %RC%
