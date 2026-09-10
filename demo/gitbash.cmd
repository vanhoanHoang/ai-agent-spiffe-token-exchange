@echo off
rem Runs a repo bash script with Git for Windows' bash (MSYS), from anywhere on
rem Windows: PowerShell, cmd, or a double-click. Never WSL's bash.exe.
rem   demo\gitbash.cmd <script-relative-to-repo-root> [args...]
setlocal
rem Capture our directory BEFORE any shift: shift moves %0 too, so %~dp0 would drift.
set "HERE=%~dp0"
set "BASH="
if exist "%ProgramFiles%\Git\bin\bash.exe" set "BASH=%ProgramFiles%\Git\bin\bash.exe"
if not defined BASH if exist "%ProgramFiles(x86)%\Git\bin\bash.exe" set "BASH=%ProgramFiles(x86)%\Git\bin\bash.exe"
if not defined BASH if exist "%LocalAppData%\Programs\Git\bin\bash.exe" set "BASH=%LocalAppData%\Programs\Git\bin\bash.exe"
if not defined BASH for /f "delims=" %%g in ('where git.exe 2^>nul') do if not defined BASH if exist "%%~dpg..\bin\bash.exe" set "BASH=%%~dpg..\bin\bash.exe"
if not defined BASH (
  echo Git for Windows was not found. Install it from https://git-scm.com/download/win
  echo ^(it provides bash, curl and openssl - the only tools the scripts need^).
  exit /b 1
)
set "SCRIPT=%~1"
if "%SCRIPT%"=="" ( echo usage: demo\gitbash.cmd ^<script^> [args] & exit /b 2 )
shift
set "ARGS="
:collect
if "%~1"=="" goto run
set "ARGS=%ARGS% %1"
shift
goto collect
:run
cd /d "%HERE%.."
rem No --login: Git's bin\bash.exe already puts /usr/bin and /mingw64/bin (curl,
rem openssl) on PATH, and a login shell would cd to HOME.
"%BASH%" "%SCRIPT%" %ARGS%
exit /b %ERRORLEVEL%
