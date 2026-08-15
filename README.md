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
| `Invoke-CMDownloadBIOSPackage.ps1` | v3.0.5 – optional `-ForceDownload` so the package is staged even when version is current |

### Task Sequence usage

```
Set Task Sequence Variable
  Name:  SMSTSForceDellBIOSFlash
  Value: True

# then normal steps
Invoke-CMDownloadBIOSPackage.ps1 ...
Invoke-DellBIOSUpdate.ps1          # -Force optional when TS var is set
```

### Getting the full download script (v3.0.5)

The full 78 KB file is produced by the self-expander (one-time):

```powershell
powershell -File .\_Expand-DownloadScript.ps1
```

This writes `Invoke-CMDownloadBIOSPackage.ps1` with `-ForceDownload` support.
Afterwards you can delete `_Expand-DownloadScript.ps1`.

Alternatively apply `ForceDownload.patch` to the upstream script.
