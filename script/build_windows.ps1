param([string]$Python = 'python')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$cmake = Get-Command cmake.exe -ErrorAction SilentlyContinue
if ($cmake) {
    $cmakePath = $cmake.Source
} else {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path -LiteralPath $vswhere)) {
        throw 'Install Visual Studio 2022 C++ Build Tools, Windows SDK and CMake first.'
    }
    $vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if (-not $vs) { throw 'Visual Studio C++ tools were not found.' }
    $cmakePath = Join-Path $vs 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
    if (-not (Test-Path -LiteralPath $cmakePath)) { throw 'Install the C++ CMake tools component.' }
}
$ctest = Join-Path (Split-Path $cmakePath) 'ctest.exe'
$build = Join-Path $root 'build-windows'
& $Python (Join-Path $PSScriptRoot 'generate_windows_tables.py') --check
if ($LASTEXITCODE -ne 0) { throw 'Generated table validation failed.' }
& $cmakePath -S (Join-Path $root 'Windows') -B $build -G 'Visual Studio 17 2022' -A x64
if ($LASTEXITCODE -ne 0) { throw 'CMake configuration failed.' }
& $cmakePath --build $build --config Release
if ($LASTEXITCODE -ne 0) { throw 'Windows build failed.' }
& $ctest --test-dir $build -C Release --output-on-failure
if ($LASTEXITCODE -ne 0) { throw 'Windows tests failed.' }
& $Python (Join-Path $PSScriptRoot 'check_engine_parity.py') --executable (Join-Path $build 'Release\arose-engine-tests.exe')
if ($LASTEXITCODE -ne 0) { throw 'Swift/C++ parity validation failed.' }
