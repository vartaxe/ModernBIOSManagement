# ModernBIOSManagement
For implementation instructions, please go to https://www.msendpointmgr.com/modern-bios-management

BIOS package matching uses the manufacturer, model/SystemSKU and BIOS version or release date, not the Windows release or build number. Windows feature updates do not require a version-mapping entry in these scripts. Microsoft Surface firmware delivered through driver packages is still handled as such.

The scripts use `Get-CimInstance` for local hardware, ConfigMgr client, time-zone and BitLocker queries. In WinPE, include the WinPE-WMI, WinPE-NetFX, WinPE-Scripting and WinPE-PowerShell optional components and their dependencies. CIM queries are local and do not require WinRM configuration.

Replacing WMI cmdlets does not make the entire solution PowerShell 7 compatible: the legacy downloader still uses `New-WebServiceProxy`, which requires Windows PowerShell. Continue using the supported ConfigMgr task-sequence PowerShell environment.

Run `.\Tests\CimMigration.Tests.ps1` for isolated regression checks; these mock hardware queries and do not download packages or flash firmware.

## Dell Update Package (DUP) exit code handling

`Invoke-DellBIOSUpdate.ps1` evaluates the full documented DUP exit code table in both the WinPE and full OS branches. Exit codes are compared as integers; the previous `-match "0|2"` regex comparison also accepted 10, 12, 20 and 120 as success.

| Code | Meaning | Script result |
| --- | --- | --- |
| 0 | Successful | Success |
| 2, 14 | Reboot required (14 with unmet soft dependencies) | Success, sets `SMSTSBIOSUpdateRebootRequired` |
| 3 | Soft dependency error, typically the same or a newer BIOS is already installed | Warning, not a failure |
| 6 | The package is restarting the system itself | Success, the script does not request a second reboot |
| 13 | Successful with unmet soft dependencies | Warning, treated as success |
| 15, 16 | Full power cycle (cold boot) required | Warning, sets `SMSTSBIOSUpdateColdBootRequired` and `SMSTSBIOSUpdateRebootRequired` |
| 4 | Hard dependency error | Failure, exits 4 |
| 5 | Qualification error, cannot be bypassed with the force switch | Failure, exits 5 |
| 10 | System is on battery power | Failure, exits 10 |
| any other | Unhandled failure, including the Linux-only code 9 | Failure, exits with the original Dell exit code |

Failure paths now exit with the original Dell exit code instead of a blanket `exit 1`, so ConfigMgr or Intune can distinguish failure classes.

`SMSTSBIOSUpdateColdBootRequired` is a new task-sequence variable. Codes 15 and 16 require a full power cycle rather than a warm restart, so the script records the requirement and lets the task sequence decide when to shut the machine down; a warm `Restart Computer` step does not apply those updates.

The other vendor scripts are unchanged in this respect: HP uses 0 and 3010, Lenovo WinUPTP uses 0 and the benign 1073807364, and no further authoritative code tables were applied.
