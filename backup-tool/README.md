# BankOnIT Backup Utility

Original script by **redacted**, maintained by **Patrick Hart**.  
Primary location for technicians: `R:\Travel Team\Tools\Backup\`

---

## 1. Field Guide (Which Script to Use)

- **`Backup.bat` (root)**
  - Everyday use on a running Windows machine.
  - Double-click → it will **auto-elevate** to admin.
  - Calls `scripts\Backup.ps1` (full feature set, toggles, color output, logging).

- **`scripts\Backup_Hirens.bat`**
  - When Windows **won't boot** or you're working from **Hiren's** / other rescue media.
  - Run from the backup USB / drive where this folder is copied.
  - Asks for Windows drive letter and user; logs to `Backups\<hostname>\backuplog.txt`.

---

## 2. Quick SOP (Standard Operating Procedure)

### A. Normal Backup (`Backup.bat`)

1. **Get the tool**
   - Browse to: `R:\Travel Team\Tools\Backup\`
   - Copy the entire `Backup` folder to your external drive.

2. **Run**
   - In the `Backup` folder, double-click `Backup.bat`.
   - Accept the **UAC elevation** prompt, if it does.

3. **Choose backup destination (optional)**
   - Default: `Backups\` next to the script (or a path configured by IT).
   - During the run, the script will show:

     ```text
     Backup destination root:
       Current default: X:\SomePath
     Override destination (leave blank to accept default):
     ```

   - **Press Enter** to accept the suggested path, or **type a new path** such as:
     - `E:\Backups`
     - `E:\Travel-Backups\%COMPUTERNAME%`
     - `\\fileserver\BankOnIT\PC-Backups\%COMPUTERNAME%`

4. **Enter user + toggles**
   - When prompted for user, leave blank to use current login.
   - Optional components (defaults in brackets; just press Enter to accept):
     - Run Belarc scan? `[Y]`
     - Launch Transwiz? `[Y]`
     - Copy Public Desktop? `[Y]`
     - Capture `ipconfig /all`? `[Y]`

5. **Verify summary**
   - At the end you'll see:

     ```text
     ===== Backup Summary =====
     Warnings logged : X
     Errors logged   : Y
     ```

   - **Errors must be 0** before you call it good.
   - If `Warnings` or `Errors` are non-zero, open:
     - `Backups\<COMPUTER_NAME>\backuplog.txt`

6. **What to hand off to engineering**
   - The entire `Backups\<COMPUTER_NAME>\` folder, or at minimum:
     - `backuplog.txt`
     - `<COMPUTER_NAME>.html` (Belarc)
     - `ipconfig.txt` (if captured)
     - `Restore (run as admin).bat`
     - `restore_exclude.txt`
     - Any `.trans.zip` created by Transwiz

### B. Hiren's / Offline Backup (`scripts\Backup_Hirens.bat`)

1. Boot Hiren's or rescue media and ensure this `Backup` folder is available.
2. Launch `scripts\Backup_Hirens.bat`.
3. When asked:
   - Enter **Windows drive** (usually `C`).
   - Enter **username** to back up.
4. Script will:
   - Install/run Belarc, copy report.
   - Copy Public Desktop from the selected drive.
   - Run Transwiz.
   - Capture `ipconfig /all`.
   - Rename the backup folder based on the "old computer name" you provide.
5. Results and log are under:
   - `Backups\<hostname>\`

---

#
  ```

Notes:

- If **no destination is specified** and `BACKUP_DEST` is not set, the script defaults to:
  - `./Backups/` under the `Backup` folder where you ran it.
- For unstable disks or flakey USB, prefer:
  - Local `Backups/` first, then copy results to `R:` or other storage afterward.

