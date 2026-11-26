<#
  wx.ps1 - operate the PC WeChat mini-program window (process WeChatAppEx, Chromium/CEF window).
  Coordinates are RELATIVE to that window's top-left corner.

  Commands:
    info                       print hwnd / rect / size / foreground state
    shot   -Out a.png          activate + capture the window
    click  -X 100 -Y 200 [-N 1]   click at relative coordinates
    dclick -X 100 -Y 200       double click
    type   -Text "stubborn"    type text (CEF accepts normal keystrokes)
    key    -Vk 13 [-N 1]       press a key (13 Enter, 8 Backspace)
    drag   -X1 -Y1 -X2 -Y2     drag (scroll content)

  Install: Set-ExecutionPolicy -Scope Process Bypass -Force
#>
param(
  [Parameter(Mandatory=$true, Position=0)][string]$Cmd,
  [int]$X = -1, [int]$Y = -1,
  [int]$X1 = -1, [int]$Y1 = -1, [int]$X2 = -1, [int]$Y2 = -1,
  [string]$Text = '',
  [string]$Out = '',
  [int]$N = 1,
  [int]$Vk = 0,
  [int]$Wait = 700
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class WX {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern IntPtr SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr SetFocus(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool f);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, System.UIntPtr e);
  [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, System.UIntPtr dwExtraInfo);
  [DllImport("user32.dll")] public static extern uint MapVirtualKey(uint uCode, uint uMapType);
}
'@
function Get-TargetWindow {
  $p = Get-Process WeChatAppEx -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
  if (-not $p) { throw 'WeChatAppEx window not found (is the mini-program open in PC WeChat?)' }
  return $p.MainWindowHandle
}
function Invoke-Activate {
  $h = Get-TargetWindow
  [void][WX]::ShowWindow($h, 9)
  [void][WX]::BringWindowToTop($h)
  [WX]::keybd_event(0x12,0,0,[System.UIntPtr]::Zero); [WX]::keybd_event(0x12,0,2,[System.UIntPtr]::Zero)
  [void][WX]::SetForegroundWindow($h)
  $procId = [uint32]0
  $tid = [WX]::GetWindowThreadProcessId($h, [ref]$procId)
  $cur = [WX]::GetCurrentThreadId()
  [void][WX]::AttachThreadInput($cur, $tid, $true)
  [void][WX]::SetForegroundWindow($h); [void][WX]::SetFocus($h)
  [void][WX]::AttachThreadInput($cur, $tid, $false)
  Start-Sleep -Milliseconds 250
  return @{ Hwnd = $h; FgMatch = ([WX]::GetForegroundWindow() -eq $h) }
}
function Invoke-Shot([string]$Path) {
  $null = Invoke-Activate
  $h = Get-TargetWindow
  $r = New-Object WX+RECT
  [void][WX]::GetWindowRect($h, [ref]$r)
  $w = $r.Right - $r.Left; $ht = $r.Bottom - $r.Top
  $bmp = New-Object System.Drawing.Bitmap $w, $ht
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($r.Left, $r.Top, 0, 0, $bmp.Size)
  $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
  $g.Dispose(); $bmp.Dispose()
  "RECT=$($r.Left),$($r.Top) SIZE=${w}x${ht} OUT=$Path"
}
function Invoke-Click([int]$rx, [int]$ry, [int]$count = 1, [int]$delay = 600) {
  $null = Invoke-Activate
  $h = Get-TargetWindow
  $r = New-Object WX+RECT
  [void][WX]::GetWindowRect($h, [ref]$r)
  $sx = $r.Left + $rx; $sy = $r.Top + $ry
  [void][WX]::SetCursorPos($sx, $sy)
  Start-Sleep -Milliseconds 100
  for ($i = 0; $i -lt $count; $i++) {
    [WX]::mouse_event(0x0002,0,0,0,[System.UIntPtr]::Zero)
    Start-Sleep -Milliseconds 40
    [WX]::mouse_event(0x0004,0,0,0,[System.UIntPtr]::Zero)
    Start-Sleep -Milliseconds 120
  }
  Start-Sleep -Milliseconds $delay
  "CLICKED rel=$rx,$ry abs=$sx,$sy count=$count"
}
switch ($Cmd) {
  'info' { $a = Invoke-Activate; $h = $a.Hwnd; $r = New-Object WX+RECT; [void][WX]::GetWindowRect($h,[ref]$r); "HWND=$h RECT=$($r.Left),$($r.Top) SIZE=$($r.Right-$r.Left)x$($r.Bottom-$r.Top) FG_MATCH=$($a.FgMatch)" }
  'shot' { if (-not $Out) { $Out = Join-Path (Get-Location) 'wx.png' }; Invoke-Shot $Out }
  'click' { Invoke-Click $X $Y $N $Wait }
  'dclick' { Invoke-Click $X $Y 2 $Wait }
  'type' {
    if (-not $Text) { throw 'type requires -Text' }
    $null = Invoke-Activate
    Start-Sleep -Milliseconds 150
    [System.Windows.Forms.SendKeys]::SendWait($Text)
    Start-Sleep -Milliseconds $Wait
    "TYPED=$Text"
  }
  'key' {
    if ($Vk -le 0) { throw 'key requires -Vk' }
    $null = Invoke-Activate
    for ($i = 0; $i -lt $N; $i++) {
      [WX]::keybd_event([byte]$Vk, [byte][WX]::MapVirtualKey([uint32]$Vk,0), 0, [System.UIntPtr]::Zero)
      Start-Sleep -Milliseconds 40
      [WX]::keybd_event([byte]$Vk, [byte][WX]::MapVirtualKey([uint32]$Vk,0), 2, [System.UIntPtr]::Zero)
      Start-Sleep -Milliseconds 150
    }
    Start-Sleep -Milliseconds 300
    "KEY vk=$Vk n=$N"
  }
  'drag' {
    $null = Invoke-Activate
    $h = Get-TargetWindow; $r = New-Object WX+RECT; [void][WX]::GetWindowRect($h,[ref]$r)
    $sx = $r.Left + $X1; $sy = $r.Top + $Y1; $ex = $r.Left + $X2; $ey = $r.Top + $Y2
    [void][WX]::SetCursorPos($sx,$sy); Start-Sleep -Milliseconds 120
    [WX]::mouse_event(0x0002,0,0,0,[System.UIntPtr]::Zero)
    $steps = 12
    for ($i=1; $i -le $steps; $i++) {
      [void][WX]::SetCursorPos([int]($sx + ($ex-$sx)*$i/$steps), [int]($sy + ($ey-$sy)*$i/$steps))
      Start-Sleep -Milliseconds 25
    }
    [WX]::mouse_event(0x0004,0,0,0,[System.UIntPtr]::Zero)
    Start-Sleep -Milliseconds $Wait
    "DRAGGED $X1,$Y1 -> $X2,$Y2"
  }
  default { throw "unknown command $Cmd (info|shot|click|dclick|type|key|drag)" }
}
