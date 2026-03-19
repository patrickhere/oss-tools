# bankonit oss toolkit

portable scripts for fixing common outlook, office, and windows issues on bank branch machines. built for onsite visits -> drop it on a usb stick, run `launcher.bat`, pick a tool.

supports on-premises exchange, microsoft 365, and hybrid environments. environment-sensitive scripts adjust their behavior based on what you select at startup.

**not for use on servers.**

---

## requirements

- windows 10 or 11
- most scripts require admin -> the launcher handles self-elevation automatically
- no powershell profile or execution policy changes needed -> scripts run with `-ExecutionPolicy Bypass`

---

## how to use

1. download or clone this repo
2. copy the folder to a usb stick (or run it directly from wherever)
3. double-click `launcher.bat` -> it will self-elevate if needed
4. select the client's mail environment when prompted
5. enter the client name / branch (used in output filenames and the session log)
6. pick a tool from the menu

to package it as a zip for sharing, run `package.bat` -> drops a zip on your desktop.

---

## tools

### fixes

| # | tool | what it does | needs admin |
|---|------|--------------|:-----------:|
| 1 | outlook autodiscover | configures autodiscover registry keys for on-prem, m365, or hybrid | yes |
| 2 | block aad workplace join | suppresses the "your org wants to manage this device" entra id prompt | yes |
| 3 | disable wam | disables web account manager for office auth -> on-prem only, warns on m365/hybrid | yes |
| 4 | credential cleanup | removes stale exchange/office entries from windows credential manager | no |
| 5 | outlook profile rebuild | deletes outlook profile(s) from registry so outlook prompts for fresh setup | no |
| 6 | clear office cache | clears office identity, license, and token broker cache | no |
| 7 | reset teams cache | clears teams cache folders | no |
| 8 | flush dns / winsock reset | flushes dns cache and resets winsock (reboot required after) | yes |
| 9 | reset outlook nav pane | launches outlook with /resetnavpane to fix a corrupt navigation pane | no |
| 10 | fix print spooler | clears the spool queue and restarts the spooler service | yes |

### config

| # | tool | what it does | needs admin |
|---|------|--------------|:-----------:|
| C1 | disable teams auto-install | prevents consumer teams from auto-installing on first logon | yes |
| C2 | disable onedrive auto-install | prevents consumer onedrive from auto-installing | yes |
| C3 | disable ms account sign-in | blocks personal microsoft account prompts in office | yes |
| C4 | disable update auto-reboot | stops windows update from rebooting mid-day when users are logged in | yes |
| C5 | edge ie mode sites | enables ie compatibility mode in edge and manages a local site list | yes |

### diag

run these first if you're not sure what you're dealing with. output saves to a timestamped `.txt` file in the `Logs\` folder next to `launcher.bat`, named with the client name you entered at startup.

| # | tool | what it does |
|---|------|--------------|
| D1 | system snapshot | os version, domain info, office version, and key registry values |
| D2 | exchange connectivity | tests dc reachability, autodiscover dns, and m365 endpoint connectivity |
| D3 | outlook config dump | exports outlook-related registry keys to a file for before/after comparison |
| D4 | office license status | checks office activation state via ospp.vbs |
| D5 | event log errors | pulls the last 100 errors from application and system logs (past 24h) |
| D6 | network info | ip, gateway, dns servers, dhcp status, and lease info for active adapters |
| DA | run all diag | runs d1-d6 in sequence, all output files go to `Logs\` |

---

## session log

every tool you run gets logged to `Logs\OSS-session-log.txt` in the toolkit folder:

```
2026-03-18 14:23:11 | WORKSTATION01 | FirstNational-Downtown | onprem | system-snapshot
2026-03-18 14:24:05 | WORKSTATION01 | FirstNational-Downtown | onprem | outlook-autodiscover
```

gives you a record of what was done during the visit without having to write anything down.

---

## environment behavior

when you select an environment at startup, a few tools change how they behave:

- **autodiscover** -> blocks cloud endpoints on-prem, removes blocks on m365, sets hybrid-safe config for hybrid
- **disable wam** -> applies on-prem, exits with a warning on m365 (would break auth), prompts before applying on hybrid
- **block aad workplace join** -> applies on-prem, prompts with a warning before applying on m365 or hybrid (can break conditional access)
- **exchange connectivity** -> tests different endpoints depending on environment

---

## packaging for sharing

run `package.bat` to create `BankOnIT-OSS.zip` on your desktop. no git or powershell knowledge needed on the receiving end -> just unzip and run.

---

built by patrick hart -> [hartforge.dev](https://hartforge.dev)
