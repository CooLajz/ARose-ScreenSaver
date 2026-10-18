# Intended only for an ephemeral Windows CI runner, never a user's workstation.
$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -ne 'true') { throw 'Run this installation test only in GitHub Actions.' }
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class SaverUI {
 [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left, Top, Right, Bottom; }
 [StructLayout(LayoutKind.Sequential)] public struct Monitor { public int Size; public Rect Bounds, Work; public uint Flags; }
 [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr w, out Rect r);
 [DllImport("user32.dll")] public static extern IntPtr MonitorFromWindow(IntPtr w, uint flags);
 [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern bool GetMonitorInfo(IntPtr m, ref Monitor info);
 [DllImport("user32.dll")] public static extern IntPtr GetDlgItem(IntPtr w, int id);
 [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr w, uint message, IntPtr wp, IntPtr lp);
}
'@
function Wait-Window($process) {
    for ($i=0; $i -lt 100; $i++) {
        $process.Refresh()
        if ($process.HasExited) { throw "Process exited before opening its window: $($process.ExitCode)" }
        if ($process.MainWindowHandle -ne 0) { return $process.MainWindowHandle }
        Start-Sleep -Milliseconds 100
    }
    throw 'Window did not appear.'
}
function Wait-Saver {
    for ($i=0; $i -lt 100; $i++) {
        $saver = Get-Process ARose -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($saver) { return $saver }
        Start-Sleep -Milliseconds 100
    }
    throw 'Companion did not launch the saver.'
}
$installer = Get-ChildItem dist/releases/*-Windows-x64-Setup.exe | Select-Object -First 1
$install = Start-Process $installer.FullName -ArgumentList '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-' -Wait -PassThru
if ($install.ExitCode -ne 0) { throw "Installer failed: $($install.ExitCode)" }
$app = Join-Path $env:ProgramFiles 'ARose ScreenSaver'
$systemSaver = Join-Path $env:WINDIR 'System32/ARose.scr'
try {
    if ((Get-ItemProperty 'HKLM:\Software\CooLajz\ARose').InstallPath -ne $app) { throw 'Wrong installation marker.' }
    if ((Get-FileHash $systemSaver).Hash -ne (Get-FileHash "$app/ARose.scr").Hash) { throw 'System saver copy differs.' }
    $control = Start-Process "$app/ARose Control.exe" -PassThru
    $window = Wait-Window $control
    $bounds = New-Object SaverUI+Rect
    $monitor = New-Object SaverUI+Monitor
    $monitor.Size = [Runtime.InteropServices.Marshal]::SizeOf($monitor)
    if (-not [SaverUI]::GetWindowRect($window,[ref]$bounds) -or -not [SaverUI]::GetMonitorInfo([SaverUI]::MonitorFromWindow($window,2),[ref]$monitor)) { throw 'Cannot inspect window placement.' }
    if ([Math]::Abs(($bounds.Left+$bounds.Right)-($monitor.Work.Left+$monitor.Work.Right)) -gt 4 -or [Math]::Abs(($bounds.Top+$bounds.Bottom)-($monitor.Work.Top+$monitor.Work.Bottom)) -gt 4) { throw 'Companion is not centered.' }
    [void][SaverUI]::PostMessage([SaverUI]::GetDlgItem($window,2003),0xF5,0,0)
    $saver = Wait-Saver
    $settings = Wait-Window $saver
    if ([SaverUI]::GetDlgItem($settings,1001) -eq 0) { throw 'Settings button opened animation instead of configuration.' }
    [void][SaverUI]::PostMessage($settings,0x10,0,0)
    if (-not $saver.WaitForExit(10000)) { throw 'Settings did not close.' }
    [void][SaverUI]::PostMessage([SaverUI]::GetDlgItem($window,2004),0xF5,0,0)
    $saver = Wait-Saver
    $preview = Wait-Window $saver
    if ([SaverUI]::GetDlgItem($preview,1001) -ne 0 -or $saver.MainWindowTitle -notmatch 'Preview|Náhled') { throw 'Preview did not open an animation window.' }
    [void][SaverUI]::PostMessage($preview,0x10,0,0)
    if (-not $saver.WaitForExit(10000)) { throw 'Preview did not close.' }
    [void][SaverUI]::PostMessage($window,0x10,0,0)
    if (-not $control.WaitForExit(10000)) { throw 'Companion did not close.' }
    Write-Output 'PASS: machine installation, system saver copy, centered companion, settings and windowed preview.'
} finally {
    Get-Process ARose,'ARose Control' -ErrorAction SilentlyContinue | Stop-Process -Force
    $uninstall = Start-Process "$app/unins000.exe" -ArgumentList '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART' -Wait -PassThru
    if ($uninstall.ExitCode -ne 0) { throw "Uninstall failed: $($uninstall.ExitCode)" }
}
if ((Test-Path $systemSaver) -or (Get-ItemProperty 'HKLM:\Software\CooLajz\ARose' -Name InstallPath -ErrorAction SilentlyContinue)) { throw 'Uninstall left system registration behind.' }
Write-Output 'PASS: machine uninstall removed the saver and installation marker.'
