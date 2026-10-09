# ============================================================
# 3DMP · tools/db-integrity.ps1 — целостность миграций/схемы (L1, область E). Только чтение.
# Пишет audit/checks/integrity.json.
# ============================================================
param([string]$Root = $null)
$ErrorActionPreference = 'Continue'
if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }
Set-Location $Root

$findings = New-Object System.Collections.ArrayList
function Add-F($area, $sev, $title, $detail, $evidence, $effort, $impact) {
  [void]$findings.Add([ordered]@{ area = $area; sev = $sev; title = $title; detail = $detail; evidence = $evidence; method = 'integrity'; effort = $effort; impact = $impact; status = 'open' })
}

$migs = Get-ChildItem (Join-Path $Root 'supabase\migrations') -Filter '*.sql' | Sort-Object Name
$maxN = 0
foreach ($f in $migs) { $m = [regex]::Match($f.Name, '^(\d{4})_'); if ($m.Success) { $n = [int]$m.Groups[1].Value; if ($n -gt $maxN) { $maxN = $n } } }

# не-idempotent паттерны
$nonIdem = New-Object System.Collections.ArrayList
foreach ($f in $migs) {
  $lines = Get-Content $f.FullName
  $ln = 0
  foreach ($l in $lines) {
    $ln++
    $low = $l.ToLower()
    if ($low -match '^\s*create\s+table\s+(?!if\s+not\s+exists)' -or $low -match '^\s*create\s+(unique\s+)?index\s+(?!if\s+not\s+exists)') {
      [void]$nonIdem.Add("$($f.Name):$ln")
    }
  }
}
if ($nonIdem.Count) { Add-F 'E' 'Major' "Не-idempotent DDL в миграциях: $($nonIdem.Count)" 'CREATE TABLE/INDEX без IF NOT EXISTS — повторный прогон apply_all может упасть.' ($nonIdem[0]) 2 3 }

# apply_all синхронизация
$apply = Join-Path $Root 'supabase\apply_all.sql'
if (Test-Path $apply) {
  $markers = ([regex]::Matches((Get-Content $apply -Raw), '-- >>>>>>>>>>')).Count
  if ($markers -ne $migs.Count) { Add-F 'E' 'Major' "apply_all.sql не синхронизирован с миграциями" "Маркеров $markers, миграций $($migs.Count)." 'supabase/apply_all.sql' 1 2 }
} else { Add-F 'E' 'Critical' "Нет supabase/apply_all.sql" 'Единый файл применения отсутствует.' 'supabase/' 1 3 }

# кодировка: признаки порчи (ромб/знаки вопроса в текстовых литералах-комментариях) — мягкая проверка по FAQ-текстам
$qmark = 0
foreach ($f in $migs) { $qmark += ([regex]::Matches((Get-Content $f.FullName -Raw), "'[^']*\?[^']*'")).Count }
if ($qmark -gt 0) { Add-F 'E' 'Info' "Знаки '?' в строковых литералах: $qmark" 'Проверить на порчу кодировки UTF-8 (many могут быть легитимны).' 'supabase/migrations' 3 1 }

$out = [ordered]@{ tool = 'integrity'; at = (Get-Date).ToString('s'); migrations = $migs.Count; max = $maxN; findings = $findings }
New-Item -ItemType Directory -Force -Path (Join-Path $Root 'audit\checks') | Out-Null
[System.IO.File]::WriteAllText((Join-Path $Root 'audit\checks\integrity.json'), ($out | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false)))
Write-Host ("db-integrity: миграций $($migs.Count), находок " + $findings.Count)
