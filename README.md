# ModernBIOSManagement (fork with Dell force-flash support)

For the original implementation instructions, see: https://www.msendpointmgr.com/modern-bios-management

## Dell NVMe recovery image recreation (this fork)

Newer Dell Pro / Dell S / Precision models store the BIOS recovery image on NVMe. After a clean OSD the image is wiped. Re-running the BIOS flash (even on the same version) recreates it (Dell KB 000467636 / r/SCCM discussion).

### What this fork provides

| Script | Version | Status |
|--------|---------|--------|
| `Invoke-DellBIOSUpdate.ps1` | **v1.2.0** | Ready. Optional `-Force` (adds `/f`). Also auto-enabled by the `SMSTSForceDellBIOSFlash=True` task sequence variable. |
| `Invoke-CMDownloadBIOSPackage.ps1` | **v3.0.6** | Ready. Built-in `-ForceDownload` support, with the `SMSTSForceBIOSDownload` and legacy `SMSTSForceDellBIOSFlash` aliases. |

### Task Sequence usage (recommended)

```
Set Task Sequence Variable
  Name:  SMSTSForceDellBIOSFlash
  Value: True

# then the normal steps
Invoke-CMDownloadBIOSPackage.ps1 ...
Invoke-DellBIOSUpdate.ps1
```

A single task-sequence variable enables both the forced download and forced flash. The more general `SMSTSForceBIOSDownload` is also accepted.

### Notes

- Only the `main` branch is used. Any other branches can be safely deleted.
- The fork remains aligned with the original project while preserving the Dell recovery-image support.
