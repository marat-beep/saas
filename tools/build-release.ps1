# ============================================================
# 3DMP Service · tools/build-release.ps1
# Собирает релиз для загрузки (FTP): копирует только деплой-артефакты
# и пакует в dist\saas-<yyyyMMdd-HHmm>.zip. Не льются: supabase/, docs/,
# tools/, dist/, .git, README.md, AGENTS.md.
# Запуск:  powershell -NoProfile -ExecutionPolicy Bypass -File tools\build-release.ps1
# ============================================================
param([string]$OutDir = "dist")
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot          # SAAS\
$deploy = @("index.html", "apps", "assets", "eco", "site", "web.config", "manifest.webmanifest", "sw.js")
$stamp = Get-Date -Format "yyyyMMdd-HHmm"
$stage = Join-Path $root (Join-Path $OutDir "saas")
$zip = Join-Path $root (Join-Path $OutDir ("saas-" + $stamp + ".zip"))

Write-Host "3DMP release build"
if (Test-Path $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
New-Item -ItemType Directory -Path $stage -Force | Out-Null

foreach ($item in $deploy) {
  $src = Join-Path $root $item
  if (-not (Test-Path -LiteralPath $src)) { Write-Warning "нет: $item"; continue }
  $dst = Join-Path $stage $item
  if ((Get-Item -LiteralPath $src).PSIsContainer) {
    Copy-Item -LiteralPath $src -Destination $dst -Recurse -Force
  } else {
    Copy-Item -LiteralPath $src -Destination $dst -Force
  }
  Write-Host ("+ " + $item)
}

# исключаем только служебный .git (рекурсивно) и корневые служебные каталоги;
# ВАЖНО: не трогать вложенные каталоги модулей с такими именами (например apps/docs).
Get-ChildItem -LiteralPath $stage -Recurse -Force -Directory -Filter ".git" |
  ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force }
foreach ($name in @(".git", ".gitignore", "supabase", "docs", "tools", "dist")) {
  $p = Join-Path $stage $name
  if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Recurse -Force }
}

if (Test-Path $zip) { Remove-Item -LiteralPath $zip -Force }
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($stage, $zip)
$size = [math]::Round((Get-Item -LiteralPath $zip).Length / 1MB, 2)
Write-Host ("Готово: " + $zip + " (" + $size + " МБ)")
