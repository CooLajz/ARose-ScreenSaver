# Intended only for an ephemeral Windows CI runner, never a user's workstation.
$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -ne 'true') { throw 'Run this installation test only in GitHub Actions.' }
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class SaverUI {
 public delegate bool EnumWindow(IntPtr window, IntPtr data);
 [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindow callback, IntPtr data);
 [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr window);
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr window, out uint pid);
 public static IntPtr FindWindow(uint pid) {
  IntPtr found=IntPtr.Zero;
  EnumWindows((w,data) => { uint owner; GetWindowThreadProcessId(w,out owner);
   if(owner==pid && IsWindowVisible(w)) { found=w; return false; } return true;
  },IntPtr.Zero);
  return found;
 }
 [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left, Top, Right, Bottom; }
 [StructLayout(LayoutKind.Sequential)] public struct Monitor { public int Size; public Rect Bounds, Work; public uint Flags; }
 [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr w, out Rect r);
 [DllImport("user32.dll")] public static extern IntPtr MonitorFromWindow(IntPtr w, uint flags);
 [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern bool GetMonitorInfo(IntPtr m, ref Monitor info);
 [DllImport("user32.dll")] public static extern IntPtr GetDlgItem(IntPtr w, int id);
 [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr w, uint message, IntPtr wp, IntPtr lp);
 [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr w, uint message, IntPtr wp, IntPtr lp);
}
'@
function Wait-Window($process) {
    for ($i=0; $i -lt 100; $i++) {
        $process.Refresh()
        if ($process.HasExited) { throw "Process exited before opening its window: $($process.ExitCode)" }
        $handle = [SaverUI]::FindWindow($process.Id)
        if ($handle -ne 0) { return $handle }
        Start-Sleep -Milliseconds 100
    }
    throw 'Window did not appear.'
}
function Wait-Saver {
    for ($i=0; $i -lt 100; $i++) {
        $saver = Get-Process | Where-Object { $_.Path -eq "$app/ARose.scr".Replace('/','\') } | Select-Object -First 1
        if ($saver) { return $saver }
        Start-Sleep -Milliseconds 100
    }
    throw 'Companion did not launch the saver.'
}
$installer = Get-ChildItem dist/releases/*-Windows-x64-Setup.exe | Select-Object -First 1
$releaseVersion = python script/release_version.py --format version
if ($LASTEXITCODE -ne 0) { throw 'Release version metadata mismatch.' }
$releaseBuild = python script/release_version.py --format build
if ($LASTEXITCODE -ne 0) { throw 'Release build metadata mismatch.' }
$info = $installer.VersionInfo
$installerVersion = '{0}.{1}.{2}.{3}' -f $info.FileMajorPart,$info.FileMinorPart,$info.FileBuildPart,$info.FilePrivatePart
if ($installerVersion -ne "$releaseVersion.$releaseBuild") { throw 'Installer fixed version does not match the packaged release build.' }
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
    # Keep the scheduling test local: no network check should become due.
    $updatesKey = 'HKCU:\Software\CooLajz\ARose\Updates'
    New-Item $updatesKey -Force | Out-Null
    New-ItemProperty $updatesKey -Name LastAttempt -Value ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) -PropertyType QWord -Force | Out-Null
    $taskName = 'ARose Update Check-' + [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    [void][SaverUI]::SendMessage([SaverUI]::GetDlgItem($window,2002),0xF5,0,0) # BM_CLICK
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
    if ($task.Actions.Execute -ne "$app\ARose Control.exe" -or $task.Actions.Arguments -ne '/weekly') { throw 'Wrong weekly task action.' }
    $boundary = $task.Triggers.StartBoundary
    [void][SaverUI]::PostMessage($window,0x10,0,0)
    if (-not $control.WaitForExit(10000)) { throw 'Companion did not close.' }
    $control = Start-Process "$app/ARose Control.exe" -PassThru
    $window = Wait-Window $control
    if ((Get-ScheduledTask -TaskName $taskName).Triggers.StartBoundary -ne $boundary) { throw 'Unchanged task was unnecessarily recreated.' }
    [void][SaverUI]::PostMessage($window,0x10,0,0)
    if (-not $control.WaitForExit(10000)) { throw 'Companion did not close.' }
    Disable-ScheduledTask -TaskName $taskName | Out-Null
    $control = Start-Process "$app/ARose Control.exe" -PassThru
    $window = Wait-Window $control
    if ((Get-ScheduledTask -TaskName $taskName).State -ne 'Disabled' -or
        [SaverUI]::SendMessage([SaverUI]::GetDlgItem($window,2002),0xF0,0,0).ToInt64() -ne 0 -or
        (Get-ItemProperty $updatesKey).Weekly -ne 0) { throw 'Companion ignored the explicit Windows task opt-out.' }
    [void][SaverUI]::SendMessage([SaverUI]::GetDlgItem($window,2002),0xF5,0,0)
    [void][SaverUI]::PostMessage($window,0x10,0,0)
    if (-not $control.WaitForExit(10000)) { throw 'Companion did not close.' }
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    # Reproduce the persisted opt-in plus missing task left by uninstall/reinstall.
    $control = Start-Process "$app/ARose Control.exe" -PassThru
    $window = Wait-Window $control
    $restored = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
    if ($restored.Actions.Execute -ne "$app\ARose Control.exe" -or
        [SaverUI]::SendMessage([SaverUI]::GetDlgItem($window,2002),0xF0,0,0).ToInt64() -ne 1) { throw 'Weekly task was not restored and reflected in the UI.' }
    [void][SaverUI]::SendMessage([SaverUI]::GetDlgItem($window,2002),0xF5,0,0)
    if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) { throw 'Opt-out left the weekly task registered.' }
    Write-Output 'PASS: weekly opt-in, unchanged registration, missing-task recovery and opt-out.'
    Write-Output 'Checking settings command.'
    [void][SaverUI]::PostMessage($window,0x111,2003,0)
    $saver = Wait-Saver
    $settings = Wait-Window $saver
    if ([SaverUI]::GetDlgItem($settings,1001) -eq 0) { throw 'Settings button opened animation instead of configuration.' }
    [void][SaverUI]::PostMessage($settings,0x10,0,0)
    if (-not $saver.WaitForExit(10000)) { throw 'Settings did not close.' }
    Write-Output 'Checking preview command.'
    [void][SaverUI]::PostMessage($window,0x111,2004,0)
    $saver = Wait-Saver
    $preview = Wait-Window $saver
    if ([SaverUI]::GetDlgItem($preview,1001) -ne 0 -or $saver.MainWindowTitle -notmatch 'Preview|Náhled') { throw 'Preview did not open an animation window.' }
    [void][SaverUI]::PostMessage($preview,0x10,0,0)
    if (-not $saver.WaitForExit(10000)) { throw 'Preview did not close.' }
    [void][SaverUI]::PostMessage($window,0x10,0,0)
    if (-not $control.WaitForExit(10000)) { throw 'Companion did not close.' }
    Write-Output 'PASS: machine installation, system saver copy, centered companion, settings and windowed preview.'
} finally {
    Get-Process | Where-Object { $_.Path -in @("$app/ARose.scr".Replace('/','\'), "$app/ARose Control.exe".Replace('/','\')) } | Stop-Process -Force
    $uninstall = Start-Process "$app/unins000.exe" -ArgumentList '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART' -Wait -PassThru
    if ($uninstall.ExitCode -ne 0) { throw "Uninstall failed: $($uninstall.ExitCode)" }
}
if ((Test-Path $systemSaver) -or (Get-ItemProperty 'HKLM:\Software\CooLajz\ARose' -Name InstallPath -ErrorAction SilentlyContinue)) { throw 'Uninstall left system registration behind.' }
Write-Output 'PASS: machine uninstall removed the saver and installation marker.'
