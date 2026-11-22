# Practice DC for Sunday: note

One script turns a fresh Windows Server 2022 VM into the practice domain controller for the AD security lab. You run it once, and it does the rest by itself.

## The fastest way: build one, then clone it

1. Make **one** Windows Server 2022 VM in Proxmox.
   - Edition: **Standard Evaluation (Desktop Experience)**. It must say Desktop Experience.
   - 4 GB memory, 2 cores, 50 GB disk.
   - Set any Administrator password during setup. The script replaces it.
2. Get `Build-PracticeDC.ps1.txt` onto the VM and rename it to `Build-PracticeDC.ps1`.
3. Log in as Administrator. Right-click Start, then **Windows PowerShell (Admin)**.
4. Go to the folder with the file and run **one** of these.

   If each student VM will be on its **own isolated network**:
   ```
   powershell -ExecutionPolicy Bypass -File .\Build-PracticeDC.ps1
   ```
   If the student VMs will **share one network** (the usual range bridge):
   ```
   powershell -ExecutionPolicy Bypass -File .\Build-PracticeDC.ps1 -SharedNetwork
   ```
5. Walk away. The VM restarts by itself **two times**. It takes 15 to 25 minutes.
6. Log in as `PRACTICE\Administrator` with the password `Practice-DC1-2026!`
7. A file named **PracticeDC build result.txt** is on the desktop. It must say **BUILD FINISHED OK**.
8. Delete that file, shut the VM down, and take a snapshot named **seeded**.
9. Convert the VM to a template and make one full clone per student.

Running the script on every VM one by one also works. Cloning is less work and guarantees they are identical.

## Why the network choice matters

Every VM is named `DC1` in the domain `practice.local` on purpose, so that every command in the lab matches. Identical Windows machines on one network fight over the name. `-SharedNetwork` turns off NetBIOS on the VM's network cards, which stops that. If each VM is on its own isolated network, leave the switch off.

Students only need the Proxmox console. The VMs do not need the internet during the lab.

## What the script does

| Step | What happens |
|---|---|
| 1 | Sets the Administrator password to the one on the lab card, installs the Active Directory role, renames the computer to `DC1`, restarts |
| 2 | Makes the server a domain controller for `practice.local`, restarts |
| 3 | Plants the four weak accounts the lab uses, turns on the audit logging the lab reads, checks everything, and writes the result file |
| End | Removes its startup task, clears the PowerShell history and logs, and deletes itself |

## If the result file says BUILD DID NOT FINISH

It lists what is wrong. Open **Windows PowerShell (Admin)** and run:

```
powershell -ExecutionPolicy Bypass -File C:\PracticeDC\Build-PracticeDC.ps1
```

That repeats only the last step. If it is still wrong, send `C:\PracticeDC\build.log` to Josh. The log holds no passwords.

## Two cautions

- The passwords inside the script are fake and weak on purpose. They are what the students are meant to find. Do not post the script where students can read it before Sunday.
- Never run it on a real server. It makes the machine weak on purpose.
