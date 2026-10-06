-- ============================================================
-- 3DMP Service · 0074_planning_slots.sql  (v52 — P14 Сессия D)
-- Слоты по времени (мощность по центрам/сменам/датам) + бронирование часов,
-- политика SLA и сканер эскалации по просроченным проблемам.
-- База знаний. Зависит от 0001..0073.
-- ============================================================

create table if not exists public.app_work_slots (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid references public.tenants (id),
  center         text not null,
  slot_date      date not null,
  shift          text not null default '1',   -- 1|2|3|night
  capacity_hours numeric not null default 8,
  used_hours     numeric not null default 0,
  status         text not null default 'open', -- open|full|blocked
  note           text,
  created_at     timestamptz not null default now()
);
create index if not exists app_work_slots_idx on public.app_work_slots (tenant_id, slot_date, center);
alter table public.app_work_slots enable row level security;

create table if not exists public.app_sla_policy (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid references public.tenants (id),
  priority   text not null default 'normal',   -- low|normal|high|critical
  hours      int not null default 24
);
create index if not exists app_sla_policy_idx on public.app_sla_policy (tenant_id, priority);
alter table public.app_sla_policy enable row level security;

-- ---------- Слоты ----------
create or replace function public.app_slots_list(p_token uuid, p_from date default null, p_to date default null, p_center text default null)
returns table (id uuid, center text, slot_date date, shift text, capacity_hours numeric, used_hours numeric,
               free_hours numeric, status text, note text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select w.id, w.center, w.slot_date, w.shift, w.capacity_hours, w.used_hours,
           round(w.capacity_hours - w.used_hours, 2), w.status, w.note
    from public.app_work_slots w
    where (urole='admin' or w.tenant_id=ten)
      and (coalesce(p_from, current_date) <= w.slot_date and w.slot_date <= coalesce(p_to, current_date + 30))
      and (coalesce(p_center,'')='' or w.center = p_center)
    order by w.slot_date, w.center, w.shift;
end $$;

create or replace function public.app_slot_save(p_token uuid, p_id uuid, p_center text, p_slot_date date,
  p_shift text, p_capacity_hours numeric, p_note text)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; sid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director','chief','master','technologist') then raise exception 'Недостаточно прав'; return; end if;
  if coalesce(trim(p_center),'')='' or p_slot_date is null then raise exception 'Укажите центр и дату'; return; end if;
  if p_id is null then
    insert into public.app_work_slots (tenant_id, center, slot_date, shift, capacity_hours, note)
    values (ten, trim(p_center), p_slot_date, coalesce(nullif(trim(p_shift),''),'1'), coalesce(p_capacity_hours,8), nullif(trim(p_note),''))
    returning id into sid;
    return query select sid, 'Слот создан';
  else
    update public.app_work_slots set center=trim(p_center), slot_date=p_slot_date, shift=coalesce(nullif(trim(p_shift),''),shift),
      capacity_hours=coalesce(p_capacity_hours,capacity_hours), note=nullif(trim(p_note),'')
     where id=p_id and (urole='admin' or tenant_id=ten) returning id into sid;
    return query select sid, 'Слот обновлён';
  end if;
end $$;

create or replace function public.app_slot_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  delete from public.app_work_slots where id=p_id and (urole='admin' or tenant_id=ten);
  return query select true,'Слот удалён';
end $$;

create or replace function public.app_slot_book(p_token uuid, p_center text, p_slot_date date, p_shift text, p_hours numeric)
returns table (id uuid, used_hours numeric, capacity_hours numeric, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; sid uuid; used numeric; cap numeric;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if coalesce(p_hours,0) <= 0 then raise exception 'Укажите часы'; return; end if;
  select w.id into sid from public.app_work_slots w
    where w.tenant_id=ten and w.center=trim(p_center) and w.slot_date=p_slot_date and w.shift=coalesce(nullif(trim(p_shift),''),'1');
  if sid is null then
    insert into public.app_work_slots (tenant_id, center, slot_date, shift, capacity_hours, used_hours)
    values (ten, trim(p_center), p_slot_date, coalesce(nullif(trim(p_shift),''),'1'), 8, least(coalesce(p_hours,0),8))
    returning id, used_hours, capacity_hours into sid, used, cap;
  else
    update public.app_work_slots set used_hours = used_hours + coalesce(p_hours,0),
      status = case when used_hours + coalesce(p_hours,0) >= capacity_hours then 'full' else status end
     where id=sid returning used_hours, capacity_hours into used, cap;
  end if;
  return query select sid, used, cap, 'Забронировано ч: '||coalesce(p_hours,0);
end $$;

create or replace function public.app_slots_kpi(p_token uuid)
returns table (slots bigint, hours_capacity numeric, hours_used numeric, utilization_pct numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; cap numeric; usd numeric;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select coalesce(sum(capacity_hours),0), coalesce(sum(used_hours),0) into cap, usd
    from public.app_work_slots where (urole='admin' or tenant_id=ten)
      and slot_date between current_date and current_date + 30;
  return query select
    (select count(*) from public.app_work_slots where (urole='admin' or tenant_id=ten) and slot_date between current_date and current_date + 30),
    cap, usd, round(case when cap>0 then usd/cap*100 else 0 end, 1);
end $$;

-- ---------- SLA ----------
create or replace function public.app_sla_list(p_token uuid)
returns table (id uuid, priority text, hours int)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select s.id, s.priority, s.hours from public.app_sla_policy s
    where (urole='admin' or s.tenant_id=ten)
    order by (case s.priority when 'critical' then 1 when 'high' then 2 when 'normal' then 3 else 4 end);
end $$;

create or replace function public.app_sla_save(p_token uuid, p_id uuid, p_priority text, p_hours int)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; sid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director','chief') then raise exception 'Недостаточно прав'; return; end if;
  if p_priority not in ('low','normal','high','critical') then raise exception 'Приоритет: low|normal|high|critical'; return; end if;
  if p_id is null then
    insert into public.app_sla_policy (tenant_id, priority, hours) values (ten, p_priority, greatest(coalesce(p_hours,24),1)) returning id into sid;
    return query select sid, 'Политика SLA добавлена';
  else
    update public.app_sla_policy set priority=p_priority, hours=greatest(coalesce(p_hours,24),1)
     where id=p_id and (urole='admin' or tenant_id=ten) returning id into sid;
    return query select sid, 'Политика SLA обновлена';
  end if;
end $$;

create or replace function public.app_escalation_scan(p_token uuid)
returns table (escalated int)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; n int := 0; h int;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director','chief') then raise exception 'Недостаточно прав'; return; end if;
  update public.app_issues i
     set escalated = true, escalated_at = now(), updated_at = now()
   where (urole='admin' or i.tenant_id=ten)
     and coalesce(i.escalated,false) = false
     and i.status not in ('done','closed','resolved','cancelled')
     and ( (i.due_date is not null and i.due_date < current_date)
        or (i.due_date is null and i.created_at < now() - make_interval(hours => coalesce(
              (select s2.hours from public.app_sla_policy s2 where s2.tenant_id=i.tenant_id and s2.priority=i.priority limit 1), 24))) );
  get diagnostics n = row_count;
  if n > 0 then
    perform public.app_notif_roles_t(ten, array['admin','owner','manager','director','chief'],
      'Эскалация: просрочено проблем', n || ' шт (превышен SLA)', 'apps/issues/index.html');
  end if;
  return query select n;
end $$;

grant execute on function public.app_slots_list(uuid,date,date,text) to anon, authenticated;
grant execute on function public.app_slot_save(uuid,uuid,text,date,text,numeric,text) to anon, authenticated;
grant execute on function public.app_slot_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_slot_book(uuid,text,date,text,numeric) to anon, authenticated;
grant execute on function public.app_slots_kpi(uuid) to anon, authenticated;
grant execute on function public.app_sla_list(uuid) to anon, authenticated;
grant execute on function public.app_sla_save(uuid,uuid,text,int) to anon, authenticated;
grant execute on function public.app_escalation_scan(uuid) to anon, authenticated;

-- ---------- Демо (тенант A) ----------
do $$
declare c text; d int;
begin
  if not exists (select 1 from public.app_work_slots where tenant_id='aaaaaaaa-0000-0000-0000-000000000001') then
    foreach c in array array['Фрезерный участок','Токарный участок','ЭЭО','Шлифование'] loop
      for d in 0..6 loop
        insert into public.app_work_slots (tenant_id, center, slot_date, shift, capacity_hours, used_hours, status)
        values ('aaaaaaaa-0000-0000-0000-000000000001', c, current_date + d, '1', 8,
                case when d=0 then 5.5 when d=1 then 8 else 0 end,
                case when d=1 then 'full' else 'open' end);
      end loop;
    end loop;
  end if;
  if not exists (select 1 from public.app_sla_policy where tenant_id='aaaaaaaa-0000-0000-0000-000000000001') then
    insert into public.app_sla_policy (tenant_id, priority, hours) values
      ('aaaaaaaa-0000-0000-0000-000000000001','critical',4),
      ('aaaaaaaa-0000-0000-0000-000000000001','high',8),
      ('aaaaaaaa-0000-0000-0000-000000000001','normal',24),
      ('aaaaaaaa-0000-0000-0000-000000000001','low',72);
  end if;
end $$;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Нормирование','Слоты по времени и SLA-эскалация (P14 Сессия D)',
   'Модуль «Слоты и загрузка»: мощность рабочих центров по датам и сменам (capacity/used, статус open/full), бронирование часов. Политика SLA по приоритетам (critical 4ч, high 8ч, normal 24ч, low 72ч). Сканер эскалации поднимает просроченные проблемы (по due_date или created_at + SLA) и уведомляет руководителей.',
   'слоты смена мощность загрузка бронирование SLA эскалация просрочка P14')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Слоты по времени и SLA-эскалация (P14 Сессия D)');
