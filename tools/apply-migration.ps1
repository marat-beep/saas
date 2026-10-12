# ============================================================
# 3DMP Service - tools/apply-migration.ps1
# Applies a SQL file (migration) to the Supabase project via Management API (UTF-8).
# Token sbp_... : -Token parameter, env SUPABASE_ACCESS_TOKEN, or -TokenFile.
# Token is not persisted. Usage:
#   powershell -ExecutionPolicy Bypass -File tools\apply-migration.ps1 -File supabase\migrations\0187_hr2.sql
# ============================================================
param(
  [Parameter(Mandatory = $true)][string]$File,
  [string]$Token = $env:SUPABASE_ACCESS_TOKEN,
  [string]$TokenFile = "$env:TEMP\kilo\sbp.txt",
  [string]$Project = 'zfkbzzmtbrueaksfaqbf'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

if ([string]::IsNullOrWhiteSpace($Token)) {
  if (Test-Path -LiteralPath $TokenFile) { $Token = (Get-Content -LiteralPath $TokenFile -Raw).Trim() }
}
if ([string]::IsNullOrWhiteSpace($Token)) { Write-Host 'Token is not set (param/env/-TokenFile).' -ForegroundColor Red; exit 2 }

$path = Join-Path $root $File
if (-not (Test-Path -LiteralPath $path)) { Write-Host "File not found: $path" -ForegroundColor Red; exit 2 }
$sql = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
Write-Host ("Applying: {0} ({1} chars)" -f $File, $sql.Length) -ForegroundColor Cyan

$json = @{ query = $sql } | ConvertTo-Json -Compress
$bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
try {
  $r = Invoke-RestMethod -Method Post -Uri "https://api.supabase.com/v1/projects/$Project/database/query" `
    -Headers @{ Authorization = "Bearer $Token" } -ContentType 'application/json; charset=utf-8' -Body $bytes -TimeoutSec 300
  Write-Host 'OK: migration applied.' -ForegroundColor Green
} catch {
  Write-Host ("SQL error: " + $_.Exception.Message) -ForegroundColor Red
  if ($_.ErrorDetails) { Write-Host $_.ErrorDetails.Message }
  exit 1
}
