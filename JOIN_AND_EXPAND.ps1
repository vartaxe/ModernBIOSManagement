# Join the expander parts and expand the full download script
$ErrorActionPreference = "Stop"
$parts = Get-Content -Path "_Expand-Part1.txt","_Expand-Part2.txt" -Raw
$full = $parts -join ""
Set-Content -Path "_Expand-DownloadScript.ps1" -Value $full -Encoding UTF8
Write-Host "Joined expander written. Now expanding..."
powershell -File ._Expand-DownloadScript.ps1
Write-Host "Done. Delete the helper files after verifying Invoke-CMDownloadBIOSPackage.ps1"
