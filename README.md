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

Microsoft's 2011 Secure Boot certificates expire on three dates: Microsoft Corporation KEK CA 2011 on June 24, Microsoft Corporation UEFI CA 2011 on June 27, and Microsoft Windows Production PCA 2011 on October 19, 2026. Their replacements span the KEK and DB: `Microsoft Corporation KEK 2K CA 2023`, `Windows UEFI CA 2023`, `Microsoft UEFI CA 2023`, and `Microsoft Option ROM UEFI CA 2023`.

An untransitioned system continues to boot and receive standard Windows updates after expiry, but it cannot receive future boot-chain protections that depend on the 2023 trust anchors. Do not use Event IDs 1796 or 1803 as general expiry indicators: 1796 is an unexpected Secure Boot update error and 1803 identifies a missing OEM-signed KEK. Microsoft documents `UEFICA2023Status=Updated` and Event ID 1808 as completion signals; Event 1801 indicates incomplete servicing and Event 1795 a firmware error.

`Test-SecureBootCertificateStatus` is read-only and reports two task-sequence variables:

- `SecureBootCertificate2023Present` is `True` only when `Windows UEFI CA 2023` is observed in the UEFI DB.
- `SecureBootCertificate2023Status` distinguishes `Updated`, `Present`, `NotPresent`, `Disabled`, `Unavailable`, and `Error`. `Updated` requires the Windows servicing value `UEFICA2023Status=Updated`, which confirms the complete certificate and 2023-signed Boot Manager transition; DB presence alone reports `Present`.

The check never blocks, delays, or alters a BIOS flash. It runs before the virtual-machine gate because VMs also store certificates in virtual NVRAM. Missing Secure Boot cmdlets, legacy BIOS, disabled Secure Boot, and WinPE limitations are reported without terminating the script under `$ErrorActionPreference = "Stop"`.

Remediation is coordinated by Windows servicing with the physical or virtual firmware; it is not universally host-only:

| Platform | Current remediation model |
| --- | --- |
| Physical hardware | Apply supported Windows servicing; install an OEM firmware update first when the firmware cannot process authenticated DB/KEK updates. |
| VMware vSphere | ESXi 8.0 U3j adds automated PK remediation for vTPM-disabled VMs. vTPM-enabled VMs on ESXi 8.x still need Broadcom's manual procedure; the capsule path requires ESX 9.1.1.0+, VMware Tools 13.1.5+, a supported Windows guest, and the July 2026 Windows CU. Update KEK/DB through the guest OS after PK readiness. |
| Hyper-V | For long-lived Generation 2 VMs, apply the updates through Windows when the virtual firmware supports authenticated Secure Boot writes; monitor `UEFICA2023Status` and the documented events. Windows Server may require an administrator-initiated deployment rather than client Controlled Feature Rollout. |
| Azure Trusted Launch / Confidential VMs | Updates are initiated through Windows servicing inside the guest and rely on Azure platform support for virtual-firmware writes. VMs created after March 2024 typically already contain the 2023 firmware certificates but still require the updated Boot Manager. |
| Proxmox VE / QEMU | New EFI disks created with `pve-edk2-firmware` 4.2025.05-1 or later contain both certificate generations. For older EFI disks, shut down the VM and use **Disk Action > Enroll Updated Certificates** or `qm enroll-efi-keys`; suspend BitLocker protectors first. |

Authoritative references:

- [Microsoft: Windows Secure Boot certificate expiration and CA updates](https://support.microsoft.com/en-us/servicing/os/secure-boot/2025/06/windows-secure-boot-certificate-expiration-and-ca-updates)
- [Microsoft: Guidance for IT professionals and organizations](https://support.microsoft.com/en-us/servicing/os/secure-boot/2025/06/secure-boot-certificate-updates-guidance-for-it-professionals-and-organizations)
- [Microsoft: Registry monitoring and deployment keys](https://support.microsoft.com/en-us/servicing/os/secure-boot/2025/09/registry-key-updates-for-secure-boot-windows-devices-with-it-managed-updates)
- [Microsoft: Secure Boot DB, DBX, and KEK events](https://support.microsoft.com/en-us/servicing/os/windows/2022/06/secure-boot-db-and-dbx-variable-update-events)
- [Microsoft: Azure Trusted Launch and Confidential VM guidance](https://support.microsoft.com/en-us/servicing/os/secure-boot/docs/2026/03/secure-boot-update-from-2011-to-2023-certificates-trusted-launch-vms-tvm-and-confidential-vms-cvm)
- [Broadcom: vSphere Secure Boot certificate expiration FAQ](https://knowledge.broadcom.com/external/article/423893/secure-boot-certificate-expirations-and.html)
- [Proxmox: 2023 certificate enrollment documentation change](https://lists.proxmox.com/pipermail/pve-devel/2026-January/078081.html)
