# ============================================================
# 3DMP Service · tools/audit.ps1 — локальный автотест (W12)
# Проверки: каталог (id/связи/ссылки/дубли), shell.js и nav.js на всех страницах,
#           согласованность версий ассетов, синтаксис JS.
# Запуск: powershell -ExecutionPolicy Bypass -File tools\audit.ps1
# ============================================================
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$fail = 0

Write-Host "Аудит 3DMP Service · $root" -ForegroundColor Cyan

# --- node доступен? ---
$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) { Write-Host "!! node не найден — часть проверок пропущена" -ForegroundColor Yellow }

# --- 1. Каталог: id/связи/ссылки/дубли ---
if ($node) {
  $js = @'
global.window = {};
require('./assets/js/catalog.js');
var fs = require('fs');
var c = window.AppCatalog, ids = {}, dup = [], bad = [], miss = [];
c.apps.forEach(function (a) { if (ids[a.id]) dup.push(a.id); ids[a.id] = 1; });
c.apps.forEach(function (a) { (a.connects || []).forEach(function (x) { if (!ids[x]) bad.push(a.id + '->' + x); }); });
c.apps.forEach(function (a) { if (a.href && !fs.existsSync(a.href)) miss.push(a.href); });
console.log('CATALOG_VERSION=' + c.version);
console.log('CATALOG_APPS=' + c.apps.length);
console.log('CATALOG_DUP=' + dup.length);
console.log('CATALOG_BAD_CONNECTS=' + bad.length + (bad.length ? ' [' + bad.join(', ') + ']' : ''));
console.log('CATALOG_MISSING_HREF=' + miss.length + (miss.length ? ' [' + miss.join(', ') + ']' : ''));
'@
  $out = node -e $js
  $out | ForEach-Object { Write-Host "  $_" }
  if ($out -match 'CATALOG_DUP=[1-9]') { $fail++; Write-Host "!! Дубли id в каталоге" -ForegroundColor Red }
  if ($out -match 'CATALOG_BAD_CONNECTS=[1-9]') { $fail++; Write-Host "!! Битые связи каталога" -ForegroundColor Red }
  if ($out -match 'CATALOG_MISSING_HREF=[1-9]') { $fail++; Write-Host "!! Отсутствующие href" -ForegroundColor Red }
}

# --- 2. shell.js / nav.js на страницах apps/* ---
$pages = Get-ChildItem -Path 'apps' -Filter 'index.html' -Recurse
$noShell = @(); $noNav = @()
foreach ($p in $pages) {
  $t = [System.IO.File]::ReadAllText($p.FullName, [System.Text.Encoding]::UTF8)
  if ($t -notmatch 'shell\.js\?v=') { $noShell += $p.FullName.Substring($root.Length + 1) }
  if ($t -notmatch 'nav\.js\?v=') { $noNav += $p.FullName.Substring($root.Length + 1) }
}
if ($noShell.Count) { $fail++; Write-Host ("!! shell.js отсутствует: " + ($noShell -join ', ')) -ForegroundColor Red } else { Write-Host "  shell.js на всех страницах apps/ ($($pages.Count))" -ForegroundColor Green }
if ($noNav.Count) { $fail++; Write-Host ("!! nav.js отсутствует: " + ($noNav -join ', ')) -ForegroundColor Red } else { Write-Host "  nav.js на всех страницах apps/" -ForegroundColor Green }

# --- 3. Согласованность версий ассетов ---
function Versions($pattern) {
  $files = @(Get-ChildItem -Path 'apps' -Filter 'index.html' -Recurse) + @(Get-Item 'index.html')
  ($files | ForEach-Object { [regex]::Matches([System.IO.File]::ReadAllText($_.FullName, [System.Text.Encoding]::UTF8), $pattern) } |
    ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
}
$navV = Versions 'nav\.js\?v=(\d+)'
$shV = Versions 'shell\.js\?v=(\d+)'
Write-Host "  nav.js версии: $($navV -join ',')  | shell.js версии: $($shV -join ',')"
if ($navV.Count -gt 1) { $fail++; Write-Host "!! Разные версии nav.js на страницах" -ForegroundColor Red }
if ($shV.Count -gt 1) { $fail++; Write-Host "!! Разные версии shell.js на страницах" -ForegroundColor Red }
$cv = (Get-Content 'assets/js/nav.js' -Encoding UTF8 | Select-String "CATALOG_V = '(\d+)'").Matches.Groups[1].Value
$cv2 = (Get-Content 'assets/js/shell.js' -Encoding UTF8 | Select-String "CATALOG_V = '(\d+)'").Matches.Groups[1].Value
Write-Host "  CATALOG_V: nav=$cv shell=$cv2"
if ($cv -ne $cv2) { $fail++; Write-Host "!! CATALOG_V в nav.js и shell.js различаются" -ForegroundColor Red }
$catVP = Versions 'catalog\.js\?v=(\d+)'
Write-Host "  catalog.js версии на страницах: $($catVP -join ',')"
$catBad = @($catVP | Where-Object { $_ -ne $cv2 })
if ($catBad.Count) { $fail++; Write-Host "!! catalog.js на страницах не совпадает с CATALOG_V=${cv2}: $($catBad -join ',')" -ForegroundColor Red }

# --- 3b. Дубли id (#who/#logout/#tabs) и единая версия notify.js ---
$dupPages = @()
foreach ($p in $pages) {
  $t = [System.IO.File]::ReadAllText($p.FullName, [System.Text.Encoding]::UTF8)
  $w = ([regex]::Matches($t, 'id="who"')).Count
  $l = ([regex]::Matches($t, 'id="logout"')).Count
  $tb = ([regex]::Matches($t, 'id="tabs"')).Count
  if ($w -gt 1 -or $l -gt 1 -or $tb -gt 1) { $dupPages += ($p.FullName.Substring($root.Length + 1) + " who=$w logout=$l tabs=$tb") }
}
if ($dupPages.Count) { $fail++; Write-Host ("!! Дубли id на страницах: " + ($dupPages -join '; ')) -ForegroundColor Red } else { Write-Host "  Дублей id (#who/#logout/#tabs) нет" -ForegroundColor Green }
$notifyV = Versions 'notify\.js\?v=(\d+)'
Write-Host "  notify.js версии: $($notifyV -join ',')"
if ($notifyV.Count -gt 1) { $fail++; Write-Host "!! Разные версии notify.js" -ForegroundColor Red }

# --- 4. Синтаксис JS ---
if ($node) {
  $jsFiles = @(Get-ChildItem -Path 'assets/js' -Filter '*.js') + @(Get-ChildItem -Path 'apps' -Filter '*.js' -Recurse)
  $badJs = @()
  foreach ($f in $jsFiles) { node --check $f.FullName 2>$null; if ($LASTEXITCODE -ne 0) { $badJs += $f.FullName.Substring($root.Length + 1) } }
  if ($badJs.Count) { $fail++; Write-Host ("!! Синтаксические ошибки JS: " + ($badJs -join ', ')) -ForegroundColor Red } else { Write-Host "  Синтаксис JS ОК ($($jsFiles.Count) файлов)" -ForegroundColor Green }
}

Write-Host ""
if ($fail -eq 0) { Write-Host "ИТОГ: все проверки пройдены ✅" -ForegroundColor Green; exit 0 }
else { Write-Host "ИТОГ: проблем — $fail ❌" -ForegroundColor Red; exit 1 }
