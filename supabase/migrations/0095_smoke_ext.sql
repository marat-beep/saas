-- ============================================================
-- 3DMP Service · 0095_smoke_ext.sql  (v73 — Пункт 5: расширенные автотесты)
-- app_smoke_test_ext: проверка доступности новых контуров (IIoT/DNC, счётчики,
-- справочники, нормирование, слоты, наладка, lean, партнёры, оборудование,
-- кадры, конфигуратор, реверс) и покрытия прав. Зависит от 0001..0094.
-- ============================================================

create or replace function public.app_smoke_test_ext(p_token uuid)
returns table (name text, ok boolean, detail text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; cnt bigint;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);

  begin
    execute 'select count(*) from public.app_iiot_readings where ($1 is null or tenant_id=$1)' into cnt using ten;
    name := 'IIoT-телеметрия (0092)'; ok := true; detail := cnt||' показаний'; return next;
  exception when others then name := 'IIoT-телеметрия (0092)'; ok := false; detail := sqlerrm; return next; end;

  begin
    execute 'select count(*) from public.app_dnc_jobs where ($1 is null or tenant_id=$1)' into cnt using ten;
    name := 'DNC-очередь (0092)'; ok := true; detail := cnt||' заданий'; return next;
  exception when others then name := 'DNC-очередь (0092)'; ok := false; detail := sqlerrm; return next; end;

  begin
    execute 'select count(*) from public.app_usage_counters where ($1 is null or tenant_id=$1)' into cnt using ten;
    name := 'Счётчики использования (0093)'; ok := true; detail := cnt||' метрик'; return next;
  exception when others then name := 'Счётчики использования (0093)'; ok := false; detail := sqlerrm; return next; end;

  begin
    execute 'select count(*) from public.app_dictionaries where ($1 is null or tenant_id=$1)' into cnt using ten;
    name := 'Справочники (0080)'; ok := cnt>0; detail := cnt||' справочников'; return next;
  exception when others then name := 'Справочники (0080)'; ok := false; detail := sqlerrm; return next; end;

  begin
    execute 'select count(*) from public.app_norms_operations where ($1 is null or tenant_id=$1)' into cnt using ten;
    name := 'Нормирование (0073)'; ok := cnt>0; detail := cnt||' операций'; return next;
  exception when others then name := 'Нормирование (0073)'; ok := false; detail := sqlerrm; return next; end;

  begin
    execute 'select count(*) from public.app_work_slots where ($1 is null or tenant_id=$1)' into cnt using ten;
    name := 'Слоты (0074)'; ok := true; detail := cnt||' слотов'; return next;
  exception when others then name := 'Слоты (0074)'; ok := false; detail := sqlerrm; return next; end;

  begin
    execute 'select count(*) from public.app_setups where ($1 is null or tenant_id=$1)' into cnt using ten;
    name := 'Наладка (0077)'; ok := true; detail := cnt||' наладок'; return next;
  exception when others then name := 'Наладка (0077)'; ok := false; detail := sqlerrm; return next; end;

  begin
    execute 'select count(*) from public.app_lean_actions where ($1 is null or tenant_id=$1)' into cnt using ten;
    name := 'Lean (0078)'; ok := true; detail := cnt||' предложений'; return next;
  exception when others then name := 'Lean (0078)'; ok := false; detail := sqlerrm; return next; end;

  begin
    execute 'select count(*) from public.app_partners where ($1 is null or tenant_id=$1)' into cnt using ten;
    name := 'Партнёры (0082)'; ok := true; detail := cnt||' партнёров'; return next;
  exception when others then name := 'Партнёры (0082)'; ok := false; detail := sqlerrm; return next; end;

  begin
    execute 'select count(*) from public.app_equipment_catalog where ($1 is null or tenant_id=$1)' into cnt using ten;
    name := 'Каталог оборудования (0083)'; ok := true; detail := cnt||' позиций'; return next;
  exception when others then name := 'Каталог оборудования (0083)'; ok := false; detail := sqlerrm; return next; end;

  begin
    execute 'select count(*) from public.app_staff_crm where ($1 is null or tenant_id=$1)' into cnt using ten;
    name := 'CRM сотрудников (0084)'; ok := true; detail := cnt||' карточек'; return next;
  exception when others then name := 'CRM сотрудников (0084)'; ok := false; detail := sqlerrm; return next; end;

  begin
    execute 'select count(*) from public.app_config_options where ($1 is null or tenant_id=$1)' into cnt using ten;
    name := 'Конфигуратор (0085)'; ok := cnt>0; detail := cnt||' опций'; return next;
  exception when others then name := 'Конфигуратор (0085)'; ok := false; detail := sqlerrm; return next; end;

  begin
    execute 'select count(*) from public.app_reverse_orders where ($1 is null or tenant_id=$1)' into cnt using ten;
    name := 'Реверс-инжиниринг (0086)'; ok := true; detail := cnt||' заявок'; return next;
  exception when others then name := 'Реверс-инжиниринг (0086)'; ok := false; detail := sqlerrm; return next; end;

  begin
    execute 'select count(*) from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace where ns.nspname=''public'' and pg_get_functiondef(p.oid) like ''%app_guard(%''' into cnt;
    name := 'Покрытие прав app_guard'; ok := cnt >= 100; detail := cnt||' функций под guard'; return next;
  exception when others then name := 'Покрытие прав app_guard'; ok := false; detail := sqlerrm; return next; end;
end $$;

grant execute on function public.app_smoke_test_ext(uuid) to anon, authenticated;

insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Эксплуатация','Расширенные автотесты',
   'Функция app_smoke_test_ext проверяет доступность и наполнение новых контуров (IIoT/DNC, счётчики, справочники, нормирование, слоты, наладка, lean, партнёры, оборудование, кадры, конфигуратор, реверс) и покрытие прав app_guard. Запускать на странице «Масштаб и эксплуатация».',
   'автотесты смоук app_smoke_test_ext QA проверка контуров')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Расширенные автотесты');
