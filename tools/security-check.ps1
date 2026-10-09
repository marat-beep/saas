# ============================================================
# 3DMP · tools/security-check.ps1 — секреты/публичные ключи (L1, область F). Только чтение.
# Пишет audit/checks/security.json.
# ============================================================
param([string]$Root = $null)
$ErrorActionPreference = 'Continue'
if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }
Set-Location $Root

$findings = New-Object System.Collections.ArrayList
function Add-F($area, $sev, $title, $detail, $evidence, $effort, $impact) {
  [void]$findings.Add([ordered]@{ area = $area; sev = $sev; title = $title; detail = $detail; evidence = $evidence; method = 'security'; effort = $effort; impact = $impact; status = 'open' })
}

$targets = @()
$targets += Get-ChildItem (Join-Path $Root 'assets') -Recurse -Include *.js,*.html -ErrorAction SilentlyContinue
$targets += Get-ChildItem (Join-Path $Root 'apps') -Recurse -Include *.js,*.html -ErrorAction SilentlyContinue
$targets += Get-ChildItem $Root -File -Include *.js,*.html -ErrorAction SilentlyContinue

$patSecret = 'sb_secret_[A-Za-z0-9_\-]+'
$patSbp    = 'sbp_[A-Za-z0-9]{20,}'
$patSvc    = 'service_role'
$patPwd    = "(password|passwd|pwd)\s*[:=]\s*['""][^'""]{3,}['""]"

foreach ($f in $targets) {
  $t = Get-Content $f.FullName -Raw
  $rel = $f.FullName -replace [regex]::Escape($Root), ''
  if ([regex]::IsMatch($t, $patSecret)) { Add-F 'F' 'Critical' "Найден секретный ключ (sb_secret_*)" 'Немедленно убрать из клиента и отозвать.' $rel 1 3 }
  if ([regex]::IsMatch($t, $patSbp))    { Add-F 'F' 'Critical' "Найден management-токен (sbp_*)" 'Секрет не должен попадать в клиент/репозиторий.' $rel 1 3 }
  if ([regex]::IsMatch($t, '"role"\s*:\s*"service_role"')) { Add-F 'F' 'Critical' "JWT с ролью service_role в клиенте" 'Секретный ключ не должен использоваться в браузере.' $rel 1 3 }
  elseif ([regex]::IsMatch($t, $patSvc)) { Add-F 'F' 'Info' "Упоминание service_role (не ключ)" 'Проверить, что это лишь комментарий/документация.' $rel 3 1 }
  if ([regex]::IsMatch($t, $patPwd))    { Add-F 'F' 'Minor' "Возможный пароль в коде" 'Проверить хардкод.' $rel 3 2 }
}

# config.js: должен быть только publishable
$cfg = Join-Path $Root 'assets\js\config.js'
if (Test-Path $cfg) {
  $c = Get-Content $cfg -Raw
  if ($c -notmatch 'sb_publishable_') { Add-F 'F' 'Minor' "config.js: нет publishable-ключа" 'Проверить конфигурацию клиента.' 'assets/js/config.js' 1 1 }
} else { Add-F 'F' 'Critical' "Нет assets/js/config.js" 'Клиент не получит конфигурацию.' 'assets/js/' 1 2 }

# .gitignore: dist/ не в git
$gi = Join-Path $Root '.gitignore'
if (Test-Path $gi) {
  $g = Get-Content $gi -Raw
  if ($g -notmatch '(?m)^\s*dist/?\s*$') { Add-F 'F' 'Minor' ".gitignore: не игнорируется dist/" 'Релизные архивы не должны попадать в git.' '.gitignore' 1 1 }
}

$out = [ordered]@{ tool = 'security'; at = (Get-Date).ToString('s'); findings = $findings }
New-Item -ItemType Directory -Force -Path (Join-Path $Root 'audit\checks') | Out-Null
[System.IO.File]::WriteAllText((Join-Path $Root 'audit\checks\security.json'), ($out | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false)))
Write-Host ("security-check: находок " + $findings.Count)
