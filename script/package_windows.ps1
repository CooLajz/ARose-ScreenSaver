param([string]$Binary = "build-windows/Release/ARose.scr")
$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)
python script/package_windows.py --binary $Binary
if ($LASTEXITCODE -ne 0) { throw "Windows packaging failed ($LASTEXITCODE)" }
