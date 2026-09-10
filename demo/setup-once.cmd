@echo off
rem One-time artifacts on a fresh machine, in order (human-run by contract):
rem SPIRE bootstrap CA, EJBCA hierarchy (minutes), employee profiles + RA credential.
rem Idempotent: safe to re-run.
call "%~dp0gitbash.cmd" infra/spire/gen-bootstrap.sh || goto fail
call "%~dp0gitbash.cmd" infra/pki/setup-ejbca.sh || goto fail
call "%~dp0gitbash.cmd" infra/pki/setup-employee-profile.sh || goto fail
echo.
echo [OK] one-time setup done. Next: demo\up.cmd
pause
exit /b 0
:fail
echo.
echo [FAILED] read the lines above, fix, re-run demo\setup-once.cmd
pause
exit /b 1
