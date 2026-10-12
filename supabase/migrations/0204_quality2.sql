-- ============================================================
-- 3DMP Service · 0204_quality2.sql  (X18 — Качество 2.0: qc/claims/passport)
-- SPC онлайн-дашборд, поверка СИ с напоминаниями, CAPA-маршрут (reuse W10),
-- трассируемость изделие→партия→оператор (reuse R3). Идемпотентно. 0001..0203.
-- ============================================================

create or replace function public.app_qc_spc_dashboard(p_token uuid)
returns table (params bigint, signals bigint, alarms bigint, last_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token);
  return query
    select count(distinct s.param), count(*), count(*) filter (where s.signal is not null and lower(s.signal) <> 'ok'), max(s.ts)
      from public.app_spc_signals(p_token, null) s;
end $$;

create or replace function public.app_metrology_scan(p_token uuid, p_days integer default 30)
returns table (due integer, overdue integer, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid; d integer; du integer; ov integer; rec record;
begin
  if not public.app_production_allowed(p_token) then return query select 0,0,'Доступ запрещён'; return; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  d := greatest(coalesce(p_days,30),1);
  select count(*) into du from public.app_measuring_tools m where (adm or m.tenant_id=ten) and m.next_verified is not null and m.next_verified between current_date and current_date + d;
  select count(*) into ov from public.app_measuring_tools m where (adm or m.tenant_id=ten) and m.next_verified is not null and m.next_verified < current_date;
  for rec in
    select m.name, m.serial, m.next_verified from public.app_measuring_tools m
     where (adm or m.tenant_id=ten) and m.next_verified is not null and m.next_verified <= current_date + d
  loop
    perform public.app_notif_roles_t(ten, array['admin','owner','manager','qc'], 'Метрология: поверка СИ',
      rec.name || coalesce(' (' || rec.serial || ')','') || ' — до ' || to_char(rec.next_verified,'DD.MM.YYYY'), 'apps/qc/index.html');
  end loop;
  return query select du, ov, 'К поверке: ' || du || ', просрочено: ' || ov;
end $$;

create or replace function public.app_capa_start(p_token uuid, p_defect_id uuid, p_route_id uuid)
returns table (ok boolean, message text, request_id uuid, task_id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid; uname text; d record; r record; tid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid, null::uuid; return; end if;
  if not public.app_can_edit(p_token, 'qc') then return query select false,'Нет прав на качество', null::uuid, null::uuid; return; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  select s.ulogin into uname from public.app_session_user(p_token) s;
  select * into d from public.app_defects where id = p_defect_id and (adm or tenant_id = ten);
  if d.id is null then return query select false,'Дефект не найден', null::uuid, null::uuid; return; end if;
  insert into public.app_tasks (tenant_id, title, description, status, priority, assignee_login, entity_type, entity_id, pos, created_login)
  values (ten, 'CAPA: ' || d.title, 'Корректирующие/предупреждающие действия по дефекту', 'todo', 'high', d.by_login, 'defect', d.id, 0, uname)
  returning app_tasks.id into tid;
  select * into r from public.app_approval_request_create(p_token, p_route_id, 'defect', d.id, 'CAPA: ' || d.title) x;
  if not r.ok then return query select false, r.message, null::uuid, tid; return; end if;
  return query select true, 'CAPA запущена (задача + маршрут)', r.id, tid;
end $$;

create or replace function public.app_traceability_search(p_token uuid, p_q text)
returns table (id uuid, item text, serial text, material text, operator text, order_number text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid; q text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  q := lower(coalesce(trim(p_q),''));
  return query
    select t.id, t.item, t.serial, t.material, t.operator, o.number, t.created_at
      from public.app_traceability t left join public.app_orders o on o.id = t.order_id
     where (adm or t.tenant_id = ten)
       and (q = '' or lower(t.item) like '%'||q||'%' or lower(coalesce(t.serial,'')) like '%'||q||'%'
            or lower(coalesce(t.material,'')) like '%'||q||'%' or lower(coalesce(t.operator,'')) like '%'||q||'%')
     order by t.created_at desc limit 200;
end $$;

-- ================= База знаний =================
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Качество','Качество 2.0: SPC онлайн, поверка СИ, CAPA-маршрут, трассируемость (X18)',
   'Качество 2.0: SPC онлайн-дашборд (app_qc_spc_dashboard — параметры/сигналы/тревоги, reuse app_spc_signals), поверка СИ с напоминаниями (app_metrology_scan — app_measuring_tools next_verified), CAPA-маршрут (app_capa_start — задача в app_tasks + маршрут app_approval_* по дефекту), трассируемость изделие→партия→оператор (app_traceability_search, reuse R3 app_traceability). Фото дефектов — app_attachment_* / app_attach_*.',
   'качество SPC контроль поверка СИ метрология CAPA дефект трассируемость партия оператор')
) as v(category,question,answer,tags)
where not exists (
  select 1 from public.app_knowledge
   where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001'
     and question = 'Качество 2.0: SPC онлайн, поверка СИ, CAPA-маршрут, трассируемость (X18)'
);

-- ================= Права =================
grant execute on function public.app_qc_spc_dashboard(uuid) to anon, authenticated;
grant execute on function public.app_metrology_scan(uuid,integer) to anon, authenticated;
grant execute on function public.app_capa_start(uuid,uuid,uuid) to anon, authenticated;
grant execute on function public.app_traceability_search(uuid,text) to anon, authenticated;
