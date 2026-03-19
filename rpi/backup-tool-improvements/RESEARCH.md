# research: backup tool improvements

## requirements

**goal:** improve the existing BankOnIT backup tool to be more robust, consistent with the OSS toolkit style, and better suited to real onsite workflows.

**scope:**
- in: bug fixes, additional backup targets, disk space check, multi-user support, client name integration, README rewrite, repo cleanup
- out: full rewrite, new third-party tooling, cloud upload, restore workflow changes

**constraints:**
- must stay .bat based (runs on any windows 10/11 machine with no prereqs)
- must stay compatible with Hiren's / rescue media workflow
- should align with OSS toolkit patterns where it makes sense

**success criteria:**
- no known bugs
- consistent style with oss-tools
- technician can run it start-to-finish without confusion
- useful output for both field tech and engineering handoff

---

## codebase analysis

**structure:**
```
backup-tool/
  Backup.bat                    -> self-elevating wrapper, calls scripts\Backup.bat
  Backup_Hirens-note.bat        -> self-elevating wrapper, calls scripts\Backup_Hirens.bat
  scripts/
    Backup.bat                  -> main backup logic (normal windows)
    Backup_Hirens.bat           -> rescue media variant
  assets/
    IGNORE.bat                  -> restore batch template (copied to backup folder)
    bin/
      advisorinstaller.exe      -> belarc advisor installer
      Start_Belarc.ps1          -> silent belarc install (normal)
      Start_Belarc_Hirens.ps1   -> silent belarc install (hirens, X: drive)
      Transwiz_free.exe         -> user profile migration tool
      Transwiz.exe              -> (same, alternate name)
      Transwiz.config
      Backup_old.bat            -> legacy, unused
    txt/
      backup_exclude.txt        -> xcopy exclusion list (just "AppData")
      backup_exclude_chrome.txt -> xcopy exclusion list for chrome (Cache, Code Cache)
      IGNORE.txt                -> restore exclusion template
```

**what it backs up (normal mode):**
- belarc advisor HTML report (installs belarc if missing, runs scan)
- transwiz user profile package (.trans.zip)
- public desktop contents (xcopy with exclude list)
- ipconfig /all output

**what was planned but commented out (Backup_Hirens.bat):**
- outlook signatures, templates, AppData\Roaming\Microsoft\Office
- AppData\Local\Microsoft\Outlook
- firefox profile
- chrome profile (with chrome-specific exclude list)

**known bugs:**
1. `Backup_Hirens.bat` line 63: `>> "%LOG_PATH"` is missing the closing `%` -> log redirect silently fails for the belarc ps1 call
2. `Backup_Hirens.bat` hostname rename logic is fragile -> if run twice for a second user, the `rename` command will fail on the second pass since the folder was already renamed
3. README section 3 is broken -> just `#` followed by a dangling code block, content was never written

**style gaps:**
- README uses title case, em dashes, old R: drive path reference (`R:\Travel Team\Tools\Backup\`)
- no version number
- no BankOnIT OSS branding tagline (unlike all oss-tools scripts)
- backup-tool is sitting inside the oss-tools repo rather than being its own thing

**good things to keep:**
- the `promptToggle` helper in scripts\Backup.bat is clean and reusable
- the `:log` + `:summarizeLog` pattern is solid
- backup destination override prompt is well-designed
- self-elevation wrappers work correctly

---

## technical feasibility

all improvements are straightforward .bat / .ps1 changes. no new dependencies needed.

**complexity: moderate**

specific items:
- bug fixes: trivial
- disk space check: moderate (wmic or powershell one-liner)
- multi-user loop: moderate (add a loop around the user prompt)
- client name integration: trivial (match OSS toolkit pattern)
- commented-out AppData targets: moderate (need to decide which ones to actually implement vs remove)
- repo split: trivial (move folder, new forgejo repo)
- README rewrite: trivial

---

## infrastructure impact

- backup-tool should be its own forgejo repo (`backup-tool`) separate from `oss-tools`
- currently lives at `oss-tools/backup-tool/` which is wrong -> it was orphaned there when work-tools was deleted
- no other infra impact

---

## risks

- belarc advisor is bundled as a binary -> if the license or installer goes stale, that workflow breaks silently. low risk for now but worth noting.
- transwiz_free.exe is a third-party binary with no version pinning -> same concern
- xcopy exclusion lists are minimal (just "AppData" and Chrome cache) -> if someone backs up a large profile to a small USB, it will fill up. disk space check would mitigate this.
- hostname rename logic in Backup_Hirens.bat is error-prone for multi-user runs -> needs to be rethought before enabling multi-user support there

---

## recommendation

**GO**

the tool is functional and already used in production. improvements are well-scoped and low risk. priority order:

1. fix the two known bugs
2. split into its own repo
3. rewrite README in patrick's style
4. add disk space check
5. add client name / visit context field (align with OSS toolkit)
6. add branding tagline to both scripts
7. decide on commented-out AppData targets -> either implement or remove
8. add multi-user loop (normal mode only, hirens mode is already one-user-at-a-time by design)
