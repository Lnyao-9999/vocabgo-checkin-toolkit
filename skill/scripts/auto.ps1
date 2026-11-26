<#
  auto.ps1 - element-based automation for the vocabgo mini-program (PC WeChat).

  Nothing is clicked by hard-coded coordinates: every action takes a fresh
  screenshot, detects the UI elements (ui.py), then clicks the chosen element.

  Commands:
    ui                        print detected elements as JSON
    shot   -Out a.png          screenshot for the model to read
    opt    -N 3               click the N-th answer row (1-based, top to bottom)
    chip   -N 2               click the N-th word chip / grid tile
    btn    -N 1               click the N-th solid green button (1 = topmost; -1 = bottom-most)
    continue                  click the bottom-most green button (继续 / 提交)
    back                      click the detected back control
    focus                     click the detected spelling input underline
    type   -Text word         paste text into the focused input (clipboard + Ctrl+V)
    spell  -Text word         focus + paste + click the bottom green button
    key    -Vk 8 [-N 3]       press a raw key
    info                      window geometry / foreground state

  Install: Set-ExecutionPolicy -Scope Process Bypass -Force
#>
param(
  [Parameter(Mandatory=$true, Position=0)][string]$Cmd,
  [int]$N = 1,
  [string]$Text = '',
  [string]$Out = '',
  [int]$Vk = 0,
  [int]$Wait = 700
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class AZ {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern IntPtr SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, System.UIntPtr e);
  [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, System.UIntPtr dwExtraInfo);
  [DllImport("user32.dll")] public static extern uint MapVirtualKey(uint uCode, uint uMapType);
}
'@
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Tmp = Join-Path $env:TEMP 'vocabgo_auto'

function Ensure-Tmp { New-Item -ItemType Directory -Force -Path $Tmp | Out-Null }

function Get-TargetWindow {
  $p = Get-Process WeChatAppEx -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
  if (-not $p) { throw 'WeChatAppEx window not found - open the mini-program in PC WeChat first' }
  return $p.MainWindowHandle
}

function Activate-Window {
  $h = Get-TargetWindow
  [void][AZ]::ShowWindow($h, 9)
  [void][AZ]::BringWindowToTop($h)
  [AZ]::keybd_event(0x12,0,0,[System.UIntPtr]::Zero); [AZ]::keybd_event(0x12,0,2,[System.UIntPtr]::Zero)
  [void][AZ]::SetForegroundWindow($h)
  Start-Sleep -Milliseconds 250
  return $h
}

function Get-Rect($h) {
  $r = New-Object AZ+RECT
  [void][AZ]::GetWindowRect($h, [ref]$r)
  return $r
}

function Save-Shot([string]$Path) {
  $h = Activate-Window
  Start-Sleep -Milliseconds 150
  $r = Get-Rect $h
  $w = $r.Right - $r.Left; $ht = $r.Bottom - $r.Top
  $bmp = New-Object System.Drawing.Bitmap $w, $ht
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($r.Left, $r.Top, 0, 0, $bmp.Size)
  $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
  $g.Dispose(); $bmp.Dispose()
  return $Path
}

function Get-Ui {
  Ensure-Tmp
  $png = Join-Path $Tmp 'ui.png'
  $null = Save-Shot $png
  $json = & python (Join-Path $ScriptDir 'ui.py') $png 2>$null
  if (-not $json) { throw 'ui.py produced no output (is python installed?)' }
  return ($json | ConvertFrom-Json)
}

function Click-Point([int]$rx, [int]$ry, [int]$delay = 700) {
  $h = Activate-Window
  $r = Get-Rect $h
  [void][AZ]::SetCursorPos($r.Left + $rx, $r.Top + $ry)
  Start-Sleep -Milliseconds 90
  [AZ]::mouse_event(0x0002,0,0,0,[System.UIntPtr]::Zero)
  Start-Sleep -Milliseconds 40
  [AZ]::mouse_event(0x0004,0,0,0,[System.UIntPtr]::Zero)
  Start-Sleep -Milliseconds $delay
  "CLICKED abs=$($r.Left + $rx),$($r.Top + $ry) rel=$rx,$ry"
}

