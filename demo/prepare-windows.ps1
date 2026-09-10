# One-time machine preparation on a fresh Windows 11 laptop (docs/RUNBOOK-WIN11.md).
# Run from the repo root in PowerShell, as a NORMAL user (no admin needed for most of it):
#   powershell -ExecutionPolicy Bypass -File demo\prepare-windows.ps1 [-Images E:\spiffe-lab]
# What it does, idempotently: .wslconfig (Docker memory, per-user), infra\.env from
# the template (opens Notepad so you paste the Groq key), optional image import from
# a USB folder, the hosts entry for keycloak IF it can (admin), else it prints the
# exact line for IT, then restarts WSL so the memory setting applies.
# Afterwards:  demo\setup-once.cmd  then  demo\up.cmd
param([string]$Images = "")
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $root
Write-Host "== repo: $root"
$todo = @()

# 0. Docker present? (installing it needs admin; nothing here can do that)
try { $null = docker version --format '{{.Server.Version}}' 2>$null; Write-Host "[ok]   docker engine answering" }
catch { Write-Host "[warn] docker is not answering: install Docker Desktop (needs admin / IT) and open it before demo\up.cmd" }

# 1. Docker memory: WSL2 takes 50% of RAM by default and never returns it. Per-user file, no admin.
$wsl = Join-Path $env:USERPROFILE ".wslconfig"
$restartWsl = $false
if (Test-Path $wsl) {
  Write-Host "[skip] $wsl already exists (make sure memory is >= 6GB)"
} else {
  Copy-Item "infra\wslconfig.example" $wsl
  Write-Host "[ok]   wrote $wsl (memory=6GB, swap=2GB)"
  $restartWsl = $true
}

# 2. hosts: the browser login redirects to http://keycloak:8080. Needs admin; try, else hand it to IT.
$hosts = Join-Path $env:SystemRoot "System32\drivers\etc\hosts"
if (Select-String -Path $hosts -Pattern '^\s*127\.0\.0\.1\s+keycloak(\s|$)' -Quiet) {
  Write-Host "[skip] hosts entry '127.0.0.1 keycloak' already present"
} else {
  try {
    Add-Content -Path $hosts -Value "`r`n127.0.0.1 keycloak" -ErrorAction Stop
    Write-Host "[ok]   hosts: 127.0.0.1 keycloak"
  } catch {
    Write-Host "[todo] hosts entry needs admin. Ask IT (or an admin PowerShell) to run:"
    Write-Host "       Add-Content C:\Windows\System32\drivers\etc\hosts `"``n127.0.0.1 keycloak`""
    $todo += "hosts entry 127.0.0.1 keycloak (admin)"
  }
}

# 3. The LLM key: template in git, filled-in file gitignored (never commit it).
if (Test-Path "infra\.env") {
  Write-Host "[skip] infra\.env already exists"
} else {
  Copy-Item "infra\.env.example" "infra\.env"
  Write-Host "[ok]   infra\.env created from the template"
  Write-Host "       Notepad opens: replace <paste your gsk_ key here> with the key from console.groq.com/keys, save, close."
  Start-Process notepad.exe -ArgumentList "infra\.env" -Wait
}
$envText = Get-Content "infra\.env" -Raw
if ($envText -match 'LLM_API_KEY=gsk_[A-Za-z0-9]{20,}') { Write-Host "[ok]   infra\.env has a key-shaped LLM_API_KEY" }
else { Write-Host "[warn] infra\.env has no gsk_ key yet: the stack would fall back to local Ollama (slow, 2-3 GB pull). Edit infra\.env before demo\up.cmd"; $todo += "paste the Groq key into infra\.env" }

# 4. Images from USB (skips the 10-minute build and the registry pulls).
if ($Images) {
  if (Test-Path (Join-Path $Images "spiffe-mcp-lab-images.tar")) {
    Write-Host "== importing images from $Images (minutes)..."
    & cmd.exe /c "`"$root\demo\import-images.cmd`" `"$Images`" < nul"
  } else {
    Write-Host "[warn] $Images has no spiffe-mcp-lab-images.tar; images will be built by demo\up.cmd instead (needs internet)"
  }
}

# 5. Apply the memory setting (no admin needed).
if ($restartWsl) {
  Write-Host "== restarting WSL so the memory setting applies (Docker Desktop will ask to restart; say yes)"
  wsl.exe --shutdown
}

Write-Host ""
if ($todo.Count -gt 0) { Write-Host "STILL TO DO:"; $todo | ForEach-Object { Write-Host "  - $_" } }
Write-Host "NEXT: open Docker Desktop, wait for 'Engine running', then:  demo\setup-once.cmd  and  demo\up.cmd"
