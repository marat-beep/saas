# ============================================================
# 3DMP · tools/perf-check.ps1 — производительность (L1/статик, область H). Только чтение.
# Пишет audit/checks/perf.json.
# ============================================================
param([string]$Root = $null)
$ErrorActionPreference = 'Continue'
if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }
Set-Location $Root

$findings = New-Object System.Collections.ArrayList
function Add-F($area, $sev, $title, $detail, $evidence, $effort, $impact) {
  [void]$findings.Add([ordered]@{ area = $area; sev = $sev; title = $title; detail = $detail; evidence = $evidence; method = 'perf'; effort = $effort; impact = $impact; status = 'open' })
}

$mig = ''
foreach ($f in Get-ChildItem (Join-Path $Root 'supabase\migrations') -Filter '*.sql') { $mig += (Get-Content $f.FullName -Raw) }

$hot = @('app_orders','app_naryads','app_qc_measures','app_tasks','app_integration_log','app_sessions')
foreach ($t in $hot) {
  if ($mig -notmatch ("on\s+public\.$t\s*\(")) { Add-F 'H' 'Minor' "Нет индекса по таблице $t" 'Добавить индекс по горячим фильтрам/сортировке.' 'supabase/migrations' 2 1 }
}

# крупные списки без limit (простая эвристика: сколько RPC-функций вообще)
$fnCount = ([regex]::Matches($mig, 'create\s+or\s+replace\s+function\s+public\.')).Count
if ($fnCount -gt 300) { Add-F 'H' 'Info' "Много RPC-функций: $fnCount" 'Проверять пагинацию/индексы горячих списков.' 'supabase/migrations' 3 1 }

$out = [ordered]@{ tool = 'perf'; at = (Get-Date).ToString('s'); findings = $findings }
New-Item -ItemType Directory -Force -Path (Join-Path $Root 'audit\checks') | Out-Null
[System.IO.File]::WriteAllText((Join-Path $Root 'audit\checks\perf.json'), ($out | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false)))
Write-Host ("perf-check: находок " + $findings.Count)
