# BankOnIT Backup Utility

Original script by **redacted**, rewritten in PowerShell by **Patrick Hart**.
Primary location for technicians: `R:\Travel Team\Tools\Backup\`

---

## 1. Field Guide (Which Script to Use)

- **`Backup.bat` (root)**
  - Everyday use on a running Windows machine.
  - Double-click -- it will **auto-elevate** to admin.
  - Calls `scripts\Backup.ps1` (color output, toggles, logging, summary).

- **`scripts\Backup_Hirens.bat`**
  - When Windows **won't boot** or you're working from **Hiren's** / other rescue media.
  - Run from the backup USB / drive where this folder is copied.
  - Asks for Windows drive letter and user; logs to `Backups\<hostname>\backuplog.txt`.

---

## 2. Quick SOP -- Normal Backup (`Backup.bat`)

1. **Get the tool**
   - Browse to: `R:\Travel Team\Tools\Backup\`
   - Copy the entire `Backup` folder to your external drive.

2. **Run**
   - Double-click `Backup.bat` in the `Backup` folder.
   - Accept the UAC elevation prompt.

3. **Choose backup destination**
   - Default is `Backups\` next to the script. Press Enter to accept, or type a path:
     - `E:\Backups`
     - `\\fileserver\BankOnIT\PC-Backups`
   - The script validates the destination and warns if space is low.

4. **Select optional components**
   - All default to Yes -- press Enter to accept each, or type `N` to skip:
     - Run Belarc Advisor scan? `[Y]`
     - Launch Transwiz? `[Y]`
     - Copy Public Desktop? `[Y]`
     - Capture `ipconfig /all`? `[Y]`

5. **Belarc note**
   - A browser window will open with the Belarc report -- this is expected.
   - Leave it open. The script polls for the report file for up to 90 seconds then moves on.

6. **Transwiz note**
   - Transwiz opens as a wizard. Work through it to completion.
   - The script waits up to 30 minutes for it to finish.

7. **Check the summary**
   - At the end the script shows a color-coded summary:

     ```
     ==================================================
       Component          Status
       -----------------  -------
       Belarc             RAN
       Transwiz           RAN
       Public Desktop     RAN
       ipconfig           RAN
       Restore Assets     RAN

       Warnings : 0
       Errors   : 0
     ==================================================
     ```

   - **Errors must be 0** before you call it good.
   - Non-zero warnings or errors -- open `Backups\<COMPUTER_NAME>\backuplog.txt`.

---

## 3. Hiren's / Offline Backup (`scripts\Backup_Hirens.bat`)

1. Boot Hiren's or rescue media and ensure this `Backup` folder is available.
2. Launch `scripts\Backup_Hirens.bat`.
3. When asked, enter the Windows drive letter (usually `C`) and the username to back up.
4. Results and log are under `Backups\<hostname>\`.

---

## 4. Notes

- Destination can be a local path or UNC share (`\\server\share`). Both are validated before the run starts.
- If `BACKUP_DEST` environment variable is set, it is used as the default destination.
- For unstable disks or flaky USB drives, back up to local `Backups\` first, then copy to `R:` afterward.
- Belarc cannot recover full M365/Office 365 product keys -- only the last 5 characters are shown. This is a Belarc limitation, not a script issue.
