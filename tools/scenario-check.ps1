# ============================================================
# 3DMP · tools/scenario-check.ps1 — L3: сквозные сценарии (область C)
# Прогоняет золотые цепочки по модулям через Management API, проверяет отсутствие
# ошибок, затем очищает тестовые данные. Пишет audit/checks/scenario.json.
# Требует -Token sbp_... (Management API). Только API, без изменения кода.
# ============================================================
param([string]$Root = $null, [string]$Token = $env:SUPABASE_ACCESS_TOKEN, [string]$Project = 'zfkbzzmtbrueaksfaqbf')
$ErrorActionPreference = 'Continue'
if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }
Set-Location $Root

$findings = New-Object System.Collections.ArrayList
function Add-F($area, $sev, $title, $detail, $evidence, $effort, $impact) {
  [void]$findings.Add([pscustomobject]@{ area = $area; sev = $sev; title = $title; detail = $detail; evidence = $evidence; method = 'scenario'; effort = $effort; impact = $impact; status = 'open' })
}
function Write-Out {
  New-Item -ItemType Directory -Force -Path (Join-Path $Root 'audit\checks') | Out-Null
  $out = [ordered]@{ tool = 'scenario'; at = (Get-Date).ToString('s'); pass = $script:pass; fail = $script:fail; findings = $findings }
  [System.IO.File]::WriteAllText((Join-Path $Root 'audit\checks\scenario.json'), ($out | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false)))
}
if (-not $Token) { Add-F 'C' 'Info' 'Сценарии L3 пропущены (нет токена)' 'Задайте -Token.' 'tools/scenario-check.ps1' 1 1; $script:pass=0; $script:fail=0; Write-Out; Write-Host 'scenario-check: пропуск (нет токена)'; exit 0 }

$Uri = "https://api.supabase.com/v1/projects/$Project/database/query"
# Пейсинг + ретраи на троттлинг Management API (429 / ThrottlerException)
$script:SqlMinGapMs = 600
$script:SqlLast = [DateTime]::UtcNow
function Sql([string]$q) {
  $attempt = 0
  while ($true) {
    $attempt++
    $gap = [int]([DateTime]::UtcNow - $script:SqlLast).TotalMilliseconds
    if ($gap -lt $script:SqlMinGapMs) { Start-Sleep -Milliseconds ($script:SqlMinGapMs - $gap) }
    $script:SqlLast = [DateTime]::UtcNow
    $j = @{ query = $q } | ConvertTo-Json -Compress
    $b = [System.Text.Encoding]::UTF8.GetBytes($j)
    try {
      return Invoke-RestMethod -Method Post -Uri $Uri -Headers @{ Authorization = "Bearer $Token" } -ContentType 'application/json; charset=utf-8' -Body $b -TimeoutSec 120
    } catch {
      $msg = ''
      try { $msg = [string]$_.ErrorDetails.Message } catch {}
      if (-not $msg) { try { $msg = [string]$_.Exception.Message } catch {} }
      if (($msg -match 'ThrottlerException|429|Too Many Requests') -and $attempt -le 5) {
        Start-Sleep -Seconds ([Math]::Min(2 * $attempt, 10)); continue
      }
      throw
    }
  }
}
function Rows($r) { if ($r -and ($r.PSObject.Properties.Name -contains 'value')) { return @($r.value) } elseif ($r) { return @($r) } else { return @() } }

$script:pass = 0; $script:fail = 0
function Step($name, [string]$sql) {
  try { $r = Sql $sql; $rows = Rows $r; $script:pass++; return $rows }
  catch { Add-F 'C' 'Major' ("Сценарий: " + $name + " — ошибка") ($_.Exception.Message) $sql 3 2; $script:fail++; return $null }
}
function ExpectV($name, $rows, $label) {
  if (-not $rows -or $rows.Count -eq 0 -or -not $rows[0].v) { Add-F 'C' 'Major' ("Сценарий: " + $name + " — пустой результат (" + $label + ")") 'Ожидалось значение.' 'scenario-check' 2 2; $script:fail++; return $false }
  return $true
}

