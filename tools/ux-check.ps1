# ============================================================
# 3DMP Service - tools/ux-check.ps1
# U3: единообразие UX по модулям — поиск и пустые состояния в списках.
# Пишет отчёт docs/UX_REPORT.md. Только чтение apps/*/index.html.
#   powershell -ExecutionPolicy Bypass -File tools\ux-check.ps1
# ============================================================
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$appsDir = Join-Path $root 'apps'
$out = Join-Path $root 'docs\UX_REPORT.md'

$apps = Get-ChildItem -LiteralPath $appsDir -Directory | Sort-Object Name
$rows = @()
foreach ($a in $apps) {
  $p = Join-Path $a.FullName 'index.html'
  if (-not (Test-Path -LiteralPath $p)) { continue }
  $html = [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8)
  $hasList = ($html -match '(<table|class="olist"|class="tbl-wrap"|id="[a-zA-Z0-9_]*[Ll]ist")')
  $hasSearch = ($html -match 'type="search"|class="search"|id="[a-zA-Z0-9_]*[Qq]"')
  $hasEmpty = ($html -match 'Ничего не найдено|нет данных|Загрузка|нет\.|Нет |пока нет|пуст')
  $rows += [pscustomobject]@{ App = $a.Name; List = $hasList; Search = $hasSearch; Empty = $hasEmpty }
}

$withList = @($rows | Where-Object { $_.List })
$noSearch = @($withList | Where-Object { -not $_.Search })
$noEmpty = @($rows | Where-Object { -not $_.Empty })

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('# UX-отчёт: поиск и пустые состояния по модулям (U3)')
[void]$sb.AppendLine('')
[void]$sb.AppendLine("_Автогенерация ``tools/ux-check.ps1``. Всего модулей: $($rows.Count); с похожими на список блоками: $($withList.Count)._")
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## Модули с списками без поиска')
[void]$sb.AppendLine('')
if ($noSearch.Count) { foreach ($r in $noSearch) { [void]$sb.AppendLine("- ``apps/$($r.App)``") } } else { [void]$sb.AppendLine('- нет') }
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## Модули без явного пустого состояния')
[void]$sb.AppendLine('')
if ($noEmpty.Count) { foreach ($r in $noEmpty) { [void]$sb.AppendLine("- ``apps/$($r.App)``") } } else { [void]$sb.AppendLine('- нет') }
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## Полная таблица')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('| Модуль | Список | Поиск | Пустое состояние |')
[void]$sb.AppendLine('|---|---|---|---|')
foreach ($r in $rows) { [void]$sb.AppendLine("| $($r.App) | " + ($(if($r.List){'да'}else{'—'})) + ' | ' + ($(if($r.Search){'да'}else{'**нет**'})) + ' | ' + ($(if($r.Empty){'да'}else{'**нет**'})) + ' |') }

[System.IO.File]::WriteAllText($out, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
Write-Host ("ux-check: модулей {0}, без поиска {1}, без пустого состояния {2} -> docs/UX_REPORT.md" -f $rows.Count, $noSearch.Count, $noEmpty.Count)
