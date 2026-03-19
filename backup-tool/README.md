# bankonit backup tool

---

## which script to use

**`Backup.bat`** -- normal use on a running Windows machine. double-click, accept UAC, done.

**`scripts\Backup_Hirens.bat`** -- machine won't boot or you're in Hiren's. asks for the Windows drive letter and username.

---

## running a backup

1. copy the `Backup` folder to your external drive.
2. double-click `Backup.bat`, accept UAC.
3. set the destination -- default is `Backups\` next to the script. can also take a UNC path like `\\pc-name\c$\BankOnIT\backups\`.
4. hit enter through the component prompts (all default to Y) or type N to skip any.
5. Belarc will open a browser window -- leave it open, the script picks up the report automatically.
6. Transwiz opens as a wizard -- work through it, the script waits for it to finish.
7. check the summary at the end. errors must be 0.
8. if anything looks off, the log is at `Backups\<COMPUTER_NAME>\backuplog.txt`.

---

## notes

- UNC paths work as destinations -- the script validates write access before starting.
- set `BACKUP_DEST` as an environment variable to override the default destination without typing it every time.
- Belarc can only recover the last 5 characters of M365 product keys -- this is a Belarc limitation.
- for flaky USB drives, back up locally first then copy to `R:` after.
