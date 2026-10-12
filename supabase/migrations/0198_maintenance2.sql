-- ============================================================
-- 3DMP Service · 0198_maintenance2.sql  (X13 — Оборудование/ТОиР 2.0)
-- Авто-наряд по предиктиву (app_mnt_predictive_autoplan), карточка-дашборд
-- оборудования (app_equipment_card), инструмент по операции (app_naryad_op_tools).
-- Идемпотентно. Зависит от 0001..0197.
-- ============================================================

-- ================= RPC: авто-наряд по предиктиву =================
create or replace function public.app_mnt_predictive_autoplan(p_token uuid, p_days integer default 30)
returns table (ok boolean, message text, created integer)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid; uname text; cnt integer := 0; rec record; due date;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', 0; return; end if;
  if not public.app_can_edit(p_token, 'maintenance') then return query select false,'Нет прав на ТОиР', 0; return; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  select s.ulogin into uname from public.app_session_user(p_token) s;
  for rec in
    with a as (
      select v.equipment_id, avg(v.value) as avg_v, coalesce(stddev(v.value),0) as sd,
             (array_agg(v.value order by v.ts desc))[1] as last_v
        from public.app_vibro_readings v
       where (adm or v.tenant_id = ten)
       group by v.equipment_id
    )
    select a.equipment_id, e.name, a.last_v, a.avg_v, a.sd
      from a join public.app_equipment e on e.id = a.equipment_id
     where a.equipment_id is not null and a.last_v > a.avg_v + greatest(a.sd, 0.01)
       and not exists (select 1 from public.app_mnt_plans p
                        where p.equipment_id = a.equipment_id and p.active and p.note like 'Автоплан%')
  loop
    due := current_date + greatest(1, least(coalesce(p_days,30), 30));
    insert into public.app_mnt_plans (tenant_id, equipment_id, kind, title, period_days, next_due, responsible, active, note)
    values (ten, rec.equipment_id, 'ppr', 'Автоплан ТОиР (вибрация): ' || rec.name, coalesce(p_days,30), due, uname, true,
            'Автоплан% по вибрации: послед. ' || round(rec.last_v,3) || ' > ср. ' || round(rec.avg_v,3) || ' + σ ' || round(rec.sd,3));
    perform public.app_notif_roles_t(ten, array['admin','owner','manager','chief','master'], 'ТОиР: автоплан по оборудованию', rec.name || ' — до ' || to_char(due,'DD.MM.YYYY'), 'apps/maintenance/index.html');
    cnt := cnt + 1;
  end loop;
  return query select true, 'Автопланов ТОиР: ' || cnt, cnt;
end $$;

-- ================= RPC: карточка-дашборд оборудования =================
create or replace function public.app_equipment_card(p_token uuid, p_equipment_id uuid)
returns table (id uuid, code text, name text, model text, kind text, cost_hour numeric,
               plans_active bigint, next_due date, service_total bigint, service_open bigint,
               vibro_last numeric, vibro_result text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query
    select e.id, e.code, e.name, e.model, e.kind, e.cost_hour,
           (select count(*) from public.app_mnt_plans p where p.equipment_id = e.id and p.active),
           (select min(p.next_due) from public.app_mnt_plans p where p.equipment_id = e.id and p.active),
           (select count(*) from public.app_service_requests s where s.equipment_id = e.id),
           (select count(*) from public.app_service_requests s where s.equipment_id = e.id and s.status not in ('done','closed','cancelled')),
           (select v.value from public.app_vibro_readings v where v.equipment_id = e.id order by v.ts desc limit 1),
           (select v.result from public.app_vibro_readings v where v.equipment_id = e.id order by v.ts desc limit 1)
      from public.app_equipment e
     where e.id = p_equipment_id and (adm or e.tenant_id = ten);
end $$;

-- ================= RPC: инструмент по операции наряда =================
create or replace function public.app_naryad_op_tools(p_token uuid, p_op_id uuid)
returns table (tool_life_id uuid, qty numeric, note text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid; rsid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  select op.route_step_id into rsid from public.app_naryad_ops op join public.app_naryads n on n.id = op.naryad_id
   where op.id = p_op_id and (adm or n.tenant_id = ten);
  if rsid is null then return; end if;
  return query
    select rt.tool_life_id, rt.qty, rt.note
      from public.app_route_tools rt
     where rt.route_step_id = rsid and (adm or rt.tenant_id = ten);
end $$;

-- ================= База знаний =================
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Производство','Оборудование/ТОиР 2.0: автоплан по предиктиву, карточка станка, инструмент (X13)',
   'ТОиР 2.0: авто-наряд по предиктиву (app_mnt_predictive_autoplan — вибрация выше среднего+σ → план ППР в app_mnt_plans + уведомление; без дублей), карточка-дашборд оборудования (app_equipment_card — паспорт, активные планы и ближайший срок, сервисные заявки/открытые, последняя вибрация и оценка), инструмент по операции наряда (app_naryad_op_tools — из app_route_tools по шагу маршрута).',
   'оборудование ТОиР предиктив вибрация автоплан карточка станка инструмент операция')
) as v(category,question,answer,tags)
where not exists (
  select 1 from public.app_knowledge
   where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001'
     and question = 'Оборудование/ТОиР 2.0: автоплан по предиктиву, карточка станка, инструмент (X13)'
);

-- ================= Права =================
grant execute on function public.app_mnt_predictive_autoplan(uuid,integer) to anon, authenticated;
grant execute on function public.app_equipment_card(uuid,uuid) to anon, authenticated;
grant execute on function public.app_naryad_op_tools(uuid,uuid) to anon, authenticated;
