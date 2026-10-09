# ============================================================
# 3DMP Service · tools/run-checks.ps1 — обёртка эксплуатационных проверок (W33)
# Запускает audit.ps1 (каталог/версии/shell/синтаксис) и db-smoke.ps1 (БД).
# Пишет лог в dist/checks/, возвращает код 0 (ок) или 1 (есть проблемы).
# Планировщик (Windows): Task Scheduler → powershell -ExecutionPolicy Bypass -File tools\run-checks.ps1
# CI: .github/workflows/checks.yml (токен — секретом SUPABASE_ACCESS_TOKEN).
# ============================================================
param(
  [string]$Token = $env:SUPABASE_ACCESS_TOKEN,
  [switch]$SkipDb,
  [string]$Project = 'zfkbzzmtbrueaksfaqbf'
)
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$logDir = Join-Path $root 'dist\checks'
if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$log = Join-Path $logDir ("checks-{0}.log" -f $stamp)
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Write-Log([string]$m) {
  $line = ('[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'), $m)
  Write-Host $line
  [System.IO.File]::AppendAllText($log, $line + "`r`n", $utf8)
}
function Run-Step([string]$name, [string]$file, [string[]]$extra) {
  if (-not (Test-Path -LiteralPath $file)) { Write-Log ("${name}: пропущен (нет $file)"); return 1 }
  $cmdArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $file) + $extra
  $out = & powershell @cmdArgs 2>&1 | Out-String
  [System.IO.File]::AppendAllText($log, $out + "`r`n", $utf8)
  Write-Host $out
  return [int]$LASTEXITCODE
}

$fail = 0
Write-Log '3DMP Service · run-checks (W33)'
Write-Log ('Корень: ' + $root)

$ac = Run-Step 'audit' (Join-Path $PSScriptRoot 'audit.ps1') @()
Write-Log ("audit exit=$ac")
if ($ac -ne 0) { $fail++ }

if (-not $SkipDb) {
  if ([string]::IsNullOrWhiteSpace($Token)) {
    Write-Log 'db-smoke: пропущен (нет токена; задайте -Token или переменную SUPABASE_ACCESS_TOKEN)'
  } else {
    $dc = Run-Step 'db-smoke' (Join-Path $PSScriptRoot 'db-smoke.ps1') @('-Token', $Token, '-Project', $Project)
    Write-Log ("db-smoke exit=$dc")
    if ($dc -ne 0) { $fail++ }
  }
}

if ($fail -eq 0) {
  Write-Log 'ИТОГ: все проверки пройдены ✅'
  Write-Log ('Лог: ' + $log)
  exit 0
} else {
  Write-Log ("ИТОГ: проблем — $fail ❌")
  Write-Log ('Лог: ' + $log)
  exit 1
}
