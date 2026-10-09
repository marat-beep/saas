# ============================================================
# 3DMP · tools/audit-deep.ps1 — углублённый статик-анализ (L0, области A/B/J)
# Пишет findings в audit/checks/deep.json. Не изменяет проект.
# ============================================================
param([string]$Root = $null)
$ErrorActionPreference = 'Continue'
if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }
Set-Location $Root

$findings = New-Object System.Collections.ArrayList
function Add-F($area, $sev, $title, $detail, $evidence, $effort, $impact) {
  [void]$findings.Add([ordered]@{ area = $area; sev = $sev; title = $title; detail = $detail; evidence = $evidence; method = 'deep'; effort = $effort; impact = $impact; status = 'open' })
}

# --- CATALOG_V ---
$cv = $null
$shell = Join-Path $Root 'assets\js\shell.js'
if (Test-Path $shell) { $m = [regex]::Match((Get-Content $shell -Raw), "CATALOG_V\s*=\s*'(\d+)'"); if ($m.Success) { $cv = $m.Groups[1].Value } }

# --- catalog ids + apps on disk ---
$cat = Get-Content (Join-Path $Root 'assets\js\catalog.js') -Raw -Encoding UTF8
$catMap = @{}  # id -> href (только объекты приложений: содержат и id:, и href:)
foreach ($m in [regex]::Matches($cat, "\{[^{}]*\bid:\s*'([a-z0-9_]+)'[^{}]*\bhref:\s*'([^']*)'[^{}]*\}")) { $catMap[$m.Groups[1].Value] = $m.Groups[2].Value }
$catIds = New-Object System.Collections.Generic.HashSet[string]
foreach ($k in $catMap.Keys) { [void]$catIds.Add($k) }
$appsDirs = @(Get-ChildItem (Join-Path $Root 'apps') -Directory | Select-Object -ExpandProperty Name)

foreach ($id in $catMap.Keys) {
  $hp = Join-Path $Root ($catMap[$id] -replace '/', '\')
  if (-not (Test-Path $hp)) {
    Add-F 'B' 'Major' "Нет файла для модуля каталога '$id'" "Каталог ссылается на '$($catMap[$id])', файл не найден." "catalog.js id=$id" 1 2
  }
}
foreach ($d in $appsDirs) {
  if (-not $catIds.Contains($d)) { Add-F 'B' 'Minor' "Приложение без записи в каталоге: '$d'" "apps/$d есть на диске, но нет id в catalog.js." "apps/$d" 1 1 }
}

# --- asset version consistency (páginas) ---
$pages = @(Get-ChildItem (Join-Path $Root 'apps') -Filter 'index.html' -Recurse)
$badCat = New-Object System.Collections.Generic.HashSet[string]
$shellVers = New-Object System.Collections.Generic.HashSet[string]
$noShell = New-Object System.Collections.Generic.HashSet[string]
foreach ($p in $pages) {
  $t = Get-Content $p.FullName -Raw
  $mc = [regex]::Match($t, 'catalog\.js\?v=(\d+)'); if ($mc.Success -and $cv -and $mc.Groups[1].Value -ne $cv) { [void]$badCat.Add($mc.Groups[1].Value) }
  $ms = [regex]::Match($t, 'shell\.js\?v=(\d+)'); if ($ms.Success) { [void]$shellVers.Add($ms.Groups[1].Value) } else { [void]$noShell.Add(($p.FullName -replace [regex]::Escape($Root), '')) }
}
if ($badCat.Count) { Add-F 'A' 'Major' "Версия catalog.js на страницах расходится с CATALOG_V=$cv" ("Встречены: " + ($badCat -join ',')) 'tools/audit-deep.ps1' 1 2 }
if ($shellVers.Count -gt 1) { Add-F 'A' 'Major' "Разные версии shell.js на страницах" ("Версии: " + ($shellVers -join ',')) 'apps/*/index.html' 2 2 }
if ($noShell.Count) { Add-F 'A' 'Critical' "Страницы без подключения shell.js" ("Кол-во: " + $noShell.Count + "; пример: " + (@($noShell)[0])) 'apps/*/index.html' 2 3 }

# --- duplicate function definitions inside one file ---
foreach ($f in Get-ChildItem (Join-Path $Root 'assets\js') -Filter '*.js') {
  $names = [regex]::Matches((Get-Content $f.FullName -Raw), 'function\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(') | ForEach-Object { $_.Groups[1].Value }
  $dups = $names | Group-Object | Where-Object { $_.Count -gt 1 }
  foreach ($d in $dups) { Add-F 'A' 'Major' "Дублирование функции '$($d.Name)' в одном файле" "$($f.Name): определений $($d.Count)" ("assets/js/" + $f.Name) 2 2 }
}

# --- big files ---
foreach ($f in Get-ChildItem (Join-Path $Root 'apps\*\*.js') + (Get-ChildItem (Join-Path $Root 'assets\js\*.js')) ) {
  if ($f.Length -gt 150KB) { Add-F 'A' 'Minor' "Большой файл: $($f.Name)" ("$([math]::Round($f.Length/1KB)) КБ") ($f.FullName -replace [regex]::Escape($Root),'') 3 1 }
}

# --- TODO/FIXME ---
$todo = 0
foreach ($f in (Get-ChildItem (Join-Path $Root 'assets\js\*.js')) ) { $todo += ([regex]::Matches((Get-Content $f.FullName -Raw), 'TODO|FIXME|HACK')).Count }
if ($todo -gt 0) { Add-F 'J' 'Info' "Маркеры TODO/FIXME в JS: $todo" 'Код-долг в assets/js.' 'assets/js/*.js' 3 1 }

$out = [ordered]@{ tool = 'deep'; at = (Get-Date).ToString('s'); findings = $findings }
New-Item -ItemType Directory -Force -Path (Join-Path $Root 'audit\checks') | Out-Null
[System.IO.File]::WriteAllText((Join-Path $Root 'audit\checks\deep.json'), ($out | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false)))
Write-Host ("audit-deep: находок " + $findings.Count)
