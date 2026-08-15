# ModernBIOSManagement (fork with Dell force-flash support)

For original implementation instructions see: https://www.msendpointmgr.com/modern-bios-management

## Dell NVMe recovery image recreation (this fork)

Newer Dell Pro / Dell S / Precision models store the BIOS recovery image on NVMe.  
After a clean OSD the image is wiped. Re-running the BIOS flash (even on the same version) recreates it  
(Dell KB 000467636 / r/SCCM discussion).

### What this fork provides

| Script | Version | Status |
|--------|---------|--------|
| `Invoke-DellBIOSUpdate.ps1` | **v1.2.0** | Ready. Optional `-Force` (adds `/f`). Also auto-enabled by TS variable `SMSTSForceDellBIOSFlash=True` |
| `Invoke-CMDownloadBIOSPackage.ps1` | base v3.0.4 + `ForceDownload.patch` | Apply the included patch to get **v3.0.5** with `-ForceDownload` support |

### Task Sequence usage (recommended)

```
Set Task Sequence Variable
  Name:  SMSTSForceDellBIOSFlash
  Value: True

# then the normal steps
Invoke-CMDownloadBIOSPackage.ps1 ...
Invoke-DellBIOSUpdate.ps1
```

The single TS variable enables both the forced download (after patch) and the forced flash.

### Applying the ForceDownload patch (one-time)

```powershell
# From the repo root
# Linux / Git Bash:
patch -p0 < ForceDownload.patch

# Windows (with Git):
git apply ForceDownload.patch
```

After applying, `Invoke-CMDownloadBIOSPackage.ps1` becomes v3.0.5 and will stage the BIOS package even when the installed version is already current. This is required so the subsequent forced flash can recreate the NVMe recovery image.

### Notes

- Only the `main` branch is used. Any other branches can be safely deleted.
- No other scripts were modified.
