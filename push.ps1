# push.ps1 - 一键推到 GitHub（会弹浏览器登录 / 或用凭证）
# 用法： powershell -ExecutionPolicy Bypass -File .\push.ps1 -RepoUrl https://github.com/<你的账号>/vocabgo-checkin-toolkit.git
param(
  [Parameter(Mandatory=$true)][string]$RepoUrl,
  [string]$GitExe = '',
  [string]$UserName = '',
  [string]$UserEmail = ''
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $GitExe) {
  foreach ($c in @("$env:USERPROFILE\..\tools\git\cmd\git.exe", 'A:\tools\git\cmd\git.exe', 'C:\Program Files\Git\cmd\git.exe')) { if (Test-Path $c) { $GitExe = $c; break } }
  if (-not $GitExe) { $g = Get-Command git -ErrorAction SilentlyContinue; if ($g) { $GitExe = $g.Source } }
}
if (-not $GitExe) { throw 'git not found. install Git for Windows, or pass -GitExe <path to git.exe>' }
Set-Location $root
if (-not (Test-Path (Join-Path $root '.git'))) { & $GitExe init; & $GitExe branch -M main }
if ($UserName)  { & $GitExe config user.name $UserName }
if ($UserEmail) { & $GitExe config user.email $UserEmail }
if (-not (& $GitExe config user.name))  { & $GitExe config user.name 'vocabgo-toolkit' }
if (-not (& $GitExe config user.email)) { & $GitExe config user.email 'vocabgo-toolkit@users.noreply.github.com' }
& $GitExe add -A
& $GitExe commit -m 'feat: 词达人打卡自动化工具包（元素识别版，无需固定坐标）' 2>$null
$remotes = & $GitExe remote
if ($remotes -notcontains 'origin') { & $GitExe remote add origin $RepoUrl } else { & $GitExe remote set-url origin $RepoUrl }
& $GitExe push -u origin main
Write-Host "`nDone. Open https://github.com 查看仓库。" -ForegroundColor Green