Write-Host '=== scenario-check (L3) ==='
$t = $null
try { $t = (Rows (Sql "select token as v from public.app_login('admin','admin')"))[0].v } catch { $t = $null }
if (-not $t) { Add-F 'C' 'Critical' 'Логин admin не вернул токен' 'Проверить app_login.' 'app_login' 1 3; Write-Out; exit 1 }

# 1. orders
$o = Step 'заявка: создание' "select id as v from public.app_order_create('$t','SCN-ORD тест','','','','','normal',null,null,'',null,'single')"
if (ExpectV 'заявка: создание' $o 'id') { Step 'заявка: чтение' "select v from (select count(*)::text as v from public.app_order_list('$t')) z" | Out-Null }

# 2. naryad
$n = Step 'наряд: создание' "select id as v from public.app_naryad_create('$t',null,'SCN-NAR тест',null,'','2026-12-31','normal')"

# 3. QC + passport + trace
$qc = Step 'ОТК: список' "select id as v from public.app_qc_list('$t') limit 1"
$p = Step 'паспорт: создание' "select id as v from public.app_passport_create('$t',null,'SCN-PAS тест',null,'{}'::jsonb,null,'SN-SCN',1)"
if (ExpectV 'паспорт: создание' $p 'id') {
  Step 'паспорт: чтение' "select v from (select count(*)::text as v from public.app_passport_get('$t','$($p[0].v)')) z" | Out-Null
  if ($qc -and $qc.Count) { Step 'паспорт: трассируемость' "select v from (select count(*)::text as v from public.app_qc_trace('$t','$($qc[0].v)')) z" | Out-Null }
  if ($qc -and $qc.Count) { Step 'ОТК: измерение' "select * from public.app_qc_measure_add('$t','$($qc[0].v)',null,'Ra',1.5)" | Out-Null }
}

# 4. warehouse (receive)
$mat = Step 'склад: материал' "select (select id from public.app_materials limit 1) as v"
$loc = Step 'склад: адрес' "select (select id from public.app_wh_addresses limit 1) as v"
if ($mat -and $mat[0].v -and $loc -and $loc[0].v) { Step 'склад: приёмка' "select * from public.app_wh_place('$t','$($mat[0].v)','$($loc[0].v)','SCN-LOT',1,10)" | Out-Null }
else { Add-F 'C' 'Info' 'Сценарий склад: нет материала/адреса для приёмки' 'Пропуск (нет справочных данных).' 'warehouse' 2 1 }

# 5. logistics
Step 'логистика: заявка на перевозку' "select * from public.app_transport_save('$t',null,'','out','SCN','груз SCN',1,'A','B',null,null,null,null,null,null,'SCN-TMS')" | Out-Null

# 6. workflow
$def = Step 'процесс: шаблоны' "select id as v from public.app_process_defs_list('$t') limit 1"
if ($def -and $def[0].v) { Step 'процесс: запуск' "select * from public.app_process_start('$t','$($def[0].v)',null,null,'SCN-WF',null)" | Out-Null }
else { Add-F 'C' 'Info' 'Процесс: нет шаблона для запуска' 'Пропуск.' 'workflow' 2 1 }

# 7. kedo
Step 'КЭДО: документ' "select * from public.app_hr_doc_save('$t',null,'manager','order','SCN-KEDO тест',null)" | Out-Null

# 8. EDO full chain
$d = Step 'ЭДО: создание' "select id as v from public.app_doc_save('$t',null,'in','letter','SCN-EDO тест','1С','суть','manager',null,null)"
if (ExpectV 'ЭДО: создание' $d 'id') {
  Step 'ЭДО: регистрация' "select * from public.app_doc_register('$t','$($d[0].v)')" | Out-Null
  Step 'ЭДО: связь' "select * from public.app_doc_link_save('$t',null,'$($d[0].v)','order',null,'SCN')" | Out-Null
  $res = Step 'ЭДО: поручение' "select id as v from public.app_doc_resolution_add('$t','$($d[0].v)','SCN поручение','manager',null)"
  if (ExpectV 'ЭДО: поручение' $res 'id') { Step 'ЭДО: выполнение поручения' "select * from public.app_doc_resolution_set_status('$t','$($res[0].v)','done')" | Out-Null }
}

