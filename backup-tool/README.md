# BankOnIT Backup Tool

PowerShell rewrite of the original batch script by redacted.
Primary location: `R:\Travel Team\Tools\Backup\`

---

## Which script to use

**`Backup.bat`** -- normal use on a running Windows machine. Double-click, accept UAC, done.

**`scripts\Backup_Hirens.bat`** -- machine won't boot or you're in Hiren's. Asks for the Windows drive letter and username.

---

## Running a backup

1. Copy the `Backup` folder to your external drive.
2. Double-click `Backup.bat`, accept UAC.
3. Set the destination -- default is `Backups\` next to the script. Can also take a UNC path like `\\pc-name\c$\BankOnIT\backups\`.
4. Hit Enter through the component prompts (all default to Y) or type N to skip any.
5. Belarc will open a browser window -- leave it open, the script picks up the report automatically.
6. Transwiz opens as a wizard -- work through it, the script waits for it to finish.
7. Check the summary at the end. Errors must be 0.
8. If anything looks off, the log is at `Backups\<COMPUTER_NAME>\backuplog.txt`.

---

## Notes

- UNC paths work as destinations -- the script validates write access before starting.
- Set `BACKUP_DEST` as an environment variable to override the default destination without typing it every time.
- Belarc can only recover the last 5 characters of M365 product keys -- this is a Belarc limitation.
- For flaky USB drives, back up locally first then copy to `R:` after.
