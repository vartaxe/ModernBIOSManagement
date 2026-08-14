<#
.SYNOPSIS
	Download BIOS package (regular package) matching computer model and manufacturer.
	
.DESCRIPTION
    This script will determine the model of the computer and manufacturer and then query the specified endpoint
    for ConfigMgr WebService for a list of Packages. It then sets the OSDDownloadDownloadPackages variable to include
    the PackageID property of a package matching the computer model. If multiple packages are detect, it will select
	most current one by the creation date of the packages.

.PARAMETER BareMetal
	Set the script to operate in 'BareMetal' (WinPE) deployment type mode.

.PARAMETER BIOSUpdate
	Set the script to operate in 'BIOSUpdate' (full OS) deployment type mode.

.PARAMETER DebugMode
	Set the script to operate in 'DebugMode' deployment type mode.

.PARAMETER Endpoint
	Specify the internal fully qualified domain name of the server hosting the AdminService, e.g. CM01.domain.local.

.PARAMETER UserName
	Specify the service account user name used for authenticating against the AdminService endpoint.

.PARAMETER Password
	Specify the service account password used for authenticating against the AdminService endpoint.
	
.PARAMETER Filter
	Define a filter used when calling ConfigMgr WebService to only return objects matching the filter.

.PARAMETER OperationalMode
	Define the operational mode, either Production or Pilot, for when calling ConfigMgr WebService to only return objects matching the selected operational mode.

.PARAMETER Manufacturer
	Override the automatically detected computer manufacturer when running in debug mode.

.PARAMETER ComputerModel
	Override the automatically detected computer model when running in debug mode.

.PARAMETER SystemSKU
	Override the automatically detected SystemSKU when running in debug mode.

.PARAMETER ForceDownload
	Force download of the matched BIOS package even when the installed version is already current.
	Needed to stage content for Dell recovery-image recreation after OSD (Dell KB 000467636).
	Also enabled when TS variable SMSTSForceDellBIOSFlash or SMSTSForceBIOSDownload is True.

.PARAMETER OSVersionFallback
	Use this switch to check for drivers packages that matches earlier versions of Windows than what's specified as input for TargetOSVersion.

.EXAMPLE
	# Detect and download latest available BIOS package with ConfigMgr through the admin service in a baremetal deployment (default):
	.\Invoke-CMDownloadBIOSPackage.ps1 -BareMetal -Endpoint "CM01.domain.com" 

	# Force download even if BIOS is already current (for Dell recovery image recreation):
	.\Invoke-CMDownloadBIOSPackage.ps1 -BareMetal -Endpoint "CM01.domain.com" -ForceDownload

	# Detect and download latest available BIOS package with ConfigMgr through the admin service in a full OS deployment:
	.\Invoke-CMDownloadBIOSPackage.ps1 -BIOSUpdate -Endpoint "CM01.domain.com"

	# Detect, and report on the matched BIOS release without downloading / in full OS
	.\Invoke-CMDownloadBIOSPackage.ps1 -Endpoint "CM01.domain.com" -UserName "Username" -Password "Password" -DebugMode
	
	# Detect, and report on the matched BIOS release without downloading / in full OS, with the make / model / sku specified
	.\Invoke-CMDownloadBIOSPackage.ps1 -Endpoint "CM01.domain.com" -UserName "Username" -Password "Password" -Manufacturer "HP" -ComptuerModel "ZBook Studio x360 G5" -SystemSKU "8427" -DebugMode

.NOTES
    FileName:    Invoke-CMDownloadBIOSPackage.ps1
	Author:      Nickolaj Andersen / Maurice Daly
    Contact:     @NickolajA / @MoDaly_IT
    Created:     2020-10-30
    Updated:     2026-08-15
    
    Version history:
    3.0.0 - (2020-10-30) - Script created
	3.0.1 - (2020-12-04) - Fixes to parameter sets, matching logic and removal of no longer code
						 - Added TS variable support for Resource URL
	3.0.2 - (2020-12-09) - Added new functionality to be able to read a custom Application ID URI, if the default of https://ConfigMgrService is not defined on the ServerApp.
	3.0.3 - (2020-12-10) - Fixed issue in WinPE, with addition of baremetal parameter switch (now default)
						   Added BIOSUpdate parameter switch for Full OS deployments
	3.0.4 - (2026-08-05) - Multiple-package selection hardening and fixes:
						 - Fixed Lenovo model-name fallback that re-sorted an already-nulled package list, causing valid model-type matches to be discarded and the run to bail out (exit 1).
						 - Unified the "latest package" sort key to SourceDate for HP and Microsoft (previously PackageCreated, which is not a property on the AdminService SMS_Package object, so the list was left unsorted and an older package could be selected).
						 - Tightened SystemSKU matching to compare whole alphanumeric tokens instead of using -match (regex substring), preventing spurious multi-package matches where a short SKU matched inside another SKU or elsewhere in the description.
						 - Normalised the reduced package list to an array so .Count and index access behave predictably after Select-Object -First 1.
						 - Corrected $null comparisons to place $null on the left-hand side.
						 - Added a documented placeholder (default) branch in Get-ComputerData describing how to add support for custom/unlisted manufacturers.
						 - Logging improvements for troubleshooting: Invoke-Executable launch failures are now written to the log file (Severity 3) instead of only Write-Warning, and return -1 rather than silently continuing; Get-ComputerData wraps manufacturer detection in try/catch that logs the manufacturer context on failure and degrades gracefully; and a script version + key parameter banner is written at startup.
	3.0.5 - (2026-08-15) - Added optional -ForceDownload switch (and TS variable SMSTSForceDellBIOSFlash / SMSTSForceBIOSDownload).
						   When set, the matched BIOS package is downloaded even if the installed version is already current.
						   Required so Invoke-DellBIOSUpdate.ps1 -Force can recreate the NVMe BIOS recovery image on newer Dell Pro/S/Precision models after OSD (Dell KB 000467636).