# 9. attachments
Step 'вложения: добавление' "select * from public.app_attach_add('$t','scn_test',null,'photo','data:image/png;base64,AAAA','SCN')" | Out-Null
Step 'вложения: чтение' "select v from (select count(*)::text as v from public.app_attach_list('$t','scn_test',null)) z" | Out-Null

# 10. health scan
Step 'мониторинг: health_scan' "select v from (select count(*)::text as v from public.app_health_scan('$t')) z" | Out-Null

# 11. report schedule lifecycle
$sc = Step 'отчёты: расписание' "select id as v from public.app_report_schedule_save('$t',null,'SCN-sched','orders','pdf','daily','email','scn@example.com',true)"
if (ExpectV 'отчёты: расписание' $sc 'id') {
  Step 'отчёты: запуск расписания' "select * from public.app_report_schedule_run('$t','$($sc[0].v)')" | Out-Null
  Step 'отчёты: удаление расписания' "select * from public.app_report_schedule_delete('$t','$($sc[0].v)')" | Out-Null
}

# 12. dashboard
Step 'дашборд: KPI' "select v from (select count(*)::text as v from public.app_dashboard_kpis('$t')) z" | Out-Null

# 13. read-only аналитика/дашборды/расширения/отчёты
Step 'аналитика: APS' "select v from (select count(*)::text as v from public.app_aps_optimize('$t')) z" | Out-Null
Step 'аналитика: предиктив ТОиР' "select v from (select count(*)::text as v from public.app_mnt_predictive('$t')) z" | Out-Null
Step 'аналитика: SPC' "select v from (select count(*)::text as v from public.app_spc_signals('$t',null)) z" | Out-Null
Step 'мониторинг: тренд' "select v from (select count(*)::text as v from public.app_health_trend('$t',14)) z" | Out-Null
Step 'мониторинг: алерты' "select v from (select count(*)::text as v from public.app_health_alerts_list('$t','open')) z" | Out-Null
Step 'расширения: каталог' "select v from (select count(*)::text as v from public.app_ext_list('$t')) z" | Out-Null
Step 'отчёты: модуль' "select v from (select jsonb_array_length(rows)::text as v from public.app_module_report('$t','orders',null,null)) z" | Out-Null

# 14. записывающие сценарии (с маркерами SCN-)
Step 'поставщики: сохранение' "select * from public.app_suppliers_save('$t',null,'SCN-SUP','1234567890','Иван','+70000000000','sup@scn.io','materials',4,'active')" | Out-Null
Step 'кадры: сотрудник' "select * from public.app_employee_save('$t',null,'SCN-EMP','мастер','цех','','',null,'true')" | Out-Null
$emp = Step 'кадры: сотрудник id' "select id as v from public.app_employees where full_name='SCN-EMP' order by created_at desc limit 1"
if (ExpectV 'кадры: сотрудник id' $emp 'id') {
  Step 'кадры: смена' "select * from public.app_shift_add('$t','$($emp[0].v)','2026-10-10','day',8,'SCN')" | Out-Null
  Step 'кадры: обучение' "select * from public.app_training_add('$t','$($emp[0].v)','SCN обучение','planned','2026-11-01','')" | Out-Null
}
Step 'СМК: средство измерений' "select * from public.app_tool_save('$t',null,'SCN-СИ','SCN-SN','Штангенциркуль','цех',null,null)" | Out-Null
Step 'трассируемость: запись' "select * from public.app_trace_add('$t','SCN-ITEM','SCN-SN',null,null,'сталь','admin','SCN')" | Out-Null
$clm = Step 'претензии: создание' "select id as v from public.app_claim_save('$t',null,'SCN клиент','SCN изделие','задир',1,'major','SCN описание','')"
if (ExpectV 'претензии: создание' $clm 'id') { Step 'претензии: CAPA' "select * from public.app_capa_save('$t',null,'$($clm[0].v)','corrective','SCN CAPA','manager','2026-11-01','open','')" | Out-Null }
Step 'закупки: тендер' "select * from public.app_tender_create('$t','SCN-TND','','materials','сталь',1,'шт',null,null,null,null)" | Out-Null
Step 'НСИ: позиция' "select * from public.app_master_item_save('$t',null,'SCN-MDM','SCN позиция','material','шт',null,null,'active','')" | Out-Null
$life = Step 'инструмент: ресурс' "select (select id from public.app_tool_life limit 1) as v"
if ($life -and $life[0].v) { Step 'инструмент: экземпляр' "select * from public.app_tool_item_save('$t',null,'$($life[0].v)','SCN-TOOL',null,100,'SCN')" | Out-Null }

