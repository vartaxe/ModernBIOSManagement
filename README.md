# ModernBIOSManagement

For implementation instructions, please go to https://www.msendpointmgr.com/modern-bios-management

## Branch: feature/dell-force-bios-flash-recovery

Adds support for forcing a Dell BIOS flash (and the corresponding package download) so that the NVMe-stored BIOS recovery image can be recreated after an OSD reimage on newer Dell Pro / Dell S / Precision models (Dell KB 000467636).

### Changes

- **Invoke-DellBIOSUpdate.ps1** (v1.2.0)
  - New optional parameter `-Force`
  - Adds `/f` to Flash64W.exe (and 32-bit fallback) when `-Force` is used or when the task-sequence variable `SMSTSForceDellBIOSFlash` is set to `True`
  - Default behaviour remains without `/f`

- **Invoke-CMDownloadBIOSPackage.ps1** (v3.0.5)
  - See `ForceDownload.patch` for the exact diff against current main
  - New optional parameter `-ForceDownload`
  - Also resolved from TS variables `SMSTSForceDellBIOSFlash` or `SMSTSForceBIOSDownload`
  - When active, the matched BIOS package is downloaded even if the installed version is already current (so the force-flash step has the required content)

### Task Sequence usage

```
Set Task Sequence Variable
  Name:  SMSTSForceDellBIOSFlash
  Value: True

# then the normal steps
Invoke-CMDownloadBIOSPackage.ps1 ...
Invoke-DellBIOSUpdate.ps1          # -Force optional if the TS variable is set
```

### How to obtain the full download script

Apply the supplied `ForceDownload.patch` to the current `Invoke-CMDownloadBIOSPackage.ps1` from main, or request the full expanded file from the author of this branch.
