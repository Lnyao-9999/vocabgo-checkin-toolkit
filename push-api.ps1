# push-api.ps1 - 用 GitHub REST API 推送（git 直连 github.com 被墙时用）
# 用法： powershell -ExecutionPolicy Bypass -File .\push-api.ps1 -Token ghp_xxx [-Message "update"]
param(
  [Parameter(Mandatory=$true)][string]$Token,
  [string]$Owner = 'Lnyao-9999',
  [string]$Name  = 'vocabgo-checkin-toolkit',
  [string]$Message = 'chore: update toolkit'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$H = @{ Authorization = "token $Token"; 'User-Agent' = 'vocabgo-push'; Accept = 'application/vnd.github+json' }
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$apiRepo = "https://api.github.com/repos/$Owner/$Name"
$api = "$apiRepo/git"

$head = Invoke-RestMethod -Uri "$apiRepo/git/refs/heads/main" -Headers $H -ErrorAction SilentlyContinue
$parent = if ($head) { $head.object.sha } else { $null }
$files = Get-ChildItem $root -Recurse -File | Where-Object { $_.FullName -notmatch '\\\.git\\' }
"uploading $($files.Count) files..."
$tree = @()
foreach ($f in $files) {
  $rel = $f.FullName.Substring($root.Length + 1).Replace('\', '/')
  $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($f.FullName))
  $blob = Invoke-RestMethod -Uri "$api/blobs" -Method Post -Headers $H -Body (@{ content = $b64; encoding = 'base64' } | ConvertTo-Json -Compress) -ContentType 'application/json'
  $tree += @{ path = $rel; mode = '100644'; type = 'blob'; sha = $blob.sha }
}
$newTree = Invoke-RestMethod -Uri "$api/trees" -Method Post -Headers $H -Body (@{ tree = $tree } | ConvertTo-Json -Depth 6 -Compress) -ContentType 'application/json'
$parents = @(); if ($parent) { $parents = @($parent) }
$commit = Invoke-RestMethod -Uri "$api/commits" -Method Post -Headers $H -Body (@{ message = $Message; tree = $newTree.sha; parents = $parents } | ConvertTo-Json -Compress) -ContentType 'application/json'
if ($parent) {
  $ref = Invoke-RestMethod -Uri "$api/refs/heads/main" -Method Patch -Headers $H -Body (@{ sha = $commit.sha; force = $true } | ConvertTo-Json -Compress) -ContentType 'application/json'
} else {
  $ref = Invoke-RestMethod -Uri "$api/refs" -Method Post -Headers $H -Body (@{ ref = 'refs/heads/main'; sha = $commit.sha } | ConvertTo-Json -Compress) -ContentType 'application/json'
}
"PUSHED commit=$($commit.sha)  -> https://github.com/$Owner/$Name"
