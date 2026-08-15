# Reconstruct full download script (v3.0.5 with -ForceDownload)
# Run:  powershell -File .\GET_FULL_DOWNLOAD_SCRIPT.ps1
$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$chunks = 1..6 | ForEach-Object { Join-Path $root ("_exp_chunk{0:D2}.txt" -f $_) }
$missing = $chunks | Where-Object { -not (Test-Path $_) }
if ($missing) { throw "Missing chunks: $missing" }
$expander = Join-Path $root "_Expand-DownloadScript.ps1"
$content = ($chunks | ForEach-Object { Get-Content -Raw $_ }) -join ""
Set-Content -Path $expander -Value $content -Encoding UTF8 -NoNewline
Write-Host "Wrote expander ($((Get-Item $expander).Length) bytes) - expanding full script..."
& $expander
Write-Host "Done. You can delete _exp_chunk*.txt, _Expand-DownloadScript.ps1 and GET_FULL_DOWNLOAD_SCRIPT.ps1"
