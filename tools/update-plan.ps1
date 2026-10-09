# ============================================================
# 3DMP · tools/update-plan.ps1 — генератор «Плана обновления»
# Вход: audit/findings.json. Выход: audit/update-plan.json, docs/UPDATE_PLAN.md,
# синхронизация блока в docs/BACKLOG.md между маркерами AUDIT:UPDATE_PLAN.
# ============================================================
param([string]$Root = $null, [int]$WaveCapacity = 20)
$ErrorActionPreference = 'Continue'
if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }
Set-Location $Root

$weights = @{ A = 12; B = 15; C = 15; D = 15; E = 10; F = 12; G = 6; H = 5; I = 5; J = 3; K = 2 }
$sevW = @{ Blocker = 4; Critical = 3; Major = 2; Minor = 1; Info = 0 }
$areaName = @{ A = 'Архитектура'; B = 'Функциональность/полнота'; C = 'Логика'; D = 'Применимость'; E = 'Данные'; F = 'Безопасность'; G = 'UX'; H = 'Производительность'; I = 'Эксплуатация'; J = 'Документация'; K = 'Интеграции' }

$fPath = Join-Path $Root 'audit\findings.json'
$items = @()
if (Test-Path $fPath) { try { $items = @(Get-Content $fPath -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { $items = @() } }

function P-Prio($it) {
  $sw = 0; if ($sevW.ContainsKey([string]$it.sev)) { $sw = $sevW[[string]$it.sev] }
  $aw = 10; if ($weights.ContainsKey([string]$it.area)) { $aw = $weights[[string]$it.area] }
  $imp = 0; try { $imp = [int](@($it.impact)[0]) } catch {}
  if ($imp -le 0) { $imp = 1 }
  $eff = 0; try { $eff = [int](@($it.effort)[0]) } catch {}
  if ($eff -le 0) { $eff = 1 }
  return [int][math]::Round($imp * $sw * $aw / $eff)
}
function P-Class($p) { if ($p -ge 60) { 'P0' } elseif ($p -ge 35) { 'P1' } elseif ($p -ge 18) { 'P2' } else { 'P3' } }
function depCat($a) { switch ($a) { 'E' { 0 } 'C' { 1 } 'F' { 1 } 'H' { 1 } 'A' { 2 } 'B' { 2 } 'G' { 2 } 'K' { 2 } 'D' { 3 } default { 3 } } }

$open = @($items | Where-Object { $_.status -notin @('done', 'wontfix', 'closed') })
$scored = foreach ($it in $open) { $it | Add-Member -NotePropertyName prio -NotePropertyValue (P-Prio $it) -Force; $it | Add-Member -NotePropertyName pclass -NotePropertyValue (P-Class (P-Prio $it)) -Force; $it }
$scored = @($scored | Sort-Object -Property @{ Expression = { $_.prio }; Descending = $true }, @{ Expression = { depCat $_.area } })

# волны
$waves = New-Object System.Collections.ArrayList
$idx = 0; $w = 1
while ($idx -lt $scored.Count) {
  $chunk = @($scored[$idx..([math]::Min($idx + $WaveCapacity - 1, $scored.Count - 1))])
  [void]$waves.Add([ordered]@{ version = ('v4.' + $w); items = $chunk })
  $idx += $WaveCapacity; $w++
}

$out = [ordered]@{ generated_at = (Get-Date).ToString('s'); capacity = $WaveCapacity; open = $scored.Count; waves = $waves }
[System.IO.File]::WriteAllText((Join-Path $Root 'audit\update-plan.json'), ($out | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($false)))

# --- метрики ---
$last = $null; $sp = Join-Path $Root 'audit\state.json'
if (Test-Path $sp) {
  try {
    $parsed = (Get-Content $sp -Raw -Encoding UTF8 | ConvertFrom-Json)
    if ($parsed -is [System.Array]) { if ($parsed.Count -gt 0) { $last = $parsed[$parsed.Count - 1] } } else { $last = $parsed }
  } catch { $last = $null }
}

# --- UPDATE_PLAN.md ---
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('# План обновления 3DMP Service (живой)')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('> Генерируется `tools/update-plan.ps1` по `audit/findings.json`. Не редактировать вручную; работы синхронизируются в `backlog` §3.')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('Сформировано: ' + (Get-Date).ToString('s'))
if ($last) { [void]$sb.AppendLine('Оценка overall: **' + (@($last.overall)[0]) + '%** (' + (@($last.rag)[0]) + '); находок: ' + (@($last.findings)[0]) + '.') }
[void]$sb.AppendLine('')
[void]$sb.AppendLine(('Открытых пунктов плана: **' + $scored.Count + '**; волн: **' + $waves.Count + '** (вместимость ' + $WaveCapacity + '/волна).'))
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## Топ-10')
[void]$sb.AppendLine('| P | ID | Область | Sev | Заголовок | Доказательство |')
[void]$sb.AppendLine('|---|---|---|---|---|---|')
if ($scored.Count -gt 0) {
  foreach ($it in $scored[0..([math]::Min(9, $scored.Count - 1))]) {
    if (-not $it) { continue }
    [void]$sb.AppendLine('| ' + $it.pclass + ' (' + $it.prio + ') | ' + $it.id + ' | ' + ($areaName[$it.area]) + ' | ' + $it.sev + ' | ' + ($it.title -replace '\|', '/') + ' | ' + ($it.evidence -replace '\|', '/') + ' |')
  }
}
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## Волны')
foreach ($wv in $waves) {
  [void]$sb.AppendLine('### ' + $wv.version)
  [void]$sb.AppendLine('| P | ID | Область | Sev | Заголовок | Effort |')
  [void]$sb.AppendLine('|---|---|---|---|---|---|')
  foreach ($it in $wv.items) {
    [void]$sb.AppendLine('| ' + $it.pclass + ' (' + $it.prio + ') | ' + $it.id + ' | ' + $it.area + ' | ' + $it.sev + ' | ' + ($it.title -replace '\|', '/') + ' | ' + $it.effort + ' |')
  }
  [void]$sb.AppendLine('')
}
[void]$sb.AppendLine('## Все находки')
[void]$sb.AppendLine('| ID | Область | Sev | P | Статус | Заголовок |')
[void]$sb.AppendLine('|---|---|---|---|---|---|')
foreach ($it in $scored) { [void]$sb.AppendLine('| ' + $it.id + ' | ' + $it.area + ' | ' + $it.sev + ' | ' + $it.prio + ' | ' + $it.status + ' | ' + ($it.title -replace '\|', '/') + ' |') }
[System.IO.File]::WriteAllText((Join-Path $Root 'docs\UPDATE_PLAN.md'), $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))

# --- синхронизация BACKLOG §3 между маркерами ---
$bl = Join-Path $Root 'docs\BACKLOG.md'
if (Test-Path $bl) {
  $b = Get-Content $bl -Raw -Encoding UTF8
  $s = [regex]::Escape('<!-- AUDIT:UPDATE_PLAN:START -->'); $e = [regex]::Escape('<!-- AUDIT:UPDATE_PLAN:END -->')
  $inner = New-Object System.Text.StringBuilder
  [void]$inner.AppendLine('<!-- AUDIT:UPDATE_PLAN:START -->')
  [void]$inner.AppendLine('_Автогенерация `tools/update-plan.ps1` от ' + (Get-Date).ToString('s') + '. Полный план — `docs/UPDATE_PLAN.md`._')
  [void]$inner.AppendLine('')
  if ($scored.Count -eq 0) { [void]$inner.AppendLine('Открытых пунктов нет (по результатам авто-проверок).') }
  else {
    [void]$inner.AppendLine('| P | ID | Область | Sev | Заголовок |')
    [void]$inner.AppendLine('|---|---|---|---|---|')
    foreach ($it in $scored[0..([math]::Min(19, $scored.Count - 1))]) { if ($it) { [void]$inner.AppendLine('| ' + $it.pclass + ' | ' + $it.id + ' | ' + $it.area + ' | ' + $it.sev + ' | ' + ($it.title -replace '\|', '/') + ' |') } }
  }
  [void]$inner.AppendLine('<!-- AUDIT:UPDATE_PLAN:END -->')
  if ($b -match $s -and $b -match $e) {
    $b = [regex]::Replace($b, '(?s)' + $s + '.*?' + $e, [System.Text.RegularExpressions.MatchEvaluator] { param($m) $inner.ToString().TrimEnd() })
    [System.IO.File]::WriteAllText($bl, $b, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host 'update-plan: BACKLOG §3 синхронизирован'
  } else { Write-Host 'update-plan: маркеры BACKLOG не найдены — пропуск синхронизации' }
}
Write-Host ('update-plan: волн ' + $waves.Count + ', открытых ' + $scored.Count)