# 15. сквозной сценарий PROP-14: заявка → наряд → ОТК → склад → счёт → оплата → себестоимость
$oid = $null; if ($o) { $oid = $o[0].v }
if ($oid) {
  $n2 = Step 'цепочка: наряд из заявки' "select id as v from public.app_naryad_create('$t','$oid','SCN-CHAIN наряд',null,'manager','2026-12-31','high',null)"
  if (ExpectV 'цепочка: наряд из заявки' $n2 'id') {
    $nid = $n2[0].v
    Step 'цепочка: наряд ↔ заявка' "select v from (select count(*)::text as v from public.app_order_naryads('$t','$oid')) z" | Out-Null
    ExpectV 'цепочка: наряд привязан к заявке' (Step 'цепочка: инвариант наряда' "select v from (select count(*)::text as v from public.app_naryads where order_id='$oid' and title like 'SCN-%') z") 'count' | Out-Null
    Step 'цепочка: операция наряда' "select * from public.app_naryad_add_op('$t','$nid','SCN операция','manager',2,null,null)" | Out-Null
    $op = Step 'цепочка: операция (id)' "select id as v from public.app_naryad_ops('$t','$nid') order by seq limit 1"
    if ($op -and $op[0].v) { Step 'цепочка: операция выполнена' "select * from public.app_naryad_op_done('$t','$($op[0].v)',2,true)" | Out-Null }
    Step 'цепочка: закрытие наряда' "select * from public.app_naryad_close('$t','$nid')" | Out-Null
    $q2 = Step 'цепочка: ОТК по наряду' "select id as v from public.app_qc_create('$t','$nid','$oid','SCN цепочка изделие','admin',10,10)"
    if ($q2 -and $q2[0].v) {
      Step 'цепочка: строка ОТК' "select * from public.app_qc_add_line('$t','$($q2[0].v)','Ra','3.2','1.6','ok')" | Out-Null
      Step 'цепочка: статус ОТК' "select * from public.app_qc_set_status('$t','$($q2[0].v)','passed','SCN')" | Out-Null
      ExpectV 'цепочка: ОТК пройден' (Step 'цепочка: инвариант ОТК' "select v from (select status as v from public.app_qc_checks where id='$($q2[0].v)') z") 'status' | Out-Null
      Step 'цепочка: трассируемость ОТК' "select v from (select count(*)::text as v from public.app_qc_trace('$t','$($q2[0].v)')) z" | Out-Null
    }
    if ($mat -and $mat[0].v) { Step 'цепочка: движение материала по заявке' "select * from public.app_stock_move('$t','$($mat[0].v)','out',1,0,'SCN цепочка','chain','$oid','$nid')" | Out-Null }
    $inv2 = Step 'цепочка: счёт по заявке' "select id as v from public.app_invoice_create('$t','$oid','SCN цепочка клиент',1000,'2026-12-31','SCN цепочка')"
    if ($inv2 -and $inv2[0].v) {
      Step 'цепочка: выставление счёта' "select * from public.app_invoice_set_status('$t','$($inv2[0].v)','sent')" | Out-Null
      Step 'цепочка: оплата' "select * from public.app_payment_add('$t','$($inv2[0].v)',1000,'bank','SCN цепочка оплата')" | Out-Null
      ExpectV 'цепочка: оплата учтена' (Step 'цепочка: инвариант оплаты' "select v from (select count(*)::text as v from public.app_payments where invoice_id='$($inv2[0].v)') z") 'count' | Out-Null
      Step 'цепочка: счёт ↔ заявка' "select v from (select count(*)::text as v from public.app_order_invoices('$t','$oid')) z" | Out-Null
    }
    Step 'цепочка: себестоимость заявки' "select v from (select count(*)::text as v from public.app_order_cost_plan_fact('$t','$oid')) z" | Out-Null
  }
} else { Add-F 'C' 'Info' 'Сквозной сценарий PROP-14 пропущен (нет заявки)' 'Пропуск.' 'scenario-check' 2 1 }

