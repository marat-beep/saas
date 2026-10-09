# ============================================================
# 3DMP · tools/trace-matrix.ps1 — трассировка каталог↔apps↔RPC↔UI (L2, область B/C/A)
# Пишет audit/checks/trace.json и docs/AUDIT_TRACE.md. Только чтение.
# ============================================================
param([string]$Root = $null)
$ErrorActionPreference = 'Continue'
if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }
Set-Location $Root

$findings = New-Object System.Collections.ArrayList
function Add-F($area, $sev, $title, $detail, $evidence, $effort, $impact) {
  [void]$findings.Add([ordered]@{ area = $area; sev = $sev; title = $title; detail = $detail; evidence = $evidence; method = 'trace'; effort = $effort; impact = $impact; status = 'open' })
}

$cat = Get-Content (Join-Path $Root 'assets\js\catalog.js') -Raw -Encoding UTF8
$catMap = @{}
foreach ($m in [regex]::Matches($cat, "(?m)^\s*id:\s*'([a-z0-9_]+)',[^\r\n]*href:\s*'([^']+)'")) { $catMap[$m.Groups[1].Value] = $m.Groups[2].Value }
$catIds = New-Object System.Collections.Generic.List[string]
foreach ($k in $catMap.Keys) { [void]$catIds.Add($k) }
$appsDirs = @(Get-ChildItem (Join-Path $Root 'apps') -Directory | Select-Object -ExpandProperty Name)

# RPC вызовы из UI
$uiRpc = @{}
foreach ($f in Get-ChildItem (Join-Path $Root 'apps') -Recurse -Include *.js) {
  $t = Get-Content $f.FullName -Raw
  foreach ($m in [regex]::Matches($t, "rpc\(\s*'(app_[a-z0-9_]+)'")) {
    $n = $m.Groups[1].Value
    if (-not $uiRpc.ContainsKey($n)) { $uiRpc[$n] = New-Object System.Collections.Generic.HashSet[string] }
    [void]$uiRpc[$n].Add(($f.FullName -replace [regex]::Escape($Root), ''))
  }
}

# RPC определения из миграций
$defRpc = New-Object System.Collections.Generic.HashSet[string]
foreach ($f in Get-ChildItem (Join-Path $Root 'supabase\migrations') -Filter '*.sql') {
  foreach ($m in [regex]::Matches((Get-Content $f.FullName -Raw), 'function\s+public\.(app_[a-z0-9_]+)\s*\(')) { [void]$defRpc.Add($m.Groups[1].Value) }
}

# Сироты
$orphanCat = @($catIds | Where-Object { -not (Test-Path (Join-Path $Root ($catMap[$_] -replace '/', '\'))) })
if ($orphanCat.Count) { Add-F 'B' 'Major' "Каталог: модули без приложения ($($orphanCat.Count))" ($orphanCat -join ', ') 'catalog.js' 1 2 }
$orphanDisk = @($appsDirs | Where-Object { -not $catIds.Contains($_) })
if ($orphanDisk.Count) { Add-F 'B' 'Minor' "apps без каталога ($($orphanDisk.Count))" ($orphanDisk -join ', ') 'apps/' 1 1 }

# RPC вызывается в UI, но не определён
$calledNotDef = @($uiRpc.Keys | Where-Object { -not $defRpc.Contains($_) })
foreach ($n in $calledNotDef) { Add-F 'C' 'Critical' "RPC '$n' вызывается в UI, но не определён в миграциях" ('Вызов: ' + ($uiRpc[$n] -join ', ')) 'apps/*/*.js' 2 3 }

# RPC определён, но не вызывается из UI (info, backend/api)
$defNotCalled = @($defRpc | Where-Object { -not $uiRpc.ContainsKey($_) })
if ($defNotCalled.Count) { Add-F 'A' 'Info' "RPC только на backend (нет вызова из UI): $($defNotCalled.Count)" 'Кандидаты на проверку/документирование API.' 'supabase/migrations' 3 1 }

# Отчёт
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('# Матрица трассируемости (3DMP Service)')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('Сформировано: ' + (Get-Date).ToString('s') + ' · tools/trace-matrix.ps1')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## Сводка')
[void]$sb.AppendLine("- Модулей в каталоге: $($catIds.Count)")
[void]$sb.AppendLine("- Приложений на диске: $($appsDirs.Count)")
[void]$sb.AppendLine("- Сироты каталога (нет index.html): $($orphanCat.Count)")
[void]$sb.AppendLine("- apps без каталога: $($orphanDisk.Count)")
[void]$sb.AppendLine("- RPC вызывается в UI: $($uiRpc.Keys.Count)")
[void]$sb.AppendLine("- RPC определено в миграциях: $($defRpc.Count)")
[void]$sb.AppendLine("- UI→RPC без определения: $($calledNotDef.Count)")
[void]$sb.AppendLine("- RPC без UI-вызова (backend): $($defNotCalled.Count)")
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## UI→RPC без определения')
[void]$sb.AppendLine('| RPC | Вызвано из |')
[void]$sb.AppendLine('|---|---|')
foreach ($n in $calledNotDef) { [void]$sb.AppendLine("| $n | " + (($uiRpc[$n]) -join ', ') + ' |') }
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## RPC только backend (нет вызова из UI)')
[void]$sb.AppendLine('| RPC |')
[void]$sb.AppendLine('|---|')
foreach ($n in ($defNotCalled | Sort-Object)) { [void]$sb.AppendLine("| $n |") }
[System.IO.File]::WriteAllText((Join-Path $Root 'docs\AUDIT_TRACE.md'), $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))

$out = [ordered]@{ tool = 'trace'; at = (Get-Date).ToString('s'); findings = $findings }
New-Item -ItemType Directory -Force -Path (Join-Path $Root 'audit\checks') | Out-Null
[System.IO.File]::WriteAllText((Join-Path $Root 'audit\checks\trace.json'), ($out | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false)))
Write-Host ("trace-matrix: находок " + $findings.Count)
