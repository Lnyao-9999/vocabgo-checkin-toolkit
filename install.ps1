# one-click install: copy skill into DSH skills dir + install audio deps
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$skillSrc = Join-Path $root 'skill'
$skillName = 'vocabgo-daily-checkin'
$dst = Join-Path $env:USERPROFILE (".agents\skills\$skillName")

Write-Host "== vocabgo-checkin-toolkit installer ==" -ForegroundColor Cyan
if (-not (Test-Path $skillSrc)) { throw "skill/ not found: $skillSrc" }

# 1) install skill
if (Test-Path $dst) {
  Write-Host "skill already exists, overwriting: $dst"
  Remove-Item $dst -Recurse -Force
}
New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
Copy-Item $skillSrc $dst -Recurse -Force
Write-Host "skill installed -> $dst" -ForegroundColor Green

# 2) python audio deps (optional)
$py = Get-Command python -ErrorAction SilentlyContinue
if ($py) {
  Write-Host "installing python audio deps (numpy pillow sounddevice soundcard) ..."
  & python -m pip install --only-binary=:all: --disable-pip-version-check `
      -i https://pypi.tuna.tsinghua.edu.cn/simple numpy pillow sounddevice soundcard
} else {
  Write-Host "python not found - audio recognition disabled (everything else still works)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "done. usage:" -ForegroundColor Cyan
Write-Host "  Set-ExecutionPolicy -Scope Process Bypass -Force"
Write-Host "  & `"$dst\scripts\wx.ps1`" info      # PC WeChat mini-program window"
Write-Host "  & `"$dst\scripts\pz.ps1`" info      # vivo phone mirror window"