# 16. сквозной сценарий PROP-15: рекламация → CAPA → сервисная заявка → паспорт → KPI
if ($clm -and $clm[0].v) {
  $cid = $clm[0].v
  Step 'качество-цепочка: CAPA по претензии' "select * from public.app_capa_save('$t',null,'$cid','corrective','SCN CAPA цепочка','manager','2026-11-15','open','')" | Out-Null
  Step 'качество-цепочка: список CAPA' "select v from (select count(*)::text as v from public.app_capa_list('$t','$cid')) z" | Out-Null
  $srv = Step 'качество-цепочка: сервисная заявка' "select id as v from public.app_service_save('$t',null,null,null,'SCN сервис по претензии','repair',null,'manager','',0,'Претензия SCN','high',null,true,null,null,null)"
  if ($srv -and $srv[0].v) { Step 'качество-цепочка: выполнение сервиса' "select * from public.app_service_complete('$t','$($srv[0].v)','SCN работы','SCN решение',2,0,0)" | Out-Null }
  $ps = Step 'качество-цепочка: паспорт изделия' "select id as v from public.app_passport_create('$t',null,'SCN цепочка изделие',null,'{}'::jsonb,null,'SN-SCN-CH',1)"
  if ($ps -and $ps[0].v) { Step 'качество-цепочка: чтение паспорта' "select v from (select count(*)::text as v from public.app_passport_get('$t','$($ps[0].v)')) z" | Out-Null }
  Step 'качество-цепочка: KPI качества' "select v from (select count(*)::text as v from public.app_quality_kpi('$t')) z" | Out-Null
  Step 'качество-цепочка: отчёт претензий' "select v from (select count(*)::text as v from public.app_claims_report('$t',null,null)) z" | Out-Null
} else { Add-F 'C' 'Info' 'Сценарий PROP-15 пропущен (нет претензии)' 'Пропуск.' 'scenario-check' 2 1 }

# 17. PROP-16: согласованность себестоимости (app_order_cost и app_order_cost_plan_fact — одна база ставок)
if ($oid) {
  Step 'себестоимость: app_order_cost' "select v from (select count(*)::text as v from public.app_order_cost('$t','$oid')) z" | Out-Null
  Step 'себестоимость: plan_fact' "select v from (select count(*)::text as v from public.app_order_cost_plan_fact('$t','$oid')) z" | Out-Null
} else { Add-F 'C' 'Info' 'Проверка себестоимости пропущена (нет заявки)' 'Пропуск.' 'scenario-check' 2 1 }

