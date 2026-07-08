# navanta backup tool

---

## which script to use

**`Backup.bat`** -- normal use on a running Windows machine. double-click, accept UAC, done.

**`scripts\Backup_Hirens.bat`** -- machine won't boot or you're in Hiren's. asks for the Windows drive letter and username.

---

## running a backup

1. copy the `Backup` folder to your external drive.
2. double-click `Backup.bat`, accept UAC.
3. set the destination -- default is `Backups\` next to the script. can also take a UNC path like `\\pc-name\c$\Navanta\backups\`.
4. hit enter through the component prompts (all default to Y) or type N to skip any.
5. Belarc will open a browser window -- leave it open, the script picks up the report automatically.
6. Transwiz opens as a wizard -- work through it, the script waits for it to finish.
7. check the summary at the end. errors must be 0.
8. if anything looks off, the log is at `Backups\<COMPUTER_NAME>\backuplog.txt`.

---

## running a restore

the backup folder contains `Restore (run as admin).bat` and `Restore.ps1`. run the .bat from wherever the backup lives -- local drive, USB, or UNC share (`\\pc-name\c$\...`).

1. on the new PC, navigate to the backup folder.
2. double-click `Restore (run as admin).bat`, accept UAC.
3. hit enter through the component prompts (all default to Y except local staging).
4. **local staging** (default N) -- robocopy's the entire backup folder to `C:\Navanta\Restore\<pc-name>\` before restoring. useful for large profiles or slow network links. not needed on a fast LAN.
5. Transwiz opens as a wizard -- point it at the `.trans.zip` in the source folder and work through it.
6. browser bookmarks (Edge, Chrome) are restored automatically. Firefox bookmarks are copied to `C:\Navanta\Firefox\<username>\` -- import manually via Firefox > Bookmarks > Manage Bookmarks > Import and Backup > Restore.
7. old computer files (Belarc report, ipconfig, MappedDrives.reg) are moved to `C:\Navanta\Old Computer\`.
8. check the summary. restore log is at `C:\Navanta\restorelog.txt`.

---

## notes

- UNC paths work as both backup destinations and restore sources -- no copy step needed.
- set `BACKUP_DEST` as an environment variable to override the default destination without typing it every time.
- Belarc can only recover the last 5 characters of M365 product keys -- this is a Belarc limitation.
- for flaky USB drives, back up locally first then copy to `R:` after.
