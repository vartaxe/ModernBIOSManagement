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

## Virtual machine detection

A virtual machine has no physical flash chip. The guest BIOS/UEFI is a binary template owned by the hypervisor and is changed by updating the hypervisor host or raising the VM hardware compatibility version, never by running a vendor firmware payload inside the guest. Running a Dell Update Package in a guest returns exit code 5 (QUAL_HARD_ERROR), which `Invoke-DellBIOSUpdate.ps1` correctly treats as a hard failure and exits 5, failing the task sequence.

`Invoke-CMDownloadBIOSPackage.ps1` previously carried two separate inline virtual machine model lists that had already drifted apart, so a VMware guest could pass one gate and fail the other. Both call sites now use a single `Test-VirtualMachinePlatform` helper that matches the known Hyper-V, VMware, VirtualBox, Xen, KVM/QEMU, Parallels, Google Compute Engine and Nutanix AHV model strings, with a manufacturer regex fallback. `Microsoft` is deliberately absent from that regex because Surface devices report `Microsoft Corporation` exactly like Hyper-V guests; Hyper-V is matched on the `Virtual Machine` model string instead.

The four vendor flash scripts previously had no virtual machine detection at all, so invoking one directly outside the downloader attempted a flash and failed hard. Each now exits 0 with a severity 2 log entry before any BitLocker suspension or working directory change, so a guest is skipped cleanly rather than leaving BitLocker suspended behind a failed step.

`Invoke-CMDownloadBIOSPackage_Legacy.ps1` keeps its inline model-only list, widened to the same model strings, to preserve the frozen state of that script.

Hypervisor integration suites such as VMware Tools, Hyper-V Integration Services and VirtIO are driver and tooling packages, not firmware, and remain out of scope for this solution.

## Secure Boot certificate expiry (2026)

The original Microsoft Secure Boot certificates issued in 2011 expire in June and October 2026 and are replaced by `Windows UEFI CA 2023`. Systems whose signature database has not been updated log Event ID 1796 or 1803 and can stop accepting signed boot components and firmware updates. This is firmware state, not an operating system setting, so `Invoke-CMDownloadBIOSPackage.ps1` reports it.

`Test-SecureBootCertificateStatus` reads `Get-SecureBootUEFI -Name db` and looks for the `Windows UEFI CA 2023` string, then writes the boolean task-sequence variable `SecureBootCertificate2023Present`. The check is detection only: it never blocks, delays or alters a BIOS flash, and a negative result is logged at severity 2 rather than failing the step.

The check runs during the prerequisite phase, deliberately before the virtual machine gate, because a virtual machine carries the same certificates in its virtual NVRAM and would otherwise never be reported. It is wrapped so that a missing `SecureBoot` module, a legacy BIOS system or a WinPE image without the Secure Boot cmdlets logs a skip instead of terminating the script under `$ErrorActionPreference = "Stop"`.

Remediation is out of band and platform specific, and on a guest it cannot be performed from inside the operating system:

| Platform | Remediation |
| --- | --- |
| Physical hardware | OEM firmware update plus the Windows servicing updates that enroll the 2023 certificates |
| VMware vSphere | Upgrade hosts to ESXi 8.0 U3j or newer; VMs created before 8.0 U2 commonly have a null Platform Key, and guests with a vTPM need an additional manual transition |
| Hyper-V and Azure | Host cumulative updates; Windows Server Gen 2 guests usually need the enrollment triggered manually |
| Proxmox, KVM and QEMU | Shut the VM down, then use Enroll Updated Certificates on the EFI disk in the hypervisor |