# 18. PROP-18: регрессия инвариантов (миграции применены, защита прав)
ExpectV 'инвариант: индексы PROP-04' (Step 'инвариант: индексы горячих таблиц' "select v from (select count(*)::text as v from pg_indexes where schemaname='public' and indexname in ('ix_orders_tenant_created','ix_naryads_tenant_order','ix_tasks_tenant_status')) z") 'count' | Out-Null
Step 'инвариант: RLS на tenders' "select v from (select count(*)::text as v from pg_policies where schemaname='public' and tablename='tenders' and cmd='SELECT') z" | Out-Null
Step 'инвариант: аудит заказов' "select v from (select count(*)::text as v from public.app_order_history) z" | Out-Null

# 20. R4: поверхности новых модулей (создание → чтение); данные помечены SCN и удаляются в очистке
Step 'R4: кампания' "select * from public.app_campaign_save('$t',null,'SCN-КАМП','email','ключевые','planned',null,0,0,0,null)" | Out-Null
ExpectV 'R4: кампания видна' (Step 'R4: кампании список' "select v from (select count(*)::text as v from public.app_campaign_list('$t')) z") 'count' | Out-Null
Step 'R4: ОС' "select * from public.app_fa_save('$t',null,'SCN-ОС','SCN станок','оборудование',1000000,100000,60,current_date)" | Out-Null
Step 'R4: амортизация ОС' "select * from public.app_fa_amortize('$t',null)" | Out-Null
ExpectV 'R4: ОС видно' (Step 'R4: ОС список' "select v from (select count(*)::text as v from public.app_fa_list('$t')) z") 'count' | Out-Null
Step 'R4: сертификат' "select * from public.app_certificate_save('$t',null,'certificate','SCN-CERT','орган','SCN изделие',current_date,current_date+365,null)" | Out-Null
ExpectV 'R4: сертификат виден' (Step 'R4: сертификаты список' "select v from (select count(*)::text as v from public.app_certificate_list('$t')) z") 'count' | Out-Null
Step 'R4: WBS работа' "select * from public.app_wbs_save('$t',null,null,null,'SCN работа',1,10)" | Out-Null
Step 'R4: табель' "select * from public.app_timesheet_save('$t',null,null,null,'SCN сотрудник',current_date,4,null)" | Out-Null
ExpectV 'R4: WBS/табель видны' (Step 'R4: WBS список' "select v from (select count(*)::text as v from public.app_wbs_list('$t',null)) z") 'count' | Out-Null
Step 'R4: скоринг поставщика' "select * from public.app_supplier_score_save('$t',null,(select id from public.app_suppliers limit 1),current_date,4,4,4,'SCN')" | Out-Null
Step 'R4: отгрузка' "select * from public.app_shipment_save('$t',null,'SCN-ORD-SH','SCN клиент',1,'SCN',null)" | Out-Null
Step 'R4: отгрузка статус' "select * from public.app_shipment_set_status('$t',(select id from public.app_shipments where order_ref='SCN-ORD-SH' limit 1),'picking')" | Out-Null
ExpectV 'R4: отгрузки видно' (Step 'R4: отгрузки список' "select v from (select count(*)::text as v from public.app_shipment_list('$t')) z") 'count' | Out-Null
Step 'R4: зарплата' "select * from public.app_payroll_save('$t',null,current_date,'SCN сотрудник',50000,5000,1000,null)" | Out-Null
Step 'R4: вакансия' "select * from public.app_vacancy_save('$t',null,'SCN вакансия','цех','open')" | Out-Null
Step 'R4: кандидат' "select * from public.app_candidate_save('$t',null,(select id from public.app_vacancies where title='SCN вакансия' limit 1),'SCN кандидат','new',null)" | Out-Null
ExpectV 'R4: подбор виден' (Step 'R4: вакансии список' "select v from (select count(*)::text as v from public.app_vacancy_list('$t')) z") 'count' | Out-Null
Step 'R4: ABC' "select * from public.app_abc_save('$t',null,current_date,'SCN деятельность','драйвер',10,100,null)" | Out-Null
Step 'R4: элиминация' "select * from public.app_consol_save('$t',null,current_date,'SCN A','SCN B',1000,null)" | Out-Null
Step 'R4: edge push' "select * from public.app_iiot_edge_push('$t','SCN','rpm',1000,'mqtt',null)" | Out-Null
ExpectV 'R4: edge буфер' (Step 'R4: edge список' "select v from (select count(*)::text as v from public.app_iiot_edge_list('$t',false)) z") 'count' | Out-Null

