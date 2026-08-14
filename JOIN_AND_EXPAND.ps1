$ErrorActionPreference='Stop'
$dir = $PSScriptRoot
$p1 = Get-Content -Raw (Join-Path $dir '_Expand-Part1.txt')
$p2 = Get-Content -Raw (Join-Path $dir '_Expand-Part2.txt')
$exp = Join-Path $dir '_Expand-DownloadScript.ps1'
($p1+$p2) | Set-Content -Path $exp -NoNewline -Encoding UTF8
& $exp
Remove-Item (Join-Path $dir '_Expand-Part1.txt'), (Join-Path $dir '_Expand-Part2.txt'), $exp -ErrorAction SilentlyContinue
Write-Host 'Done - Invoke-CMDownloadBIOSPackage.ps1 should now exist'
