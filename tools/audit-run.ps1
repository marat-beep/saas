# ============================================================
# 3DMP · tools/audit-run.ps1 — оркестратор аудита (L0-L2) и сбор Findings
# Запускает проверки, объединяет в audit/findings.json, ведёт audit/state.json,
# затем генерирует план (tools/update-plan.ps1). Не изменяет код проекта.
#   -Token sbp_...   — включает db-smoke (иначе L1 пропускается)
#   -SkipDb          — не запускать db-smoke
#   -SkipPlan        — не генерировать план
# ============================================================
param([string]$Root = $null, [string]$Token = $env:SUPABASE_ACCESS_TOKEN, [switch]$SkipDb, [switch]$SkipPlan)
$ErrorActionPreference = 'Continue'
if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }
Set-Location $Root
New-Item -ItemType Directory -Force -Path (Join-Path $Root 'audit\checks') | Out-Null

function Run-Child([string]$script, [string[]]$extra) {
  $cmdArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot $script)) + $extra
  & powershell @cmdArgs 2>&1 | ForEach-Object { Write-Host $_ }
  return [int]$LASTEXITCODE
}

$extraFindings = New-Object System.Collections.ArrayList
function Add-X($area, $sev, $title, $detail, $evidence, $effort, $impact) {
  [void]$extraFindings.Add([pscustomobject]@{ area = $area; sev = $sev; title = $title; detail = $detail; evidence = $evidence; method = 'run'; effort = $effort; impact = $impact; status = 'open' })
}
function Add-Id($it, $id) { $it | Add-Member -NotePropertyName id -NotePropertyValue $id -Force; return $it }

Write-Host '=== 3DMP audit-run ==='
Remove-Item (Join-Path $Root 'audit\checks\*.json') -ErrorAction SilentlyContinue

$ac = Run-Child 'audit.ps1' @()
if ($ac -ne 0) { Add-X 'A' 'Major' "Локальный автотест audit.ps1 вернул код $ac" 'Проверить вывод audit.ps1.' 'tools/audit.ps1' 2 3 }
Run-Child 'audit-deep.ps1'  @('-Root', $Root) | Out-Null
Run-Child 'trace-matrix.ps1' @('-Root', $Root) | Out-Null
Run-Child 'db-integrity.ps1' @('-Root', $Root) | Out-Null
Run-Child 'security-check.ps1' @('-Root', $Root) | Out-Null
Run-Child 'perf-check.ps1' @('-Root', $Root) | Out-Null

if ((-not $SkipDb) -and $Token) {
  $dc = Run-Child 'db-smoke.ps1' @('-Token', $Token)
  if ($dc -ne 0) { Add-X 'E' 'Major' "db-smoke.ps1 вернул код $dc" 'Проблемы БД/перегрузки/кодировка.' 'tools/db-smoke.ps1' 2 3 }
} else { Add-X 'I' 'Info' 'db-smoke пропущен (нет токена)' 'L1 не выполнялся; задайте -Token или env SUPABASE_ACCESS_TOKEN.' 'tools/audit-run.ps1' 1 1 }

# --- merge ---
$all = New-Object System.Collections.ArrayList
foreach ($f in Get-ChildItem (Join-Path $Root 'audit\checks') -Filter '*.json') {
  try { $j = Get-Content $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json; foreach ($it in $j.findings) { [void]$all.Add($it) } } catch { Write-Host "skip $($f.Name): $_" }
}
foreach ($it in $extraFindings) { [void]$all.Add($it) }

$i = 0
$final = New-Object System.Collections.ArrayList
foreach ($it in $all) { $i++; $it | Add-Member -NotePropertyName id -NotePropertyValue ('F-{0:D4}' -f $i) -Force; [void]$final.Add($it) }
[System.IO.File]::WriteAllText((Join-Path $Root 'audit\findings.json'), (ConvertTo-Json -InputObject @($final) -Depth 6), (New-Object System.Text.UTF8Encoding($false)))

# --- scoring ---
$weights = @{ A = 12; B = 15; C = 15; D = 15; E = 10; F = 12; G = 6; H = 5; I = 5; J = 3; K = 2 }
$sevW = @{ Blocker = 4; Critical = 2; Major = 1; Minor = 0.3; Info = 0 }
$areas = 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K'
$ded = @{}; foreach ($a in $areas) { $ded[$a] = 0.0 }
$counts = @{ Blocker = 0; Critical = 0; Major = 0; Minor = 0; Info = 0 }
foreach ($it in $final) {
  $a = $it.area; $s = $it.sev
  if ($counts.ContainsKey($s)) { $counts[$s]++ }
  if ($ded.ContainsKey($a) -and $sevW.ContainsKey($s)) { $ded[$a] += $sevW[$s] }
}
$sumW = 0.0; $acc = 0.0; $areaPct = @{}
foreach ($a in $areas) { $sc = [math]::Max(0, [math]::Min(4, 4 - $ded[$a])); $pct = [math]::Round($sc / 4 * 100, 1); $areaPct[$a] = $pct; $acc += $sc / 4 * $weights[$a]; $sumW += $weights[$a] }
$overall = [math]::Round($acc / $sumW * 100, 1)
$rag = if ($overall -ge 85) { 'green' } elseif ($overall -ge 70) { 'yellow' } else { 'red' }

$rec = [ordered]@{ at = (Get-Date).ToString('s'); findings = $final.Count; counts = $counts; areaPct = $areaPct; overall = $overall; rag = $rag }
$statePath = Join-Path $Root 'audit\state.json'
$hist = @()
if (Test-Path $statePath) { try { $hist = @(Get-Content $statePath -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { $hist = @() } }
$hist += $rec
[System.IO.File]::WriteAllText($statePath, (ConvertTo-Json -InputObject @($hist) -Depth 6), (New-Object System.Text.UTF8Encoding($false)))

Write-Host ''
Write-Host ("ИТОГ: overall " + $overall + "% (" + $rag + "); находок " + $final.Count + " [B:" + $counts.Blocker + " C:" + $counts.Critical + " M:" + $counts.Major + " m:" + $counts.Minor + "]")

if (-not $SkipPlan) { Run-Child 'update-plan.ps1' @('-Root', $Root) | Out-Null }

if ($counts.Blocker -gt 0 -or $counts.Critical -gt 0) { exit 1 } else { exit 0 }