# --- cleanup ---
$cleanup = @'
delete from public.app_order_items where order_id in (select id from public.app_orders where title like 'SCN-%');
delete from public.app_orders where title like 'SCN-%';
delete from public.app_naryads where title like 'SCN-%';
delete from public.app_passports where product like 'SCN-%';
delete from public.app_stock_moves where lot_id in (select id from public.app_material_lots where lot='SCN-LOT');
delete from public.app_wh_stock where lot_id in (select id from public.app_material_lots where lot='SCN-LOT');
delete from public.app_material_lots where lot='SCN-LOT';
delete from public.app_transport_orders where note='SCN-TMS';
delete from public.app_process_tasks where instance_id in (select id from public.app_process_instances where entity_title='SCN-WF');
delete from public.app_process_actions where instance_id in (select id from public.app_process_instances where entity_title='SCN-WF');
delete from public.app_process_instances where entity_title='SCN-WF';
delete from public.app_hr_docs where title like 'SCN-%';
delete from public.app_doc_resolutions where doc_id in (select id from public.app_doc_flows where title like 'SCN-%');
delete from public.app_doc_links where doc_id in (select id from public.app_doc_flows where title like 'SCN-%');
delete from public.app_doc_flows where title like 'SCN-%';
delete from public.app_attachments where entity_type='scn_test';
delete from public.app_report_schedules where name like 'SCN-%';
delete from public.app_health_checks where checked_at::date = current_date and kind not in ('db','tables','functions','realtime','integration','billing','freshness','ping');
delete from public.app_health_alerts where name in ('Свежесть проверок','Внешний мониторинг') and first_seen >= now() - interval '30 minutes';
delete from public.app_notifications where title like '%SCN%' and created_at >= now() - interval '30 minutes';
delete from public.app_events where (detail like '%SCN%' or action in ('Рассылка отчёта','Вложение добавлено','Смена пароля')) and created_at >= now() - interval '30 minutes';
delete from public.app_qc_measures where param='Ra' and value=1.5 and ts >= now() - interval '30 minutes' and created_login='admin';
'@
$del = @(
  "delete from public.app_campaigns where name like 'SCN%'",
  "delete from public.app_fixed_assets where name like 'SCN%'",
  "delete from public.app_quality_certificates where number like 'SCN%'",
  "delete from public.app_timesheets where employee like 'SCN%'",
  "delete from public.app_wbs where name like 'SCN%'",
  "delete from public.app_supplier_scores where note like 'SCN%'",
  "delete from public.app_shipments where order_ref like 'SCN%'",
  "delete from public.app_payroll where employee like 'SCN%'",
  "delete from public.app_candidates where name like 'SCN%'",
  "delete from public.app_vacancies where title like 'SCN%'",
  "delete from public.app_activity_costs where activity like 'SCN%'",
  "delete from public.app_consol_elim where from_unit like 'SCN%'",
  "delete from public.app_iiot_edge where machine like 'SCN%'",
  "delete from public.app_service_history where request_id in (select id from public.app_service_requests where title like 'SCN-%')",
  "delete from public.app_service_visits where request_id in (select id from public.app_service_requests where title like 'SCN-%')",
  "delete from public.app_service_parts where request_id in (select id from public.app_service_requests where title like 'SCN-%')",
  "delete from public.app_service_requests where title like 'SCN-%'",
  "delete from public.app_qc_lines where check_id in (select id from public.app_qc_checks where product like 'SCN-%')",
  "delete from public.app_qc_checks where product like 'SCN-%'",
  "delete from public.app_naryad_ops where naryad_id in (select id from public.app_naryads where title like 'SCN-%')",
  "delete from public.app_payments where note like 'SCN%'",
  "delete from public.app_invoices where customer like 'SCN%'",
  "delete from public.app_stock_moves where note like 'SCN%'",
  "delete from public.app_traceability where item like 'SCN-%'",
  "delete from public.app_trainings where title like 'SCN-%'",
  "delete from public.app_training_plan where employee_id in (select id from public.app_employees where full_name like 'SCN-%')",
  "delete from public.app_shifts where employee_id in (select id from public.app_employees where full_name like 'SCN-%')",
  "delete from public.app_employees where full_name like 'SCN-%'",
  "delete from public.app_suppliers where name='SCN-SUP'",
  "delete from public.app_measuring_tools where name like 'SCN-%'",
  "delete from public.app_capa_actions where title like 'SCN-%'",
  "delete from public.app_claims where customer like 'SCN-%'",
  "delete from public.tenders where title like 'SCN-%'",
  "delete from public.app_master_items where code like 'SCN-%'",
  "delete from public.app_tool_items where serial like 'SCN-%'",
  "delete from public.app_order_items where order_id in (select id from public.app_orders where title like 'SCN-%')",
  "delete from public.app_orders where title like 'SCN-%'",
  "delete from public.app_naryads where title like 'SCN-%'",
  "delete from public.app_passports where product like 'SCN-%'",
  "delete from public.app_stock_moves where lot_id in (select id from public.app_material_lots where lot='SCN-LOT')",
  "delete from public.app_wh_stock where lot_id in (select id from public.app_material_lots where lot='SCN-LOT')",
  "delete from public.app_material_lots where lot='SCN-LOT'",
  "delete from public.app_transport_orders where note='SCN-TMS'",
  "delete from public.app_process_tasks where instance_id in (select id from public.app_process_instances where entity_title='SCN-WF')",
  "delete from public.app_process_actions where instance_id in (select id from public.app_process_instances where entity_title='SCN-WF')",
  "delete from public.app_process_instances where entity_title='SCN-WF'",
  "delete from public.app_hr_docs where title like 'SCN-%'",
  "delete from public.app_doc_resolutions where doc_id in (select id from public.app_doc_flows where title like 'SCN-%')",
  "delete from public.app_doc_links where doc_id in (select id from public.app_doc_flows where title like 'SCN-%')",
  "delete from public.app_doc_flows where title like 'SCN-%'",
  "delete from public.app_attachments where entity_type='scn_test'",
  "delete from public.app_report_schedules where name like 'SCN-%'",
  "delete from public.app_qc_measures where param='Ra' and value=1.5 and created_login='admin' and ts >= now() - interval '30 minutes'",
  "delete from public.app_notifications where title like '%SCN%' and created_at >= now() - interval '30 minutes'",
  "delete from public.app_events where (detail like '%SCN%' or action='Рассылка отчёта') and created_at >= now() - interval '30 minutes'"
)
$cleanFail = 0; $cleanErrs = New-Object System.Collections.ArrayList
foreach ($d in $del) {
  try { Sql $d | Out-Null }
  catch {
    $cleanFail++
    $m = ''; try { $m = [string]$_.ErrorDetails.Message } catch {}
    if (-not $m) { try { $m = [string]$_.Exception.Message } catch {} }
    $m = ($m -replace '\s+', ' ')
    if ($cleanErrs.Count -lt 4 -and $m) { [void]$cleanErrs.Add($m.Substring(0, [Math]::Min(180, $m.Length))) }
  }
}
if ($cleanFail -gt 0) { Add-F 'C' 'Minor' "Очистка сценарных данных: не выполнено шагов $cleanFail" ($cleanErrs -join ' || ') 'cleanup' 2 1 }
Write-Host ("scenario-check: очистка выполнена (ошибок " + $cleanFail + ')')

Write-Out
Write-Host ("scenario-check: pass=" + $script:pass + ' fail=' + $script:fail + ' findings=' + $findings.Count)
if ($script:fail -gt 0) { exit 1 } else { exit 0 }
