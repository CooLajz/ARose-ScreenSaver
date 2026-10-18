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
$app = Join-Path $env:ProgramFiles 'ARose ScreenSaver CI Custom'
$installArguments = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /DIR="' + $app + '"'
$install = Start-Process $installer.FullName -ArgumentList $installArguments -Wait -PassThru
if ($install.ExitCode -ne 0) { throw "Installer failed: $($install.ExitCode)" }
$systemSaver = Join-Path $env:WINDIR 'System32/ARose.scr'
$fixtureFolder = Join-Path $env:TEMP ('ARose-uninstall-' + [guid]::NewGuid())
$fixtureKey = "HKCU:\Software\ARoseUninstallFixture-$PID"
$loadedTestUsers = @()
$desktopKey = 'HKCU:\Control Panel\Desktop'
$oldSelection = (Get-ItemProperty $desktopKey -Name 'SCRNSAVE.EXE' -ErrorAction SilentlyContinue).'SCRNSAVE.EXE'
try {
    if ((Get-ItemProperty 'HKLM:\Software\CooLajz\ARose').InstallPath -ne $app) { throw 'Wrong installation marker.' }
    # An updater invokes the installer without /DIR; preserve the custom path.
    $upgrade = Start-Process $installer.FullName -ArgumentList '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-' -Wait -PassThru
    if ($upgrade.ExitCode -ne 0) { throw "Upgrade failed: $($upgrade.ExitCode)" }
    if ((Get-ItemProperty 'HKLM:\Software\CooLajz\ARose').InstallPath -ne $app -or
        -not (Test-Path "$app/ARose Control.exe")) { throw 'Upgrade changed the previous installation directory.' }
    if (Test-Path (Join-Path $env:ProgramFiles 'ARose ScreenSaver/ARose Control.exe')) { throw 'Upgrade created a second default installation.' }
    Write-Output 'PASS: silent upgrade preserves the custom installation directory.'
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
    # Use disposable loaded hives to simulate a different logged-in user. Never
    # load real offline profiles or change another existing user's preferences.
    New-Item "$fixtureKey\Control Panel\Desktop" -Force | Out-Null
    New-ItemProperty "$fixtureKey\Control Panel\Desktop" -Name Wallpaper -Value 'fixture-preserved' -PropertyType String -Force | Out-Null
    New-Item $fixtureFolder -ItemType Directory | Out-Null
    $baseHive = Join-Path $fixtureFolder 'base.hiv'
    & reg.exe save "HKCU\Software\ARoseUninstallFixture-$PID" $baseHive /y
    if ($LASTEXITCODE -ne 0) { throw 'Cannot save the disposable user hive.' }
    $testUsers = @("S-1-5-21-4294967200-4294967201-4294967202-$PID", "S-1-12-1-4294967200-4294967201-4294967202-$PID")
    foreach ($sid in $testUsers) {
        if (Test-Path "Registry::HKEY_USERS\$sid") { throw 'Disposable test SID already exists.' }
        $hiveFile = Join-Path $fixtureFolder "$sid.hiv"
        Copy-Item $baseHive $hiveFile
        & reg.exe load "HKU\$sid" $hiveFile
        if ($LASTEXITCODE -ne 0) { throw 'Cannot load the disposable user hive.' }
        $loadedTestUsers += $sid
    }
    New-ItemProperty $desktopKey -Name 'SCRNSAVE.EXE' -Value ('"' + "$app\ARose.scr" + '"') -PropertyType String -Force | Out-Null
    New-ItemProperty "Registry::HKEY_USERS\$($testUsers[0])\Control Panel\Desktop" -Name 'SCRNSAVE.EXE' -Value $systemSaver -PropertyType String -Force | Out-Null
    New-ItemProperty "Registry::HKEY_USERS\$($testUsers[1])\Control Panel\Desktop" -Name 'SCRNSAVE.EXE' -Value 'C:\Other\Unrelated.scr' -PropertyType String -Force | Out-Null
} finally {
    try {
        Get-Process | Where-Object { $_.Path -in @("$app/ARose.scr".Replace('/','\'), "$app/ARose Control.exe".Replace('/','\')) } | Stop-Process -Force
        $uninstall = Start-Process "$app/unins000.exe" -ArgumentList '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART' -Wait -PassThru
        if ($uninstall.ExitCode -ne 0) { throw "Uninstall failed: $($uninstall.ExitCode)" }
        if ($loadedTestUsers.Count -eq 2) {
            if ((Get-ItemProperty $desktopKey -Name 'SCRNSAVE.EXE' -ErrorAction SilentlyContinue) -or
                (Get-ItemProperty "Registry::HKEY_USERS\$($testUsers[0])\Control Panel\Desktop" -Name 'SCRNSAVE.EXE' -ErrorAction SilentlyContinue)) { throw 'Uninstall left ARose selected in a loaded user profile.' }
            $other = Get-ItemProperty "Registry::HKEY_USERS\$($testUsers[1])\Control Panel\Desktop"
            if ($other.'SCRNSAVE.EXE' -ne 'C:\Other\Unrelated.scr' -or $other.Wallpaper -ne 'fixture-preserved') { throw 'Uninstall changed unrelated user settings.' }
            if ((Get-ItemProperty "Registry::HKEY_USERS\$($testUsers[0])\Control Panel\Desktop").Wallpaper -ne 'fixture-preserved') { throw 'Uninstall changed the other user wallpaper.' }
            Write-Output 'PASS: uninstall clears only matching ARose selections across loaded user profiles.'
        }
    } finally {
        foreach ($sid in $loadedTestUsers) {
            & reg.exe unload "HKU\$sid"
            if ($LASTEXITCODE -ne 0) { Write-Warning 'Could not unload a disposable test hive.' }
        }
        if ($null -ne $oldSelection) {
            New-ItemProperty $desktopKey -Name 'SCRNSAVE.EXE' -Value $oldSelection -PropertyType String -Force | Out-Null
        } else { Remove-ItemProperty $desktopKey -Name 'SCRNSAVE.EXE' -ErrorAction SilentlyContinue }
        Remove-Item $fixtureKey -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item $fixtureFolder -Recurse -Force -ErrorAction SilentlyContinue
    }
}
if ((Test-Path $systemSaver) -or (Get-ItemProperty 'HKLM:\Software\CooLajz\ARose' -Name InstallPath -ErrorAction SilentlyContinue)) { throw 'Uninstall left system registration behind.' }
Write-Output 'PASS: machine uninstall removed the saver and installation marker.'
