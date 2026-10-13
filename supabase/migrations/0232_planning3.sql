-- ============================================================
-- 3DMP Service · 0232_planning3.sql
-- X12 (остаток): сценарии планирования, переналадки, зависимости Ганта.
--  • app_plan_scenarios — именованные сценарии APS (даты/горизонт), запуск.
--  • app_changeovers — нормы времени переналадки «семейство → семейство».
--  • app_plan_dep — зависимости наряд→предшественник (лаг), контроль нарушений.
-- Идемпотентно. Зависит от 0001..0231.
-- ============================================================

create table if not exists public.app_plan_scenarios (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid references public.tenants (id),
  name       text not null,
  from_date  date not null default current_date,
  days       integer not null default 14,
  note       text,
  created_by text,
  created_at timestamptz not null default now()
);
create index if not exists app_plan_scenarios_idx on public.app_plan_scenarios (tenant_id, created_at);
alter table public.app_plan_scenarios enable row level security;

create table if not exists public.app_changeovers (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid references public.tenants (id),
  from_family text,
  to_family   text,
  minutes     numeric not null default 0,
  note        text,
  created_at  timestamptz not null default now()
);
create index if not exists app_changeovers_idx on public.app_changeovers (tenant_id);
alter table public.app_changeovers enable row level security;

create table if not exists public.app_plan_dep (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid references public.tenants (id),
  naryad_id    uuid not null references public.app_naryads (id) on delete cascade,
  pred_naryad_id uuid not null references public.app_naryads (id) on delete cascade,
  lag_days     integer not null default 0,
  note         text,
  created_at   timestamptz not null default now(),
  unique (tenant_id, naryad_id, pred_naryad_id)
);
create index if not exists app_plan_dep_idx on public.app_plan_dep (tenant_id, naryad_id);
alter table public.app_plan_dep enable row level security;

