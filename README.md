# ModernBIOSManagement
For implementation instructions, please go to https://www.msendpointmgr.com/modern-bios-management

BIOS package matching uses the manufacturer, model/SystemSKU and BIOS version or release date, not the Windows release or build number. Windows feature updates do not require a version-mapping entry in these scripts. Microsoft Surface firmware delivered through driver packages is still handled as such.

The scripts use `Get-CimInstance` for local hardware, ConfigMgr client, time-zone and BitLocker queries. In WinPE, include the WinPE-WMI, WinPE-NetFX, WinPE-Scripting and WinPE-PowerShell optional components and their dependencies. CIM queries are local and do not require WinRM configuration.

Replacing WMI cmdlets does not make the entire solution PowerShell 7 compatible: the legacy downloader still uses `New-WebServiceProxy`, which requires Windows PowerShell. Continue using the supported ConfigMgr task-sequence PowerShell environment.

Run `.\Tests\CimMigration.Tests.ps1` for isolated regression checks; these mock hardware queries and do not download packages or flash firmware.
