# Runbook — fresh Windows 11 demo laptop

Goal: `bash demo/up.sh` passes on the first try on a machine that has never seen
this stack, with nobody around to debug. Every step is copy-paste; every failure
seen so far on Windows is in the table at the end with its fix line. The
preflight in `demo/up.sh --check` tests all of them and prints the fix itself.

Time budget on a laptop with the images imported from USB: about 25 minutes
(EJBCA's first initialisation is most of it). With images built from source: add 10–15 minutes and a working internet connection.

## Company laptop, Docker already installed, hosts line added by you

Everything below is PowerShell as your normal user, no admin. Copy block by block.

**1. Code + machine prep** (`.wslconfig`, `infra\.env` with the Groq key via Notepad, WSL restart):

```powershell
cd "C:\Research Engineer\Eviden\AI\ai-agent-spiffe-token-exchange"
git pull
powershell -ExecutionPolicy Bypass -File demo\prepare-windows.ps1
```

When Notepad opens: replace `<paste your gsk_ key here>` with the key from
console.groq.com/keys, Save, close Notepad. When the script prints NEXT: open
Docker Desktop, wait for "Engine running".

**2. One-time CA hierarchy** (~10 min, mostly EJBCA):

```powershell
demo\setup-once.cmd
```

**3. Check, then launch** (first launch builds the images, ~15 min with internet):

```powershell
demo\up.cmd --check
demo\up.cmd
```

Every `--check` line must be `OK`; a `FAIL` line tells you the fix. The last line
of `demo\up.cmd` must be `CHECKLIST PASS — go on stage`.

**4. Try it once before the audience:** http://localhost:8090, `alice` /
`alice-password`, then these two prompts:

```
Use the whoami tool and tell me who you act for
Onboard employee john-laptop
```

**5. Morning of the demo, after the laptop slept:**

```powershell
demo\checklist.cmd
```

If it reports clock skew: `wsl --shutdown`, open Docker Desktop again, then `demo\reset.cmd --soft`.

---

## The whole thing, to paste

**Needs admin (IT), no way around it:** installing Docker Desktop with the WSL2
backend, and one line in the hosts file. Everything else is per-user. Ask IT for
exactly these two things, in this wording:

```
1. Install Docker Desktop (WSL2 backend) and let my user run it.
2. Add this line to C:\Windows\System32\drivers\etc\hosts:   127.0.0.1 keycloak
```

Git for Windows installs per-user without admin (installer: "Install for me only"),
or use the portable build from git-scm.com.

Then PowerShell, as your normal user. Change `E:\spiffe-lab` to the USB folder, or
drop `-Images ...` to build from source (needs internet, +15 min):

```powershell
git clone https://github.com/vanhoanHoang/ai-agent-spiffe-token-exchange.git C:\lab\spiffe-mcp-lab
cd C:\lab\spiffe-mcp-lab
powershell -ExecutionPolicy Bypass -File demo\prepare-windows.ps1 -Images E:\spiffe-lab
```

`prepare-windows.ps1` does, by itself and without admin: `.wslconfig` (Docker
memory 6 GB), `infra\.env` from the template (Notepad opens, paste the Groq key,
save), image import from the USB folder, WSL restart. It tries the hosts line and,
if it cannot, prints it for IT. When it says NEXT, open Docker Desktop, wait for
"Engine running", then:

```powershell
demo\setup-once.cmd     # one-time CA hierarchy, ~10 min (EJBCA)
demo\up.cmd --check     # every line OK, or a fix line
demo\up.cmd             # launch; last line must be CHECKLIST PASS
```

Then http://localhost:8090, alice / alice-password, and the two demo prompts once:
"Use the whoami tool and tell me who you act for", then "Onboard employee john-laptop".

Morning of the demo, after the laptop slept: `demo\checklist.cmd`.

The sections below are the same steps, explained, plus every Windows failure seen and its fix.

## 0. On the OLD machine, before you leave

```bash
# 1. everything committed and pushed (a fresh clone only sees commits)
git status --short          # must be empty
git push ai-agent main

# 2. images to a USB stick (a few GB) — skips the build and the registry pulls at the venue
bash demo/export-images.sh /e/usb/spiffe-lab

# 3. the Groq key travels separately (infra/.env is gitignored and NOT in the clone):
#    copy infra/.env to the USB stick too, or have console.groq.com open on the new machine
```

## 1. Install (once, ~15 min, needs internet)

| What | Where | Note |
|---|---|---|
| Docker Desktop | docker.com | WSL2 backend (default). Reboot when asked. After install open it once and wait for "Engine running". If it complains about WSL: admin PowerShell `wsl --update`, reboot. |
| Git for Windows | git-scm.com | Keep the defaults. This gives you **Git Bash**, `curl`, `openssl` — the scripts need nothing else. |
| Python 3 (optional) | python.org | Only `scripts/check-*.sh` and `demo/capture-run.sh` use it. Tick "Add to PATH". Windows ships a fake `python` that opens the Store — the preflight tells you if that is what you have. |

Memory: copy `infra/wslconfig.example` to `C:\Users\<you>\.wslconfig`, then in
PowerShell `wsl --shutdown` and restart Docker Desktop. Without it, on a 16 GB laptop WSL takes 8 GB and never gives it back; on an 8 GB laptop it takes 4 GB, which is too little for EJBCA's first boot.

## 2. Get the code and open the right shell

Two ways to run everything; pick one and stay with it.

**A. Windows-native (no shell knowledge needed).** Every step below has a
`.cmd` twin in `demo\` that you double-click in Explorer or run from
PowerShell/cmd: `demo\setup-once.cmd`, `demo\up.cmd` (or `demo\up.cmd --check`),
`demo\checklist.cmd`, `demo\reset.cmd`, `demo\import-images.cmd`. They locate
Git for Windows' bash themselves and keep the window open so you can read the
verdict. Only `git clone` still needs a terminal (PowerShell is fine for that).

**B. Git Bash.** Open the **Git Bash** app (Start menu → "Git Bash") and run the
`bash …` commands as written. Not PowerShell's `bash` (that is WSL), not
WSL/Ubuntu — docker and paths behave differently there, and the preflight
refuses to run.

```bash
cd /c && mkdir -p lab && cd lab
git clone https://github.com/vanhoanHoang/ai-agent-spiffe-token-exchange.git spiffe-mcp-lab
cd spiffe-mcp-lab            # main is the demo branch
```

Path rules: no `&` in the path (`C:\lab\spiffe-mcp-lab` is right). Do **not**
copy the folder from the old machine instead of cloning: it would carry the old
machine's CA files (gitignored) without its docker volumes, and the two are one
unit — the preflight detects this and tells you what to delete.

## 3. Images from the USB stick (optional, saves the build)

```bash
bash demo/import-images.sh /e/spiffe-lab     # wherever the stick is mounted in Git Bash (/d, /e, ...)
```

## 4. The LLM key

PowerShell, from the repo root:

```powershell
Copy-Item infra\.env.example infra\.env
notepad infra\.env          # paste the gsk_ key from console.groq.com/keys, save as UTF-8
```

Or copy the `infra/.env` you brought on the stick. The key is never in git: the
template `infra/.env.example` is committed, the filled-in `infra/.env` is
gitignored. If Notepad asks, choose **UTF-8** (not "UTF-8 with BOM"); never create
the file with a PowerShell `>` (that writes UTF-16). The preflight checks the
encoding and prints the provider it actually read.

No `.env` means the local Ollama model: a 2–3 GB pull and slow CPU answers.

## 5. Hosts file (once; admin)

Admin PowerShell (right-click → Run as administrator):

```powershell
Add-Content C:\Windows\System32\drivers\etc\hosts "`n127.0.0.1 keycloak"
```

The browser login redirects to `http://keycloak:8080`; without this line the
login page never loads.

## 6. One-time artifacts (human-run, ~10–15 min, mostly EJBCA waiting)

```bash
bash infra/spire/gen-bootstrap.sh          # seconds
bash infra/pki/setup-ejbca.sh              # minutes: EJBCA first boot + CA hierarchy
bash infra/pki/setup-employee-profile.sh   # employee profiles + RA credential
```

Windows-native: `demo\setup-once.cmd` runs the three in order and stops at the first failure.

They create gitignored files under `infra/spire/bootstrap/` and `infra/pki/`
and the `ejbca-data` volume. They are idempotent; re-running is safe.

## 7. Launch and verify

```bash
bash demo/up.sh --check     # preflight only: every line OK, or a fix line
bash demo/up.sh             # preflight → reset --full → checklist --full; last line is the verdict
```

Windows-native: `demo\up.cmd --check`, then `demo\up.cmd` (double-click runs the full launch).

Then open **http://localhost:8090**, log in `alice` / `alice-password`, and run
the demo prompt once end to end ("onboard employee …") **before** the audience
arrives: the first Groq call and the consent step-up are the two things you
want to have seen work on this machine.

## 8. Day-of checklist (2 minutes, every time the laptop woke up)

```bash
bash demo/checklist.sh      # clock skew FIRST, health, model reachable, ports, hosts
```

Clock skew after sleep/hibernate is the most common "everything was fine
yesterday" failure: JWTs are refused as not-yet-valid or expired. Fix in
PowerShell: `wsl --shutdown`, then restart Docker Desktop, then
`bash demo/reset.sh --soft`.

Recovery ladder: `demo/reset.sh --soft` (app layer, < 2 min) → `--full`
(compose down/up, volumes kept, ~3 min) → `--cold` (destroys CA state, asks
first, re-runs step 6 for you).

## Failures seen on Windows, and the fix

| Symptom | Cause | Fix |
|---|---|---|
| `bash: docker: command not found` or paths like `/c/Users` misbehave | You are in WSL bash (from PowerShell) | Open the Git Bash app. The preflight refuses WSL. |
| `bind: An attempt was made to access a socket in a way forbidden by its access permissions` on 8080/8443/… while nothing listens | Windows reserved a Hyper-V/WSL port range | Admin PowerShell: `net stop winnat; netsh int ipv4 add excludedportrange protocol=tcp startport=8080 numberofports=1; net start winnat` (preflight prints the port). |
| `port is already allocated` | Another stack holds the port | `docker ps --format '{{.Names}}\t{{.Ports}}'`, stop the holder. |
| Chat works but the model is Ollama although `.env` says Groq; or agent-web dies with `No qualifying bean of type ChatModel` | `.env` has CRLF, a UTF-8 BOM or is UTF-16 | Save as plain UTF-8 (CRLF is now tolerated). Preflight checks the encoding and prints the effective provider. |
| `agent-web` crashloops with `Realm does not exist` | Bare `docker compose up` after a `down` | Always launch through `demo/up.sh` or `demo/reset.sh` (they re-run the idempotent realm setup). |
| Login page never loads / browser cannot reach `keycloak` | Hosts entry missing | Step 5. |
| `! agent-web Warning pull access denied for spiffe-mcp-lab-agent-client ... may require 'docker login'` during `up`, then `http2: server: error reading preface from client //./pipe/dockerDesktopLinuxEngine: file has already been closed` | Neither is a failure. Compose asked a registry for a locally built image before using it; the second line is Docker Desktop pipe noise on Windows. | Fixed: `agent-web` is `pull_policy: never`. If you still see it, the checkout predates the fix; the run continues anyway (watch for `Running 8/8`). |
| Every JWT refused, `check` shows clock skew > 30 s | WSL clock drifted after sleep | `wsl --shutdown`, restart Docker Desktop, `demo/reset.sh --soft`. |
| `unable to find valid certification path` between containers | CA files and volumes from different machines (folder copied) | Delete `infra/pki/*.pem infra/pki/ra/ infra/spire/bootstrap/`, `docker volume rm spiffe-mcp-lab_ejbca-data`, re-run step 6. Preflight detects the mismatch. |
| EJBCA setup "waits forever" | First boot on a slow disk / too little memory | Give it 10 min; check `docker stats`; set `.wslconfig` memory to 6 GB. |
| Image build fails with a download error | No internet / corporate proxy | Import the images from USB (step 3), or build at home first and export. |
| Groq answers `401` / model not in catalog | Wrong key, or the model pin changed | New key at console.groq.com/keys; `bash scripts/check-llm-provider.sh` names the missing model. |
| Groq answers `429` | Free-tier rate limit (about 30 requests/min) | Wait a minute; one presenter never hits it in normal use. |
| `python` opens the Microsoft Store | Windows app-execution alias | Install Python from python.org, or Settings → Apps → Advanced app settings → App execution aliases → turn off `python.exe`. Only the check scripts need it. |
| Windows Defender Firewall prompt on first launch | Docker binding host ports | Allow for private networks. |

Machine-local by design and never copied between machines: SPIRE bootstrap
CA, EJBCA hierarchy, RA keystore, docker volumes, the Ollama model. A new
laptop is a new lab with its own root CA; the trust domain stays the same.