-- ---------- Сценарии ----------
create or replace function public.app_plan_scenario_list(p_token uuid)
returns table (id uuid, name text, from_date date, days integer, note text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query select s.id, s.name, s.from_date, s.days, s.note, s.created_at
    from public.app_plan_scenarios s where (adm or s.tenant_id = ten) order by s.created_at desc;
end $$;

create or replace function public.app_plan_scenario_save(p_token uuid, p_id uuid, p_name text, p_from date, p_days integer, p_note text)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid; uname text; newid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён',null::uuid; return; end if;
  if not public.app_can_edit(p_token, 'planning') then return query select false,'Нет прав на планирование',null::uuid; return; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  select s.ulogin into uname from public.app_session_user(p_token) s;
  if coalesce(trim(p_name),'') = '' then return query select false,'Укажите название сценария',null::uuid; return; end if;
  if p_id is null then
    insert into public.app_plan_scenarios (tenant_id, name, from_date, days, note, created_by)
    values (ten, left(trim(p_name),120), coalesce(p_from, current_date), greatest(least(coalesce(p_days,14),60),1), nullif(trim(p_note),''), uname)
    returning id into newid;
    return query select true,'Сценарий создан', newid;
  else
    update public.app_plan_scenarios set name=left(trim(p_name),120), from_date=coalesce(p_from,from_date),
      days=greatest(least(coalesce(p_days,days),60),1), note=nullif(trim(p_note),'')
     where id=p_id and (adm or tenant_id=ten) returning id into newid;
    if newid is null then return query select false,'Сценарий не найден',null::uuid; return; end if;
    return query select true,'Сценарий сохранён', newid;
  end if;
end $$;

create or replace function public.app_plan_scenario_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  if not public.app_can_edit(p_token, 'planning') then return query select false,'Нет прав на планирование'; return; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  delete from public.app_plan_scenarios where id=p_id and (adm or tenant_id=ten);
  return query select true,'Сценарий удалён';
end $$;

-- run: строит план по параметрам сценария (без применения)
create or replace function public.app_plan_scenario_run(p_token uuid, p_id uuid)
returns table (number text, title text, priority text, remaining numeric, plan_start date, plan_end date,
               days integer, due_date date, risk text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid; sc record;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  select * into sc from public.app_plan_scenarios s where s.id=p_id and (adm or s.tenant_id=ten);
  if sc.id is null then raise exception 'Сценарий не найден'; end if;
  return query select * from public.app_aps_build(p_token, sc.from_date, sc.days);
end $$;

-- ---------- Переналадки ----------
create or replace function public.app_changeover_list(p_token uuid, p_q text default null)
returns table (id uuid, from_family text, to_family text, minutes numeric, note text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query select c.id, c.from_family, c.to_family, c.minutes, c.note
    from public.app_changeovers c
   where (adm or c.tenant_id = ten)
     and (qq='' or lower(coalesce(c.from_family,'')) like '%'||qq||'%' or lower(coalesce(c.to_family,'')) like '%'||qq||'%')
   order by c.from_family, c.to_family;
end $$;

create or replace function public.app_changeover_save(p_token uuid, p_id uuid, p_from text, p_to text, p_minutes numeric, p_note text)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid; newid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён',null::uuid; return; end if;
  if not public.app_can_edit(p_token, 'planning') then return query select false,'Нет прав на планирование',null::uuid; return; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_to),'') = '' then return query select false,'Укажите семейство «в»',null::uuid; return; end if;
  if p_id is null then
    insert into public.app_changeovers (tenant_id, from_family, to_family, minutes, note)
    values (ten, nullif(trim(p_from),''), trim(p_to), greatest(coalesce(p_minutes,0),0), nullif(trim(p_note),'')) returning id into newid;
    return query select true,'Переналадка добавлена', newid;
  else
    update public.app_changeovers set from_family=nullif(trim(p_from),''), to_family=trim(p_to),
      minutes=greatest(coalesce(p_minutes,minutes),0), note=nullif(trim(p_note),'')
     where id=p_id and (adm or tenant_id=ten) returning id into newid;
    if newid is null then return query select false,'Запись не найдена',null::uuid; return; end if;
    return query select true,'Переналадка сохранена', newid;
  end if;
end $$;

create or replace function public.app_changeover_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  if not public.app_can_edit(p_token, 'planning') then return query select false,'Нет прав на планирование'; return; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  delete from public.app_changeovers where id=p_id and (adm or tenant_id=ten);
  return query select true,'Удалено';
end $$;

create or replace function public.app_changeover_minutes(p_token uuid, p_from text, p_to text)
returns numeric
language plpgsql security definer set search_path = public
as $$
declare adm boolean; ten uuid; m numeric;
begin
  if not public.app_production_allowed(p_token) then return 0; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  select c.minutes into m from public.app_changeovers c
   where (adm or c.tenant_id = ten)
     and lower(coalesce(c.from_family,'')) = lower(coalesce(p_from,''))
     and lower(c.to_family) = lower(coalesce(p_to,''))
   order by c.created_at desc limit 1;
  return coalesce(m, 0);
end $$;

-- ---------- Зависимости Ганта ----------
create or replace function public.app_plan_deps_list(p_token uuid)
returns table (id uuid, naryad_id uuid, naryad text, pred_naryad_id uuid, pred text, lag_days integer, note text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query select d.id, d.naryad_id, n.number, d.pred_naryad_id, p.number, d.lag_days, d.note
    from public.app_plan_dep d
    join public.app_naryads n on n.id = d.naryad_id
    join public.app_naryads p on p.id = d.pred_naryad_id
   where (adm or d.tenant_id = ten)
   order by p.number, n.number;
end $$;

create or replace function public.app_plan_dep_save(p_token uuid, p_id uuid, p_naryad_id uuid, p_pred_id uuid, p_lag integer, p_note text)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid; newid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён',null::uuid; return; end if;
  if not public.app_can_edit(p_token, 'planning') then return query select false,'Нет прав на планирование',null::uuid; return; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  if p_naryad_id is null or p_pred_id is null then return query select false,'Выберите наряд и предшественника',null::uuid; return; end if;
  if p_naryad_id = p_pred_id then return query select false,'Наряд не может зависеть от себя',null::uuid; return; end if;
  if p_id is null then
    insert into public.app_plan_dep (tenant_id, naryad_id, pred_naryad_id, lag_days, note)
    values (ten, p_naryad_id, p_pred_id, coalesce(p_lag,0), nullif(trim(p_note),'')) returning id into newid;
    return query select true,'Зависимость добавлена', newid;
  else
    update public.app_plan_dep set naryad_id=p_naryad_id, pred_naryad_id=p_pred_id, lag_days=coalesce(p_lag,lag_days), note=nullif(trim(p_note),'')
     where id=p_id and (adm or tenant_id=ten) returning id into newid;
    if newid is null then return query select false,'Запись не найдена',null::uuid; return; end if;
    return query select true,'Зависимость сохранена', newid;
  end if;
exception when unique_violation then
  return query select false,'Такая зависимость уже есть',null::uuid;
end $$;

create or replace function public.app_plan_dep_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  if not public.app_can_edit(p_token, 'planning') then return query select false,'Нет прав на планирование'; return; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  delete from public.app_plan_dep where id=p_id and (adm or tenant_id=ten);
  return query select true,'Удалено';
end $$;

create or replace function public.app_plan_deps_check(p_token uuid)
returns table (naryad text, pred text, lag_days integer, pred_end date, plan_start date, expected_start date, violation boolean)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query
    select n.number, p.number, d.lag_days, p.plan_end, n.plan_start,
           (p.plan_end + coalesce(d.lag_days,0))::date as expected_start,
           (p.plan_end is not null and n.plan_start is not null and n.plan_start < (p.plan_end + coalesce(d.lag_days,0)))
      from public.app_plan_dep d
      join public.app_naryads n on n.id = d.naryad_id
      join public.app_naryads p on p.id = d.pred_naryad_id
     where (adm or d.tenant_id = ten)
     order by violation desc nulls last, n.number;
end $$;

grant execute on function public.app_plan_scenario_list(uuid)                 to anon, authenticated;
grant execute on function public.app_plan_scenario_save(uuid,uuid,text,date,integer,text) to anon, authenticated;
grant execute on function public.app_plan_scenario_delete(uuid,uuid)         to anon, authenticated;
grant execute on function public.app_plan_scenario_run(uuid,uuid)            to anon, authenticated;
grant execute on function public.app_changeover_list(uuid,text)              to anon, authenticated;
grant execute on function public.app_changeover_save(uuid,uuid,text,text,numeric,text) to anon, authenticated;
grant execute on function public.app_changeover_delete(uuid,uuid)            to anon, authenticated;
grant execute on function public.app_changeover_minutes(uuid,text,text)      to anon, authenticated;
grant execute on function public.app_plan_deps_list(uuid)                    to anon, authenticated;
grant execute on function public.app_plan_dep_save(uuid,uuid,uuid,uuid,integer,text) to anon, authenticated;
grant execute on function public.app_plan_dep_delete(uuid,uuid)              to anon, authenticated;
grant execute on function public.app_plan_deps_check(uuid)                   to anon, authenticated;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select null, v.category, v.question, v.answer, v.tags
from (values
  ('Планирование','Сценарии планирования, переналадки и зависимости Ганта (X12)',
   'Планирование 2.0: Сценарии — вкладка «Сценарии и связи» позволяет сохранить именованные сценарии APS (дата старта, горизонт дней), построить по ним план (app_plan_scenario_run) и применить (app_aps_apply). Переналадки — нормы времени «семейство → семейство» (app_changeovers, app_changeover_minutes) для учёта перехода между группами деталей. Зависимости Ганта — связи наряд→предшественник с лагом в днях (app_plan_dep); контроль нарушений (app_plan_deps_check) показывает, где план нарушает последовательность (plan_start раньше pred.plan_end + лаг).',
   'планирование APS сценарии переналадки зависимости Гант связи лаг X12 app_plan_scenario app_changeovers app_plan_dep')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge k where k.question=v.question);