#>
[CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = "BareMetal")]
param (
	[parameter(Mandatory = $true, ParameterSetName = "BareMetal", HelpMessage = "Set the script to operate in 'BareMetal' deployment type mode.")]
	[switch]$BareMetal,
	
	[parameter(Mandatory = $true, ParameterSetName = "BIOSUpdate", HelpMessage = "Set the script to operate in 'BIOSUpdate' deployment type mode.")]
	[switch]$BIOSUpdate,
	
	[parameter(Mandatory = $true, ParameterSetName = "BIOSUpdate", HelpMessage = "Specify the internal fully qualified domain name of the server hosting the AdminService, e.g. CM01.domain.local.")]
	[parameter(Mandatory = $true, ParameterSetName = "BareMetal")]
	[parameter(Mandatory = $true, ParameterSetName = "Debug")]
	[ValidateNotNullOrEmpty()]
	[string]$Endpoint,
	
	[parameter(Mandatory = $false, ParameterSetName = "Debug", HelpMessage = "Set the script to operate in 'DebugMode' deployment type mode.")]
	[switch]$DebugMode,
	
	[parameter(Mandatory = $true, ParameterSetName = "Debug", HelpMessage = "Specify the service account user name used for authenticating against the AdminService endpoint.")]
	[ValidateNotNullOrEmpty()]
	[string]$UserName = "",
	
	[parameter(Mandatory = $true, ParameterSetName = "Debug", HelpMessage = "Specify the service account password used for authenticating against the AdminService endpoint.")]
	[ValidateNotNullOrEmpty()]
	[string]$Password = "",
	
	[parameter(Mandatory = $false, ParameterSetName = "BIOSUpdate", HelpMessage = "Define a filter used when calling the AdminService to only return objects matching the filter.")]
	[parameter(Mandatory = $false, ParameterSetName = "BareMetal")]
	[ValidateNotNullOrEmpty()]
	[string]$Filter = "BIOS",
	
	[parameter(Mandatory = $false, ParameterSetName = "BIOSUpdate", HelpMessage = "Define the operational mode, either Production or Pilot, for when calling ConfigMgr WebService to only return objects matching the selected operational mode.")]
	[parameter(Mandatory = $false, ParameterSetName = "BareMetal")]
	[parameter(Mandatory = $true, ParameterSetName = "Debug")]
	[ValidateNotNullOrEmpty()]
	[ValidateSet("Production", "Pilot")]
	[string]$OperationalMode = "Production",
	
	[parameter(Mandatory = $false, ParameterSetName = "Debug", HelpMessage = "Override the automatically detected computer manufacturer when running in debug mode.")]
	[ValidateNotNullOrEmpty()]
	[ValidateSet("Hewlett-Packard", "HP", "Dell", "Lenovo", "Microsoft", "Fujitsu", "Panasonic", "Viglen", "AZW")]
	[string]$Manufacturer,
	
	[parameter(Mandatory = $false, ParameterSetName = "Debug", HelpMessage = "Override the automatically detected computer model when running in debug mode.")]
	[ValidateNotNullOrEmpty()]
	[string]$ComputerModel,
	
	[parameter(Mandatory = $false, ParameterSetName = "Debug", HelpMessage = "Override the automatically detected SystemSKU when running in debug mode.")]
	[ValidateNotNullOrEmpty()]
	[string]$SystemSKU,

	[parameter(Mandatory = $false, ParameterSetName = "BareMetal", HelpMessage = "Force download of the matched BIOS package even when the installed version is already current. Needed to stage content for Dell recovery-image recreation after OSD.")]
	[parameter(Mandatory = $false, ParameterSetName = "BIOSUpdate", HelpMessage = "Force download of the matched BIOS package even when the installed version is already current. Needed to stage content for Dell recovery-image recreation after OSD.")]
	[switch]$ForceDownload
)
