# ============================================================
# 3DMP Service - tools/ux-check.ps1
# U3: единообразие UX по модулям — поиск и пустые состояния в списках.
# Пишет отчёт docs/UX_REPORT.md. Читает index.html И *.js модуля (списки часто
# строятся в JS). Пустое состояние требуется только у модулей со списками.
#   powershell -ExecutionPolicy Bypass -File tools\ux-check.ps1
# ============================================================
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$appsDir = Join-Path $root 'apps'
$out = Join-Path $root 'docs\UX_REPORT.md'

$reListHtml = '(<table|class="olist"|class="tbl-wrap"|class="tab2"|class="table"|id="[a-zA-Z0-9_]*[Ll]ist")'
$reListJs   = '(<table|<tbody|createElement\(''table''\))'
$reSearch   = '(type="search"|class="search"|id="[a-zA-Z0-9_]*[Qq]"|data-search)'
$reEmpty    = '(Ничего не найдено|нет данных|Загрузка|нет\.|Нет |пока нет|Нет записей|Услуг нет|Перевозчиков нет|пусто|пуст)'

$apps = Get-ChildItem -LiteralPath $appsDir -Directory | Sort-Object Name
$rows = @()
foreach ($a in $apps) {
  $p = Join-Path $a.FullName 'index.html'
  if (-not (Test-Path -LiteralPath $p)) { continue }
  $html = [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8)
  $js = ''
  foreach ($f in (Get-ChildItem -LiteralPath $a.FullName -Filter '*.js' -File -ErrorAction SilentlyContinue)) {
    $js += [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8) + "`n"
  }
  $hasList = ($html -match $reListHtml) -or ($js -match $reListJs)
  $hasSearch = ($html -match $reSearch)
  $hasEmpty = ($html -match $reEmpty) -or ($js -match $reEmpty)
  $rows += [pscustomobject]@{ App = $a.Name; List = $hasList; Search = $hasSearch; Empty = $hasEmpty }
}

$withList = @($rows | Where-Object { $_.List })
$noSearch = @($withList | Where-Object { -not $_.Search })
$noEmpty = @($withList | Where-Object { -not $_.Empty })

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('# UX-отчёт: поиск и пустые состояния по модулям (U3)')
[void]$sb.AppendLine('')
[void]$sb.AppendLine("_Автогенерация ``tools/ux-check.ps1``. Всего модулей: $($rows.Count); с похожими на список блоками (HTML+JS): $($withList.Count)._")
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## Модули с списками без поиска')
[void]$sb.AppendLine('')
if ($noSearch.Count) { foreach ($r in $noSearch) { [void]$sb.AppendLine("- ``apps/$($r.App)``") } } else { [void]$sb.AppendLine('- нет') }
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## Модули без явного пустого состояния (со списками)')
[void]$sb.AppendLine('')
if ($noEmpty.Count) { foreach ($r in $noEmpty) { [void]$sb.AppendLine("- ``apps/$($r.App)``") } } else { [void]$sb.AppendLine('- нет') }
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## Полная таблица')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('| Модуль | Список | Поиск | Пустое состояние |')
[void]$sb.AppendLine('|---|---|---|---|')
foreach ($r in $rows) { [void]$sb.AppendLine("| $($r.App) | " + ($(if($r.List){'да'}else{'—'})) + ' | ' + ($(if($r.Search){'да'}else{'**нет**'})) + ' | ' + ($(if($r.Empty){'да'}else{'**нет**'})) + ' |') }

[System.IO.File]::WriteAllText($out, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
Write-Host ("ux-check: модулей {0}, со списками {1}, без поиска {2}, без пустого состояния {3} -> docs/UX_REPORT.md" -f $rows.Count, $withList.Count, $noSearch.Count, $noEmpty.Count)
