# ============================================================
# 3DMP Service · tools/apply-pending.ps1
# Применяет диапазон миграций (по умолчанию новые: 0256..9999) к Supabase через
# Management API, по порядку номеров. Все миграции идемпотентны (проверка tools/db-integrity.ps1).
# Токен sbp_ : -Token, env SUPABASE_ACCESS_TOKEN или -TokenFile (по умолчанию %TEMP%\kilo\sbp.txt).
# Пример:
#   powershell -ExecutionPolicy Bypass -File tools\apply-pending.ps1
#   powershell -ExecutionPolicy Bypass -File tools\apply-pending.ps1 -From 0255 -To 0271
# ============================================================
param(
  [string]$From = '0256',
  [string]$To = '9999',
  [string]$Token = $env:SUPABASE_ACCESS_TOKEN,
  [string]$TokenFile = "$env:TEMP\kilo\sbp.txt",
  [string]$Project = 'zfkbzzmtbrueaksfaqbf'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$mig = Join-Path $root 'supabase\migrations'

if ([string]::IsNullOrWhiteSpace($Token) -and (Test-Path -LiteralPath $TokenFile)) {
  $Token = (Get-Content -LiteralPath $TokenFile -Raw).Trim()
}
if ([string]::IsNullOrWhiteSpace($Token)) {
  Write-Host 'Токен не задан (-Token / env SUPABASE_ACCESS_TOKEN / -TokenFile). Применение отменено.' -ForegroundColor Red
  exit 2
}

$fromNum = [int]$From
$toNum = [int]$To
$files = Get-ChildItem -LiteralPath $mig -Filter '*.sql' |
  Where-Object { $n = [int]($_.Name.Substring(0, 4)); $n -ge $fromNum -and $n -le $toNum } |
  Sort-Object Name

if (-not $files.Count) { Write-Host 'Нет миграций в диапазоне.' -ForegroundColor Yellow; exit 0 }
Write-Host ("Применяю миграций: {0} ({1}..{2})" -f $files.Count, $files[0].Name, $files[$files.Count - 1].Name) -ForegroundColor Cyan

$ok = 0
foreach ($f in $files) {
  $sql = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8)
  $json = @{ query = $sql } | ConvertTo-Json -Compress
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
  try {
    Invoke-RestMethod -Method Post -Uri "https://api.supabase.com/v1/projects/$Project/database/query" `
      -Headers @{ Authorization = "Bearer $Token" } -ContentType 'application/json; charset=utf-8' -Body $bytes -TimeoutSec 300 | Out-Null
    Write-Host ("OK  " + $f.Name) -ForegroundColor Green
    $ok++
  } catch {
    Write-Host ("ОШИБКА " + $f.Name + ": " + $_.Exception.Message) -ForegroundColor Red
    if ($_.ErrorDetails) { Write-Host $_.ErrorDetails.Message }
    exit 1
  }
}
Write-Host ("Готово: применено {0} из {1}." -f $ok, $files.Count) -ForegroundColor Cyan