function Paste-Text([string]$Value) {
  $Value | clip.exe
  Start-Sleep -Milliseconds 300
  $null = Activate-Window
  $ctrl = 0x11; $v = 0x56
  $sc = [byte][AZ]::MapVirtualKey([uint32]$ctrl,0); $sv = [byte][AZ]::MapVirtualKey([uint32]$v,0)
  [AZ]::keybd_event([byte]$ctrl,$sc,0,[System.UIntPtr]::Zero); Start-Sleep -Milliseconds 50
  [AZ]::keybd_event([byte]$v,$sv,0,[System.UIntPtr]::Zero); Start-Sleep -Milliseconds 50
  [AZ]::keybd_event([byte]$v,$sv,2,[System.UIntPtr]::Zero); Start-Sleep -Milliseconds 50
  [AZ]::keybd_event([byte]$ctrl,$sc,2,[System.UIntPtr]::Zero)
  Start-Sleep -Milliseconds 600
  "PASTED=$Value"
}

function Pick-Index($arr, [int]$idx) {
  if (-not $arr -or $arr.Count -eq 0) { throw 'no element detected on this page (check the screenshot)' }
  if ($idx -lt 0) { $idx = $arr.Count + $idx + 1 }
  if ($idx -lt 1 -or $idx -gt $arr.Count) { throw "index $idx out of range (1..$($arr.Count))" }
  return $arr[$idx - 1]
}

switch ($Cmd) {
  'info' {
    $h = Activate-Window
    $r = Get-Rect $h
    $fg = [AZ]::GetForegroundWindow()
    "HWND=$h RECT=$($r.Left),$($r.Top) SIZE=$($r.Right-$r.Left)x$($r.Bottom-$r.Top) FG_MATCH=$($fg -eq $h)"
  }
  'ui'   { $u = Get-Ui; $u | ConvertTo-Json -Depth 6 -Compress }
  'shot' { if (-not $Out) { $Out = Join-Path (Get-Location) 'shot.png' }; $p = Save-Shot $Out; "SHOT=$p" }
  'opt'  { $u = Get-Ui; $e = Pick-Index $u.rows $N; Click-Point $e.x $e.y $Wait }
  'chip' { $u = Get-Ui; $e = Pick-Index $u.chips $N; Click-Point $e.x $e.y $Wait }
  'btn'  { $u = Get-Ui; $e = Pick-Index $u.buttons $N; Click-Point $e.x $e.y $Wait }
  'continue' { $u = Get-Ui; $e = Pick-Index $u.buttons -1; Click-Point $e.x $e.y $Wait }
  'back' { $u = Get-Ui; if (-not $u.back) { throw 'back control not detected' }; Click-Point $u.back.x $u.back.y $Wait }
  'focus' { $u = Get-Ui; if (-not $u.input) { throw 'input underline not detected' }; Click-Point $u.input.x $u.input.y 500 }
  'type' { if (-not $Text) { throw 'type requires -Text' }; Paste-Text $Text }
  'spell' {
    if (-not $Text) { throw 'spell requires -Text' }
    $u = Get-Ui
    if (-not $u.input) { throw 'input underline not detected' }
    Click-Point $u.input.x $u.input.y 600 | Out-Null
    Paste-Text $Text | Out-Null
    Start-Sleep -Milliseconds 300
    $u2 = Get-Ui
    if (-not $u2.buttons) { throw 'submit button not detected after typing' }
    $b = $u2.buttons[-1]
    Click-Point $b.x $b.y 1000
  }
  'key' {
    if ($Vk -le 0) { throw 'key requires -Vk (8=Backspace 13=Enter)' }
    $null = Activate-Window
    for ($i = 0; $i -lt $N; $i++) {
      [AZ]::keybd_event([byte]$Vk,[byte][AZ]::MapVirtualKey([uint32]$Vk,0),0,[System.UIntPtr]::Zero)
      Start-Sleep -Milliseconds 40
      [AZ]::keybd_event([byte]$Vk,[byte][AZ]::MapVirtualKey([uint32]$Vk,0),2,[System.UIntPtr]::Zero)
      Start-Sleep -Milliseconds 140
    }
    "KEY vk=$Vk n=$N"
  }
  default { throw "unknown command: $Cmd (info|ui|shot|opt|chip|btn|continue|back|focus|type|spell|key)" }
}
