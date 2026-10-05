<#
.SYNOPSIS
    Invoke Dell BIOS Update process.

.DESCRIPTION
    This script will invoke the Dell BIOS update process for the executable residing in the path specified for the Path parameter.

.PARAMETER Path
    Specify the path containing the Flash64W.exe and BIOS executable.

.PARAMETER Password
    Specify the BIOS password if necessary.

.PARAMETER NoVideo
    Add Dell's /novideo switch for supported headless systems that cannot flash the BIOS without a connected display. Disabled by default.

.PARAMETER LogFileName
    Set the name of the log file produced by the flash utility.

.EXAMPLE
    .\Invoke-DellBIOSUpdate.ps1 -Password "BIOSPassword" -LogFileName "LogFileName.log"

.NOTES
    FileName:    Invoke-DellBIOSUpdate.ps1
    Authors:     Maurice Daly & Nickolaj Andersen
    Contact:     @modaly_it
    Created:     2017-05-30
    Updated:     2019-05-14
    
    Version history:
    1.0.0 - (2017-05-30) Script created (Maurice Daly)
	1.0.1 - (2017-06-01) Additional checks for both in OSD and normal OS environments (Maurice Daly)
	1.0.2 - (2017-06-07) Fixed bug in legacy update method (Maurice Daly)
	1.0.3 - (2017-06-26) Added checks for Flash64W.exe utility and BIOS file presence including some additional logging (Nickolaj Andersen)
	1.0.4 - (2017-06-30) Fixed an issue where the password was not passed to Flash64W.exe utility. Added logging for this script to a separate file (Nickolaj Andersen)
	1.0.5 - (2017-07-04) Configured Flash64W.exe as the native update tool for 64-bit Full OS deployments
	1.0.6 - (2018-12-04) Variable name correction in example. No functional changes
	1.0.7 - (2019-02-05) Removed requirement for OSDBIOSPackage01 variable. Script will now default to this value.
						 Added registry stamping function
	1.0.8 - (2019-03-02) Updated path and task sequence handling
	1.0.9 - (2019-05-01) Removed the /f switch that bypasses the model check and could possibly incorrectly flash the system with a wrong BIOS package if Dell somehow messes up with the downloaded bits
	1.1.0 - (2019-05-14) Handle log output correctly if $Password is not specified
	1.1.1 - (2026-09-13) Added opt-in /novideo support for compatible headless systems
