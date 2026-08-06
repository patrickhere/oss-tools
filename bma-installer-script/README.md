# BMA Installer — source of truth

This folder is the canonical template for the per-client BMA installer. Everything
below `#DON'T TOUCH BELOW THIS LINE` in `BMAInstallerScript.ps1` is identical across
every client. Only the three values above that line change per client/branch.

## Files

- `BMAInstallerScript.ps1` — downloads the BMA package for the machine's role
  (workstation vs. server), runs `BMAInstaller.exe`, and verifies the BMA services
  came up. Redacts secrets from captured installer output before logging.
- `RunBMAInstaller.bat` — **manual** launcher for a tech running the install by hand.
  Self-elevates to Administrator, runs the script, and reports the PowerShell exit
  code. Pass `/dryrun` to validate without downloading or installing. Not for GPO
  (see Deployment).

## Deployment

**GPO startup policy (primary).** Point the policy at `BMAInstallerScript.ps1`
directly — Computer Configuration > Policies > Windows Settings > Scripts > Startup >
**PowerShell Scripts** tab. For this path:

- Runs as **SYSTEM**, which is elevated and passes the script's Administrator check,
  so `RunBMAInstaller.bat` is not involved.
- Runs on **every boot** and is safe to: once the BMA services are running the script
  exits early (code 0) without re-downloading, and the log self-rotates at 1 MB.
- The session is **non-interactive** — the `.ps1` never prompts, so it can't hang.
- Enable **"Always wait for the network at computer startup and logon"** (Computer
  Config > Admin Templates > System > Logon) so the first-boot download isn't skipped
  before networking is up. If it is skipped, the next boot retries.
- If script execution is locked down, use the PowerShell Scripts tab (it honors the
  execution-policy GPO) or wrap the call as
  `powershell -NoProfile -ExecutionPolicy Bypass -File <path>`.
- **Do not** point GPO at `RunBMAInstaller.bat` — its self-elevation and `pause` are
  interactive-only and will hang a startup script.

**Manual (fallback).** Double-click `RunBMAInstaller.bat` (self-elevates, runs the
script, shows the exit code, waits for a keypress). Add `/dryrun` to validate first.

## BMA Interface (system-tray app)

After a fresh core install, the script also makes sure the **BMA Interface** tray app
(`C:\Program Files\BankOnIT\BMA\BMA Interface\BMAInterface.exe`) is in place. The core
installer normally handles this, so this is a safety net:

- If `BMAInterface.exe` is missing, it deploys the files from `BMAInterface.zip`
  (extracted with the rest of the payload), flattening the zip's internal subfolder so
  the exe lands directly in `BMA Interface\`.
- It registers an autostart (HKLM `...\Run`) so the tray app starts **in the user's
  session at logon** — but only if nothing already starts it, to avoid a duplicate tray
  icon. A tray icon can't appear in the SYSTEM/session-0 context a startup script runs in,
  so the script never launches it there; it launches immediately only when a tech runs it
  interactively via `RunBMAInstaller.bat`.

Runs **only during a fresh core install** — on a machine where BMA core is already running
the script exits early and does not re-check the interface. Interface deployment is
best-effort and logged; it does not change the exit code.

## Stamping a new client

1. Copy this whole folder to a new `CLIENTID` folder.
2. In `BMAInstallerScript.ps1`, set the three values at the top:
   ```powershell
   $ClientNumber   = "CLIENTID"          # institution / client id
   $ClientPassword = 'W@lk....Miles'     # BMAv3 client secret (BMP > Credentials > Misc)
   $BMASite        = 1                   # branch number (HQ = 1, next branch = 2, ...); from SmartTrak
   ```
3. Leave everything below `#DON'T TOUCH BELOW THIS LINE` unchanged.

   If a client has multiple branches, use one installer folder per branch, each with
   its own `$BMASite`.

`RunBMAInstaller.bat` is generic — copy it as-is; it calls the `.ps1` next to it.

## Exit codes

`RunBMAInstaller.bat` and RMM tooling key alerting off the PowerShell exit code:

| Code | Meaning                                            |
|------|----------------------------------------------------|
| 0    | Success, desired state already met, or dry run     |
| 1    | Not elevated (Administrator required)              |
| 2    | Unsupported OS product type                        |
| 3    | Download or extract failed                         |
| 4    | Installer missing after extract                    |
| 5    | Installer failed to launch                         |
| 6    | Install ran but BMA services are not running       |

## Dry run

```
RunBMAInstaller.bat /dryrun
```

Walks every pre-flight check and logs what a real run would do, without downloading
or installing anything.

## Log

`C:\BankOnIT\Logs\BMAInstall_Log.txt` (rolls to `.1` past 1 MB).

## Deployed clients

Folders currently built from this template:

- `ABCOGCLEVELAND/bma-installer/`
- `CWBFRESNO/`
- `HBSTPAUL/`
- `MABBALDWIN/` — ⚠ `$ClientPassword` is still the placeholder
  `REPLACE-WITH-BMP-CLIENT-SECRET`. Fill it in from BMP (Credentials > Misc)
  before deploying. The old `MABBALDWIN/BMAInstaller/` binaries + `Install.bat`
  remain as a manual fallback until this is done, then can be deleted.
- `SBOCCherry/`

> The generic bundled installer kept under `bma-installer-template/bma-installers-archive/`
> uses the older interactive `Install.bat` + bundled-binaries method and is **not**
> built from this template — it's retained only as a manual reference.
