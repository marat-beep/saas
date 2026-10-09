# ============================================================
# 3DMP Service · tools/db-smoke.ps1 — смоук-тесты БД (W12)
# Запускает app_smoke_test (10) и app_smoke_test_ext (14) через Management API.
# Токен sbp_… задаётся параметром, переменной окружения SUPABASE_ACCESS_TOKEN
# или вводится вручную. Токен не сохраняется.
# Запуск: powershell -ExecutionPolicy Bypass -File tools\db-smoke.ps1 -Token sbp_...
# ============================================================
param(
  [string]$Token = $env:SUPABASE_ACCESS_TOKEN,
  [string]$Project = 'zfkbzzmtbrueaksfaqbf'
)
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Token)) { $Token = Read-Host 'Введите Management-токен (sbp_...)' }

function Sql([string]$q) {
  $json = @{ query = $q } | ConvertTo-Json -Compress
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
  try {
    return Invoke-RestMethod -Method Post -Uri "https://api.supabase.com/v1/projects/$Project/database/query" `
      -Headers @{ Authorization = "Bearer $Token" } -ContentType 'application/json; charset=utf-8' -Body $bytes -TimeoutSec 120
  } catch {
    Write-Host ("Ошибка SQL: " + $_.Exception.Message) -ForegroundColor Red
    if ($_.ErrorDetails) { Write-Host $_.ErrorDetails.Message }
    throw
  }
}
function Val($r) { if ($r.token) { return $r.token }; if ($r.value) { return (@($r.value)[0]) }; return $null }

$admin = Val (Sql "select token from public.app_login('admin','admin')")
if (-not $admin) { Write-Host 'Не удалось войти admin/admin' -ForegroundColor Red; exit 1 }

$s1 = Sql "select count(*) as total, count(*) filter (where ok) as ok from public.app_smoke_test('$admin')"
$s2 = Sql "select count(*) as total, count(*) filter (where ok) as ok from public.app_smoke_test_ext('$admin')"
function Row($r) { if ($r.value) { return (@($r.value)[0]) }; return $r }
$r1 = Row $s1; $r2 = Row $s2

Write-Host ("app_smoke_test:     {0}/{1}" -f $r1.ok, $r1.total)
Write-Host ("app_smoke_test_ext: {0}/{1}" -f $r2.ok, $r2.total)

# Проверка кодировки: в ответах БЗ и описаниях тарифов не должно быть символа '?' (признак потери текста)
$enc = Row (Sql "select (select count(*) from public.app_knowledge where answer like '%?%') as answers_q, (select count(*) from public.app_plans where description like '%?%') as plans_q")
Write-Host ("Кодировка ('?' в текстах): ответы БЗ={0}, тарифы={1}" -f $enc.answers_q, $enc.plans_q)

# Дымовые проверки ключевых RPC волн W7–R4 (только чтение; ошибка = провал)
$waveChecks = @(
  @{ n = 'billing_plans';    q = "select count(*) as n from public.app_billing_plans('$admin')" },
  @{ n = 'subscriptions';    q = "select count(*) as n from public.app_subscriptions_list('$admin')" },
  @{ n = 'health_board';     q = "select count(*) as n from public.app_health_board('$admin')" },
  @{ n = 'report_defs';      q = "select count(*) as n from public.app_report_defs_list('$admin')" },
  @{ n = 'forecast_demand';  q = "select count(*) as n from public.app_forecast_demand('$admin', 3)" },
  @{ n = 'aps_plan';         q = "select count(*) as n from public.app_aps_plan('$admin', current_date, 3)" },
  @{ n = 'iiot_connectors';  q = "select count(*) as n from public.app_iiot_connectors_list('$admin')" },
  @{ n = 'oee_online';       q = "select count(*) as n from public.app_oee_online('$admin')" },
  @{ n = 'tool_wear';        q = "select count(*) as n from public.app_tool_wear_scan('$admin', 5)" },
  @{ n = 'perm_sets';        q = "select count(*) as n from public.app_perm_sets_list('$admin')" },
  @{ n = 'approval_routes';  q = "select count(*) as n from public.app_approval_routes_list('$admin')" },
  @{ n = 'audit_kpi';        q = "select count(*) as n from public.app_audit_kpi('$admin')" },
  @{ n = 'ai_kpi';           q = "select count(*) as n from public.app_ai_kpi('$admin')" },
  @{ n = 'crm_reminders';    q = "select count(*) as n from public.app_crm_reminders_list('$admin', null)" },
  @{ n = 'lot_list';         q = "select count(*) as n from public.app_lot_list('$admin', null)" },
  @{ n = 'dept_scope';       q = "select public.app_dept_scope_get('$admin') as n" },
  @{ n = 'my_department';    q = "select count(*) as n from public.app_my_department('$admin')" },
  @{ n = 'tool_items';       q = "select count(*) as n from public.app_tool_items_kpi('$admin')" },
  @{ n = 'tool_catalog';     q = "select count(*) as n from public.app_tool_catalog_list('$admin', null, null)" },
  @{ n = 'crm_reminders2';   q = "select count(*) as n from public.app_crm_reminders_list('$admin', null)" },
  @{ n = 'lot_list';         q = "select count(*) as n from public.app_lot_list('$admin', null)" },
  @{ n = 'dept_scope';       q = "select public.app_dept_scope_get('$admin') as n" },
  @{ n = 'workflow_defs';    q = "select count(*) as n from public.app_process_defs_list('$admin')" },
  @{ n = 'workflow_my';      q = "select count(*) as n from public.app_process_my('$admin')" },
  @{ n = 'workflow_rules';   q = "select count(*) as n from public.app_rules_list('$admin')" },
  @{ n = 'workflow_forms';   q = "select count(*) as n from public.app_form_defs_list('$admin')" },
  @{ n = 'mdm_kpi';          q = "select count(*) as n from public.app_mdm_kpi('$admin')" },
  @{ n = 'plm_kpi';          q = "select count(*) as n from public.app_plm_kpi('$admin')" },
  @{ n = 'edo_list';         q = "select count(*) as n from public.app_doc_flow_list('$admin', null, null, null)" },
  @{ n = 'collab_kpi';       q = "select count(*) as n from public.app_collab_kpi('$admin')" },
  @{ n = 'kedo_kpi';         q = "select count(*) as n from public.app_kedo_kpi('$admin')" },
  @{ n = 'eam_kpi';          q = "select count(*) as n from public.app_eam_kpi('$admin')" },
  @{ n = 'ehs_kpi';          q = "select count(*) as n from public.app_ehs_kpi('$admin')" },
  @{ n = 'holding_kpi';      q = "select count(*) as n from public.app_holding_kpi('$admin')" },
  @{ n = 'projbudget_kpi';   q = "select count(*) as n from public.app_proj_budget_kpi('$admin')" },
  @{ n = 'pmo_kpi';          q = "select count(*) as n from public.app_pmo_kpi('$admin')" },
  @{ n = 'tms_kpi';          q = "select count(*) as n from public.app_tms_kpi('$admin')" },
  @{ n = 'itsm_kpi';         q = "select count(*) as n from public.app_itsm_kpi('$admin')" },
  @{ n = 'elearning_kpi';    q = "select count(*) as n from public.app_elearning_kpi('$admin')" },
  @{ n = 'accounting_kpi';   q = "select count(*) as n from public.app_accounting_kpi('$admin')" },
  @{ n = 'finance_budgets';  q = "select count(*) as n from public.app_budgets_list('$admin')" },
  @{ n = 'finance_cash';     q = "select count(*) as n from public.app_cash_kpi('$admin')" },
  @{ n = 'kb_articles';      q = "select count(*) as n from public.app_kb_articles('$admin', null, null)" },
  @{ n = 'overloads';        q = "select count(*) as n from (select proname from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace where ns.nspname='public' group by proname having count(*)>1) x" }
)
$waveFail = @()
foreach ($c in $waveChecks) {
  try { Sql $c.q | Out-Null } catch { $waveFail += $c.n }
}
Write-Host ("Волновые RPC: {0}/{1} ок{2}" -f ($waveChecks.Count - $waveFail.Count), $waveChecks.Count, $(if ($waveFail.Count) { ' [' + ($waveFail -join ', ') + ']' } else { '' }))

# Перегрузки функций (должно быть 0)
$ovl = Row (Sql "select count(*) as n from (select proname from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace where ns.nspname='public' group by proname having count(*)>1) x")
Write-Host ("Перегрузки функций: {0}" -f $ovl.n)

$ok = ([int]$r1.ok -eq [int]$r1.total -and [int]$r2.ok -eq [int]$r2.total -and [int]$enc.answers_q -eq 0 -and [int]$enc.plans_q -eq 0 -and $waveFail.Count -eq 0 -and [int]$ovl.n -eq 0)
if ($ok) { Write-Host 'Смоук пройден ✅' -ForegroundColor Green; exit 0 }
else { Write-Host 'Смоук не пройден ❌' -ForegroundColor Red; exit 1 }
