# Join expander halves then run it
$ErrorActionPreference = "Stop"
$a = Get-Content -Raw (Join-Path $PSScriptRoot "_exp_a.ps1.txt")
$b = Get-Content -Raw (Join-Path $PSScriptRoot "_exp_b.ps1.txt")
$expander = Join-Path $PSScriptRoot "_Expand-DownloadScript.ps1"
Set-Content -Path $expander -Value ($a + $b) -Encoding UTF8 -NoNewline
Write-Host "Wrote expander ($((Get-Item $expander).Length) bytes) - running it..."
& $expander
