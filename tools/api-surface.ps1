# ============================================================
# 3DMP Service - tools/api-surface.ps1
# U4/PROP-05: инвентаризация RPC. Какие функции вызываются из UI, а какие —
# только backend/API (хелперы, триггеры, служебные, внешний API). Пишет docs/API_SURFACE.md.
#   powershell -ExecutionPolicy Bypass -File tools\api-surface.ps1
# ============================================================
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$migDir = Join-Path $root 'supabase\migrations'
$uiDirs = @((Join-Path $root 'apps'), (Join-Path $root 'assets\js'))
$out = Join-Path $root 'docs\API_SURFACE.md'

$fnRe = [regex]'create\s+(?:or\s+replace\s+)?function\s+public\.([a-z0-9_]+)'
$funcs = New-Object System.Collections.Generic.HashSet[string]
foreach ($f in Get-ChildItem -LiteralPath $migDir -Filter '*.sql') {
  $sql = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8)
  foreach ($m in $fnRe.Matches($sql)) { [void]$funcs.Add($m.Groups[1].Value) }
}

$uiText = New-Object System.Text.StringBuilder
foreach ($d in $uiDirs) {
  if (-not (Test-Path -LiteralPath $d)) { continue }
  foreach ($f in Get-ChildItem -LiteralPath $d -Recurse -File -Include *.js,*.html) {
    [void]$uiText.AppendLine([System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8))
  }
}
$ui = $uiText.ToString()

# Категория backend/API-функции (по имени) + примечание.
function Note-Of([string]$fn) {
  if ($fn -match '^admin_') { return @('админ', 'админ-операция (только admin)') }
  if ($fn -match '^app_health') { return @('мониторинг', 'мониторинг/эксплуатация') }
  if ($fn -match '^app_api_|^app_webhook_') { return @('внешний API', 'внешний API/вебхуки') }
  if ($fn -match '^app_norm_|^app_calc_|^app_bom_cost') { return @('расчёт', 'движок расчёта') }
  if ($fn -match '^(app_login_attempt|app_session|app_guard|app_can|app_is_|app_my_|app_require|app_dept_ok|app_production_allowed|app_role_is_staff|app_role_actions_get|current_tenant_ids|is_admin|is_staff|handle_new_user)') { return @('права', 'хелпер авторизации/прав (RLS)') }
  if ($fn -match '_trg$') { return @('триггер', 'триггерная функция') }
  if ($fn -match '^app_(smoke|selftest)') { return @('самопроверка', 'самопроверка/диагностика') }
  if ($fn -match 'totp|base32|base64') { return @('утилита', 'утилита (2FA/кодирование)') }
  if ($fn -match '_(url|encode|decode|eval)$') { return @('утилита', 'утилита') }
  if ($fn -match '^app_offline|_cache$|_queue$') { return @('офлайн', 'офлайн/PWA') }
  if ($fn -match '_(allowed|enabled|owner|is_staff)$') { return @('права', 'хелпер авторизации/прав (RLS)') }
  if ($fn -match '_(list|get|kpi|report|stats|overview|matrix|coverage|dashboard|board|gantt|calendar)$') { return @('аналитика', 'набор/отчёт (backend/аналитика)') }
  if ($fn -match '_(scan|sweep|build|run|dispatch|escalate|predictive|optimize|simulate)$') { return @('batch', 'пакетная/служебная операция') }
  if ($fn -match '(_save|_delete|_update|_set_status|_add|_close|_link|_move|_issue|_start|_stop|_act)$') { return @('служебная', 'служебная (вызывается из других RPC/триггеров)') }
  return @('прочее', '')
}

$used = @(); $backend = @()
foreach ($fn in ($funcs | Sort-Object)) {
  $rx = '(?<![a-z0-9_])' + [regex]::Escape($fn) + '(?![a-z0-9_])'
  if ($ui -match $rx) { $used += $fn } else { $backend += $fn }
}

$catCount = @{}
$rows = @()
foreach ($fn in $backend) {
  $n = Note-Of $fn
  if (-not $catCount.ContainsKey($n[0])) { $catCount[$n[0]] = 0 }
  $catCount[$n[0]] = $catCount[$n[0]] + 1
  $rows += [pscustomobject]@{ fn = $fn; cat = $n[0]; note = $n[1] }
}

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('# API-поверхность RPC (U4/PROP-05)')
[void]$sb.AppendLine('')
[void]$sb.AppendLine("_Автогенерация ``tools/api-surface.ps1``. Всего функций в миграциях: **$($funcs.Count)**; вызываются из UI (apps + assets/js): **$($used.Count)**; только backend/API: **$($backend.Count)**._")
[void]$sb.AppendLine('')
[void]$sb.AppendLine('«Только backend/API» — функции, не встречающиеся в `apps/` и `assets/js/` (сопоставление по границам слова, чтобы не путать похожие имена). Это внутренние хелперы/RLS, триггеры, служебные операции и кандидаты внешнего API (вызов по токену). Их не обязательно выводить в UI.')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## Сводка по категориям backend/API')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('| Категория | Кол-во |')
[void]$sb.AppendLine('|---|---|')
foreach ($k in ($catCount.Keys | Sort-Object)) { [void]$sb.AppendLine("| $k | $($catCount[$k]) |") }
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## Backend/API-функции')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('| Функция | Категория | Примечание |')
[void]$sb.AppendLine('|---|---|---|')
foreach ($r in ($rows | Sort-Object cat, fn)) { [void]$sb.AppendLine("| ``$($r.fn)`` | $($r.cat) | $($r.note) |") }
[void]$sb.AppendLine('')
[void]$sb.AppendLine('---')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('**Классификация (PROP-05):** функции внешнего API и часть служебных сохраняют `grant execute` для `anon/authenticated` (нужны внешним вызовам и реализациям, работающим от имени пользователя). Чисто внутренние хелперы/RLS/триггеры недоступны пользователю напрямую (не вызываются из клиента) и защищены проверками прав. Харденинг грантов — отдельная задача (PROP-03).')

[System.IO.File]::WriteAllText($out, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
Write-Host ("api-surface: функций {0}, из UI {1}, backend/API {2} -> docs/API_SURFACE.md" -f $funcs.Count, $used.Count, $backend.Count)
foreach ($k in ($catCount.Keys | Sort-Object)) { Write-Host ("  $k : $($catCount[$k])") }
