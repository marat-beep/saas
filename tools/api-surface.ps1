# ============================================================
# 3DMP Service - tools/api-surface.ps1
# U4: инвентаризация RPC. Какие функции вызываются из UI, а какие —
# только backend/API. Пишет docs/API_SURFACE.md.
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

$used = @(); $backend = @()
foreach ($fn in ($funcs | Sort-Object)) {
  if ($ui.IndexOf($fn, [System.StringComparison]::Ordinal) -ge 0) { $used += $fn } else { $backend += $fn }
}

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('# API-поверхность RPC (U4)')
[void]$sb.AppendLine('')
[void]$sb.AppendLine("_Автогенерация ``tools/api-surface.ps1``. Всего функций в миграциях: **$($funcs.Count)**; вызываются из UI: **$($used.Count)**; только backend/API: **$($backend.Count)**._")
[void]$sb.AppendLine('')
[void]$sb.AppendLine('«Только backend/API» — функции, не встречающиеся в `apps/` и `assets/js/`. Это внутренние хелперы, триггерные/служебные функции и кандидаты внешнего API (вызов по токену). Их не обязательно выводить в UI; их назначение — API/внутренняя логика.')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## Backend/API-функции')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('| Функция | Примечание |')
[void]$sb.AppendLine('|---|---|')
foreach ($fn in $backend) {
  $note = ''
  if ($fn -match '^admin_') { $note = 'админ-операция (только admin)' }
  elseif ($fn -match '^app_health') { $note = 'мониторинг/эксплуатация' }
  elseif ($fn -match '^app_api_|^app_webhook_') { $note = 'внешний API/вебхуки' }
  elseif ($fn -match '^app_norm_|^app_calc_') { $note = 'движок расчёта' }
  elseif ($fn -match '^(app_login_attempt|app_session|app_guard|app_can|app_is_|app_my_|app_require|app_dept_ok|app_production_allowed)') { $note = 'хелпер авторизации/прав' }
  [void]$sb.AppendLine("| ``$fn`` | $note |")
}
[void]$sb.AppendLine('')

[System.IO.File]::WriteAllText($out, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
Write-Host ("api-surface: функций {0}, из UI {1}, backend/API {2} -> docs/API_SURFACE.md" -f $funcs.Count, $used.Count, $backend.Count)
