param(
    [string]$Binary = 'build-windows/Release/ARose.scr',
    [ValidateRange(2,600)][int]$Seconds = 30,
    [string[]]$Backends = @('hardware'),
    [ValidateSet('direct3d','cached-halo','reference')][string]$Drawing = 'direct3d',
    [switch]$CpuOverlay,
    [string]$OutputDirectory = ('build-windows/performance/' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
)
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
$binaryPath = (Resolve-Path -LiteralPath $Binary).Path
if (Test-Path -LiteralPath $OutputDirectory) { throw 'Choose a new output directory to preserve previous measurements.' }
$directory = New-Item -ItemType Directory -Path $OutputDirectory
$results = @()
foreach ($backend in $Backends) {
    if ($backend -notin @('default','hardware','software')) { throw "Unknown backend: $backend" }
    $report = Join-Path $directory.FullName ($backend + '.json')
    # Windows paths cannot contain quotes. Quote the report path for spaces.
    # ShellExecute treats .scr as an installed screen saver and replaces /b
    # with /S. Start the PE executable directly so diagnostics keep their args.
    $start = New-Object System.Diagnostics.ProcessStartInfo
    $start.FileName = $binaryPath
    $start.Arguments = '/b "' + $report + '" ' + $Seconds + ' ' + $backend
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.EnvironmentVariables['AROSE_WINDOWS_RENDERER'] = $Drawing
    $start.EnvironmentVariables['AROSE_BENCHMARK_CPU_OVERLAY'] = $(if($CpuOverlay) {'1'} else {'0'})
    $process = [System.Diagnostics.Process]::Start($start)
    if (-not $process.WaitForExit(($Seconds + 30) * 1000)) {
        $process.Kill()
        throw "Benchmark timed out: $backend"
    }
    if (-not (Test-Path -LiteralPath $report)) { throw "Benchmark did not produce a report: $backend" }
    $result = Get-Content -LiteralPath $report -Raw | ConvertFrom-Json
    if ($process.ExitCode -ne 0 -or $result.exit_code -ne 0 -or $result.frames -eq 0) {
        throw "Benchmark failed: $backend; inspect $report"
    }
    if ($result.seconds -lt ($Seconds - 0.1) -or $result.width -ne 1280 -or $result.height -ne 720) {
        throw "Benchmark was interrupted or resized: $backend; inspect $report"
    }
    if ($Drawing -eq 'cached-halo' -and -not $result.halo_cache_used) {
        throw "Halo cache was unavailable: $backend; inspect $report"
    }
    if ($Drawing -eq 'direct3d' -and (-not $result.gpu_batch_used -or $result.draw_calls -ne 2)) {
        throw "Batched GPU renderer was unavailable: $backend; inspect $report"
    }
    $results += $result
}
$results | Format-Table backend, drawing, fps, cpu_one_core_percent, cpu_all_cores_percent, submit_ms_per_frame
Write-Output "Reports: $($directory.FullName)"