#>
[CmdletBinding()]
param(
    [parameter(Mandatory=$false, HelpMessage="Specify the path containing the Flash64W.exe and BIOS executable.")]
    [ValidateNotNullOrEmpty()]
    [string]$Path,

    [parameter(Mandatory=$false, HelpMessage="Specify the BIOS password if necessary.")]
    [ValidateNotNullOrEmpty()]
    [string]$Password,

    [parameter(Mandatory=$false, HelpMessage="Add Dell's /novideo switch for supported headless systems.")]
    [switch]$NoVideo,

    [parameter(Mandatory=$false, HelpMessage="Set the name of the log file produced by the flash utility.")]
    [ValidateNotNullOrEmpty()]
    [string]$LogFileName = "DellFlashBIOSUpdate.log"
)
Begin {
	# Load Microsoft.SMS.TSEnvironment COM object
	try {
		$TSEnvironment = New-Object -ComObject Microsoft.SMS.TSEnvironment -ErrorAction Stop
	}
	catch [System.Exception] {
		Write-Warning -Message "Unable to construct Microsoft.SMS.TSEnvironment object"
	}
}
Process {
    # Functions
    function Write-CMLogEntry {
	    param(
		    [parameter(Mandatory=$true, HelpMessage="Value added to the log file.")]
		    [ValidateNotNullOrEmpty()]
		    [string]$Value,

		    [parameter(Mandatory=$true, HelpMessage="Severity for the log entry. 1 for Informational, 2 for Warning and 3 for Error.")]
		    [ValidateNotNullOrEmpty()]
            [ValidateSet("1", "2", "3")]
		    [string]$Severity,

		    [parameter(Mandatory=$false, HelpMessage="Name of the log file that the entry will written to.")]
		    [ValidateNotNullOrEmpty()]
		    [string]$FileName = "Invoke-DellBIOSUpdate.log"
	    )
	    # Determine log file location
        $LogFilePath = Join-Path -Path $TSEnvironment.Value("_SMSTSLogPath") -ChildPath $FileName

        # Construct time stamp for log entry
        $Time = -join @((Get-Date -Format "HH:mm:ss.fff"), "+", (Get-CimInstance -ClassName Win32_TimeZone | Select-Object -ExpandProperty Bias))

        # Construct date for log entry
        $Date = (Get-Date -Format "MM-dd-yyyy")

        # Construct context for log entry
        $Context = $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)

        # Construct final log entry
        $LogText = "<![LOG[$($Value)]LOG]!><time=""$($Time)"" date=""$($Date)"" component=""DellBIOSUpdate.log"" context=""$($Context)"" type=""$($Severity)"" thread=""$($PID)"" file="""">"
	
	    # Add value to log file
        try {
	        Out-File -InputObject $LogText -Append -NoClobber -Encoding Default -FilePath $LogFilePath -ErrorAction Stop 
        }
        catch [System.Exception] {
            Write-Warning -Message "Unable to append log entry to Invoke-DellBIOSUpdate.log file. Error message: $($_.Exception.Message)"
        }
    }
	
	# A virtual machine has no physical firmware flash chip. The guest BIOS/UEFI is a software template
	# owned by the hypervisor, so Dell Update Packages refuse to execute and return exit code 5
	# (QUAL_HARD_ERROR), which would fail the task sequence. Skip gracefully instead.
	$ComputerSystem = Get-CimInstance -ClassName "Win32_ComputerSystem" -ErrorAction SilentlyContinue
	if ($ComputerSystem -ne $null) {
		$VirtualMachineModels = @("Virtual Machine", "VMware Virtual Platform", "VMware7,1", "VMware20,1", "VirtualBox", "HVM domU", "KVM", "QEMU Virtual Machine", "Standard PC (Q35 + ICH9, 2009)", "Standard PC (i440FX + PIIX, 1996)", "Parallels Virtual Platform", "Google Compute Engine", "AHV")
		if (($ComputerSystem.Model -in $VirtualMachineModels) -or ($ComputerSystem.Manufacturer -match "VMware|QEMU|innotek|Xen|Parallels|Nutanix|Red Hat")) {
			Write-CMLogEntry -Value "Virtual machine detected ('$($ComputerSystem.Manufacturer) $($ComputerSystem.Model)'). BIOS/UEFI firmware is managed by the hypervisor, skipping BIOS flash" -Severity 2
			exit 0
		}
	}
	
	# Default to task sequence variable set in detection script
	if (-not([string]::IsNullOrEmpty($TSEnvironment.Value("OSDBIOSPackage01")))){
		Write-CMLogEntry -Value "Using BIOS package location set in OSDBIOSPackage01 TS variable" -Severity 1
		$Path = $TSEnvironment.Value("OSDBIOSPackage01")
	}
	
	# Run BIOS update process if BIOS package exists
	if (-not([string]::IsNullOrEmpty($Path))){

		# Write log file for script execution
		Write-CMLogEntry -Value "Initiating script to determine flashing capabilities for Dell BIOS updates" -Severity 1

		# Flash BIOS upgrade utility file name
		$FlashUtility = Get-ChildItem -Path $Path -Filter "*.exe" -Recurse | Where-Object { $_.Name -like "Flash64W.exe" } | Select-Object -First 1 -ExpandProperty FullName
		Write-CMLogEntry -Value "Attempting to use flash utility: $($FlashUtility)" -Severity 1

		if ($FlashUtility -ne $null) {
			# Detect BIOS update executable
			$CurrentBIOSFileItems = @(Get-ChildItem -Path $Path -Filter "*.exe" -Recurse | Where-Object { $_.Name -notlike ($FlashUtility | Split-Path -leaf) } | Select-Object -ExpandProperty FullName)
			if ($CurrentBIOSFileItems.Count -gt 1) {
				Write-CMLogEntry -Value "Multiple BIOS update executables were found in the package, unable to determine which one to use. Files found: $($CurrentBIOSFileItems -join ", ")" -Severity 3; exit 1
			}
			$CurrentBIOSFile = $CurrentBIOSFileItems | Select-Object -First 1
			Write-CMLogEntry -Value "Attempting to use BIOS update file: $($CurrentBIOSFile)" -Severity 1	

			if ($CurrentBIOSFile -ne $null) {
				# Set log file location
				$BIOSLogFile = Join-Path -Path $TSEnvironment.Value("_SMSTSLogPath") -ChildPath $LogFileName

				# Set required switches for silent upgrade of the bios and logging
				$FlashSwitches = "/b=""$($CurrentBIOSFile)"" /s /l=""$($BIOSLogFile)"""

				# Add password to the Flash64W.exe switches
				if ($PSBoundParameters["Password"]) {
					if (-not([System.String]::IsNullOrEmpty($Password))) {
						$FlashSwitches = $FlashSwitches + " /p=$($Password)"
					}
				}	

				if ($NoVideo.IsPresent) {
					$FlashSwitches = $FlashSwitches + " /novideo"
				}

				if (($TSEnvironment -ne $null) -and ($TSEnvironment.Value("_SMSTSinWinPE") -eq $true)) {
					Write-CMLogEntry -Value "Current environment is determined as WinPE" -Severity 1

					try {
						# Start flash update process
						if (-not([System.String]::IsNullOrEmpty($Password))) {
							Write-CMLogEntry -Value "Using the following switches for Flash64W.exe: $($FlashSwitches -replace $Password, "<password removed>")" -Severity 1
						}
						else {
							Write-CMLogEntry -Value "Using the following switches for Flash64W.exe: $($FlashSwitches)" -Severity 1
						}
						$FlashProcess = Start-Process -FilePath $FlashUtility -ArgumentList $FlashSwitches -Passthru -Wait -ErrorAction Stop
						
						Write-CMLogEntry -Value "Flash utility exit code: $($FlashProcess.ExitCode)" -Severity 1

						# Evaluate the Dell Update Package (DUP) exit code, see the DUP exit code table for the full list
						# Exit codes must be compared as integers, a regex match such as "0|2" would also accept 10, 12, 20 and 120
						switch ($FlashProcess.ExitCode) {
							0 {
								# SUCCESSFUL - update applied, no restart required
								Write-CMLogEntry -Value "BIOS update completed successfully, no restart is required" -Severity 1
								$TSEnvironment.Value("SMSTSBIOSInOSUpdateRequired") = "False"
							}
							{ $_ -in @(2, 14) } {
								# REBOOT_REQUIRED - the update is staged and a restart applies it
								Write-CMLogEntry -Value "BIOS update staged successfully, a restart is required to apply the new BIOS" -Severity 1
								$TSEnvironment.Value("SMSTSBIOSUpdateRebootRequired") = "True"
								$TSEnvironment.Value("SMSTSBIOSInOSUpdateRequired") = "False"
							}
							3 {
								# DEP_SOFT_ERROR - typically the same version is already installed or a downgrade was attempted, non-blocking
								Write-CMLogEntry -Value "Flash utility reported a soft dependency error (exit code 3), the system is likely already running this BIOS version. No update was applied." -Severity 2
								$TSEnvironment.Value("SMSTSBIOSInOSUpdateRequired") = "False"
							}
							6 {
								# REBOOTING_SYSTEM - the flash utility is restarting the device itself, do not trigger a second restart
								Write-CMLogEntry -Value "Flash utility has taken control of the power state and is restarting the system (exit code 6)" -Severity 1
								$TSEnvironment.Value("SMSTSBIOSInOSUpdateRequired") = "False"
							}
							13 {
								# UPDATE_SUCCESSFUL with unmet soft dependencies
								Write-CMLogEntry -Value "BIOS update completed successfully, however one or more soft dependencies were not met (exit code 13)" -Severity 2
								$TSEnvironment.Value("SMSTSBIOSInOSUpdateRequired") = "False"
							}
							{ $_ -in @(15, 16) } {
								# CONTAINER_POWER_CYCLE_REQUIRED - a full power cycle is required, a warm restart will not apply the firmware
								Write-CMLogEntry -Value "BIOS update staged successfully, however a full power cycle (cold boot) is required to apply the firmware. A warm restart will not complete the update." -Severity 2
								$TSEnvironment.Value("SMSTSBIOSUpdateColdBootRequired") = "True"
								$TSEnvironment.Value("SMSTSBIOSUpdateRebootRequired") = "True"
								$TSEnvironment.Value("SMSTSBIOSInOSUpdateRequired") = "False"
							}
							4 {
								Write-CMLogEntry -Value "A hard dependency was not met by the flash utility (exit code 4), the required prerequisite BIOS version or hardware is missing. Please review the log file located at $($BIOSLogFile)" -Severity 3; exit 4
							}
							5 {
								Write-CMLogEntry -Value "The flash utility refused to run on this system (exit code 5, qualification error). This cannot be bypassed with the force switch. Please review the log file located at $($BIOSLogFile)" -Severity 3; exit 5
							}
							10 {
								# Code 10 is package-specific and is not assigned by Dell's generic DUP exit-code table; client BIOS packages commonly use it for a power prerequisite.
								Write-CMLogEntry -Value "The BIOS utility returned package-specific exit code 10. Verify AC power and battery requirements, then review the log file located at $($BIOSLogFile)" -Severity 3; exit 10
							}
							default {
								Write-CMLogEntry -Value "An error occured while updating the system BIOS during OS offline phase, exit code was $($FlashProcess.ExitCode). Please review the log file located at $($BIOSLogFile)" -Severity 3; exit $FlashProcess.ExitCode
							}
						}
						
					}
					catch [System.Exception] {
						Write-CMLogEntry -Value "An error occured while updating the system BIOS during OS offline phase. Error message: $($_.Exception.Message)" -Severity 3 ; exit 1
					}
				}
				else {
					# Used as a fall back for systems that do not support the Flash64w update tool
					# Used in a later section of the task sequence (after Setup Windows and ConfigMgr step)

					Write-CMLogEntry -Value "Current environment is determined as FullOS" -Severity 1
					
					# Detect BitLocker status through CIM instead of parsing localized Manage-Bde output
					$OSVolumeEncypted = $false
					try {
						$OSVolume = Get-CimInstance -Namespace "root\cimv2\Security\MicrosoftVolumeEncryption" -ClassName "Win32_EncryptableVolume" -ErrorAction Stop | Where-Object { $_.DriveLetter -eq $env:SystemDrive }
						if (($OSVolume -ne $null) -and ($OSVolume.ProtectionStatus -eq 1)) {
							$OSVolumeEncypted = $true
						}
					}
					catch [System.Exception] {
						Write-CMLogEntry -Value "Unable to determine BitLocker status for volume $($env:SystemDrive). Error message: $($_.Exception.Message)" -Severity 3; exit 1
					}
					
					# Supend Bitlocker if $OSVolumeEncypted is $true, remember to re-enable BitLocker after the flashing has occurred
					if ($OSVolumeEncypted -eq $true) {
						Write-CMLogEntry -Value "Suspending BitLocker protected volume: $($env:SystemDrive)" -Severity 1
						Manage-Bde -Protectors -Disable $env:SystemDrive | Out-Null

						# Confirm that protection was actually suspended before flashing, a locked volume during flash can render the device unbootable
						$OSVolume = Get-CimInstance -Namespace "root\cimv2\Security\MicrosoftVolumeEncryption" -ClassName "Win32_EncryptableVolume" | Where-Object { $_.DriveLetter -eq $env:SystemDrive }
						if (($OSVolume -eq $null) -or ($OSVolume.ProtectionStatus -ne 0)) {
							Write-CMLogEntry -Value "Failed to suspend BitLocker protection on volume $($env:SystemDrive), aborting BIOS update to avoid leaving the device in an unbootable state." -Severity 3; exit 1
						}
					}
					
					# Start BIOS update process
					try {
						if (([Environment]::Is64BitOperatingSystem) -eq $true) {
							Write-CMLogEntry -Value "Starting 64-bit flash BIOS update process" -Severity 1
							if (-not([System.String]::IsNullOrEmpty($Password))) {
								Write-CMLogEntry -Value "Using the following switches for Flash64W.exe: $($FlashSwitches -replace $Password, "<password removed>")" -Severity 1
							}
							else {
								Write-CMLogEntry -Value "Using the following switches for Flash64W.exe: $($FlashSwitches)" -Severity 1
							}

							# Update BIOS using Flash64W.exe
							$FlashUpdate = Start-Process -FilePath $FlashUtility -ArgumentList $FlashSwitches -Passthru -Wait -ErrorAction Stop
							$FlashExitCode = $FlashUpdate.ExitCode
						}
						else {
							# Set required switches for silent upgrade of the BIOS
							$FileSwitches = " /l=""$($BIOSLogFile)"" /s"

							# Add password to switches
							if ($PSBoundParameters["Password"]) {
								if (-not([System.String]::IsNullOrEmpty($Password))) {
									$FileSwitches = $FileSwitches + " /p=$($Password)"
								}
							}

							if ($NoVideo.IsPresent) {
								$FileSwitches = $FileSwitches + " /novideo"
							}

							Write-CMLogEntry -Value "Starting 32-bit flash BIOS update process" -Severity 1
							if (-not([System.String]::IsNullOrEmpty($Password))) {
								Write-CMLogEntry -Value "Using the following switches for BIOS file: $($FileSwitches -replace $Password, "<password removed>")" -Severity 1
							}
							else {
								Write-CMLogEntry -Value "Using the following switches for BIOS file: $($FileSwitches)" -Severity 1
							}

							# Update BIOS using update file
							$FileUpdate = Start-Process -FilePath $CurrentBIOSFile -ArgumentList $FileSwitches -PassThru -Wait -ErrorAction Stop
							$FlashExitCode = $FileUpdate.ExitCode
						}
						
					}
					catch [System.Exception] {
						Write-CMLogEntry -Value "An error occured while updating the system BIOS in OS online phase. Error message: $($_.Exception.Message)" -Severity 3; exit 1
					}

					# Evaluate the exit code returned by the flash utility, previously the result was discarded and every run was reported as a success
					Write-CMLogEntry -Value "Flash utility exit code: $($FlashExitCode)" -Severity 1
					switch ($FlashExitCode) {
						0 {
							# SUCCESSFUL - update applied, no restart required
							Write-CMLogEntry -Value "BIOS update completed successfully, no restart is required" -Severity 1
						}
						{ $_ -in @(2, 14) } {
							# REBOOT_REQUIRED - the update is staged and a restart applies it
							Write-CMLogEntry -Value "BIOS update completed successfully, a restart is required to apply the new BIOS" -Severity 1
							if ($TSEnvironment -ne $null) {
								$TSEnvironment.Value("SMSTSBIOSUpdateRebootRequired") = "True"
							}
						}
						3 {
							# DEP_SOFT_ERROR - typically the same version is already installed or a downgrade was attempted, non-blocking
							Write-CMLogEntry -Value "Flash utility reported a soft dependency error (exit code 3), the system is likely already running this BIOS version. No update was applied." -Severity 2
						}
						6 {
							# REBOOTING_SYSTEM - the flash utility is restarting the device itself, do not trigger a second restart
							Write-CMLogEntry -Value "Flash utility has taken control of the power state and is restarting the system (exit code 6)" -Severity 1
						}
						13 {
							# UPDATE_SUCCESSFUL with unmet soft dependencies
							Write-CMLogEntry -Value "BIOS update completed successfully, however one or more soft dependencies were not met (exit code 13)" -Severity 2
						}
						{ $_ -in @(15, 16) } {
							# CONTAINER_POWER_CYCLE_REQUIRED - a full power cycle is required, a warm restart will not apply the firmware
							Write-CMLogEntry -Value "BIOS update completed successfully, however a full power cycle (cold boot) is required to apply the firmware. A warm restart will not complete the update." -Severity 2
							if ($TSEnvironment -ne $null) {
								$TSEnvironment.Value("SMSTSBIOSUpdateColdBootRequired") = "True"
								$TSEnvironment.Value("SMSTSBIOSUpdateRebootRequired") = "True"
							}
						}
						4 {
							Write-CMLogEntry -Value "A hard dependency was not met by the flash utility (exit code 4), the required prerequisite BIOS version or hardware is missing. Please review the log file located at $($BIOSLogFile)" -Severity 3; exit 4
						}
						5 {
							Write-CMLogEntry -Value "The flash utility refused to run on this system (exit code 5, qualification error). This cannot be bypassed with the force switch. Please review the log file located at $($BIOSLogFile)" -Severity 3; exit 5
						}
						10 {
							# Code 10 is package-specific and is not assigned by Dell's generic DUP exit-code table; client BIOS packages commonly use it for a power prerequisite.
							Write-CMLogEntry -Value "The BIOS utility returned package-specific exit code 10. Verify AC power and battery requirements, then review the log file located at $($BIOSLogFile)" -Severity 3; exit 10
						}
						default {
							Write-CMLogEntry -Value "BIOS update failed with exit code $($FlashExitCode). Please review the log file located at $($BIOSLogFile)" -Severity 3; exit $FlashExitCode
						}
					}
				}
			}
			else {
				Write-CMLogEntry -Value "Unable to locate the current BIOS update file" -Severity 2 ; exit 1
			}
		}
		else {
			Write-CMLogEntry -Value "Unable to locate the Flash64W.exe utility" -Severity 2 ; exit 1
		}
	}
	else {
		Write-CMLogEntry -Value "Unable to determine BIOS package path." -Severity 2 ; exit 1
	}
}