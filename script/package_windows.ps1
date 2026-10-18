param([string]$Binary = "build-windows/Release/ARose.scr")
$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)
python script/package_windows.py --binary $Binary
if ($LASTEXITCODE -ne 0) { throw "Windows packaging failed ($LASTEXITCODE)" }

$iscc = Get-Command ISCC.exe -ErrorAction SilentlyContinue
if (-not $iscc) {
    $defaultCompiler = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
    if (Test-Path $defaultCompiler) { $iscc = Get-Item $defaultCompiler }
}
if (-not $iscc) { throw "Inno Setup 6 is required on the BUILD machine to produce the installer." }
$binaryDir = Split-Path (Resolve-Path $Binary) -Parent
$compilerPath = if ($iscc -is [System.IO.FileInfo]) { $iscc.FullName } else { $iscc.Source }
$version = python script/release_version.py --format version
if ($LASTEXITCODE -ne 0) { throw "Release metadata mismatch" }
& $compilerPath "/DBinaryDir=$binaryDir" "/DAppVersion=$version" Windows/Installer.iss
if ($LASTEXITCODE -ne 0) { throw "Windows installer packaging failed ($LASTEXITCODE)" }

Get-ChildItem dist/releases -File | Where-Object { $_.Extension -in '.exe','.scr' } | ForEach-Object {
    $digest = (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower()
    "$digest  $($_.Name)" | Set-Content -Encoding ascii ($_.FullName + '.sha256')
}
