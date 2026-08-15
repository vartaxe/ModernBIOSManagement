# ModernBIOSManagement (fork with Dell force-flash support)

For original implementation instructions see: https://www.msendpointmgr.com/modern-bios-management

## Dell NVMe recovery image recreation (this fork)

Newer Dell Pro / Dell S / Precision models store the BIOS recovery image on NVMe.
After a clean OSD the image is wiped. Re-running the BIOS flash (even on the same version)
recreates it (Dell KB 000467636).

### What changed

| Script | Change |
|--------|--------|
| `Invoke-DellBIOSUpdate.ps1` | v1.2.0 – optional `-Force` (adds `/f`). Also respects TS var `SMSTSForceDellBIOSFlash=True` |
| `Invoke-CMDownloadBIOSPackage.ps1` | Apply `ForceDownload.patch` to get v3.0.5 – optional `-ForceDownload` so the package is staged even when version is current |

### Task Sequence usage

```
Set Task Sequence Variable
  Name:  SMSTSForceDellBIOSFlash
  Value: True

# then normal steps
Invoke-CMDownloadBIOSPackage.ps1 ...
Invoke-DellBIOSUpdate.ps1          # -Force optional when TS var is set
```

### Enabling -ForceDownload on the download script

The included `Invoke-CMDownloadBIOSPackage.ps1` is the base (v3.0.4).
Apply the small patch to add `-ForceDownload` + TS variable support:

```powershell
# From the repo root (or copy the .ps1 + .patch somewhere)
# On Linux / Git Bash:
patch -p0 < ForceDownload.patch

# Or on Windows PowerShell (requires git):
git apply ForceDownload.patch
```

After applying, the script becomes v3.0.5 with:
- `-ForceDownload` switch
- Auto-enable when TS var `SMSTSForceDellBIOSFlash` or `SMSTSForceBIOSDownload` is `True`

This stages the BIOS package even when the installed version is already current, so the subsequent `Invoke-DellBIOSUpdate.ps1 -Force` (or the same TS var) can recreate the NVMe recovery image.
