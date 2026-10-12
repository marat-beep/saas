-- ============================================================
-- 3DMP Service · 0194_planning2.sql  (X12 — Планирование 2.0)
-- Ёмкость РЦ по дням (app_wc_capacity), слоты плана (app_plan_slots),
-- эвристический APS-солвер (app_aps_solve), Гант и загрузка РЦ.
-- Идемпотентно. Зависит от 0001..0193.
-- ============================================================

create table if not exists public.app_wc_capacity (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid references public.tenants (id),
  wc_id          uuid not null references public.app_work_centers (id) on delete cascade,
  cap_date       date not null,
  capacity_hours numeric not null default 8
);
create unique index if not exists app_wc_capacity_uq on public.app_wc_capacity (tenant_id, wc_id, cap_date);
alter table public.app_wc_capacity enable row level security;

create table if not exists public.app_plan_slots (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  plan_date     date not null,
  wc_id         uuid references public.app_work_centers (id) on delete cascade,
  naryad_id     uuid references public.app_naryads (id) on delete cascade,
  hours         numeric not null default 0,
  source        text not null default 'aps',
  created_login text,
  created_at    timestamptz not null default now()
);
create index if not exists app_plan_slots_idx on public.app_plan_slots (tenant_id, plan_date, wc_id);
alter table public.app_plan_slots enable row level security;

-- ================= RPC: ёмкость РЦ =================
create or replace function public.app_capacity_list(p_token uuid, p_from date default null, p_to date default null)
returns table (id uuid, wc_id uuid, wc_name text, cap_date date, capacity_hours numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query
    select c.id, c.wc_id, w.name, c.cap_date, c.capacity_hours
      from public.app_wc_capacity c left join public.app_work_centers w on w.id = c.wc_id
     where (adm or c.tenant_id = ten)
       and (p_from is null or c.cap_date >= p_from) and (p_to is null or c.cap_date <= p_to)
     order by c.cap_date, w.name;
end $$;

create or replace function public.app_capacity_set(p_token uuid, p_wc_id uuid, p_date date, p_hours numeric)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; uname text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  if not public.app_can_edit(p_token, 'planning') then return query select false,'Нет прав на планирование'; return; end if;
  select u.tenant_id, s.ulogin into ten, uname from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  if p_wc_id is null or p_date is null then return query select false,'Укажите РЦ и дату'; return; end if;
  if not exists (select 1 from public.app_work_centers w where w.id = p_wc_id and (public.app_is_platform_admin(p_token) or w.tenant_id = ten)) then
    return query select false,'Рабочий центр не найден'; return;
  end if;
  insert into public.app_wc_capacity (tenant_id, wc_id, cap_date, capacity_hours)
  values (ten, p_wc_id, p_date, greatest(coalesce(p_hours,8),0))
  on conflict (tenant_id, wc_id, cap_date) do update set capacity_hours = greatest(coalesce(p_hours,8),0);
  return query select true,'Ёмкость РЦ на ' || to_char(p_date,'DD.MM') || ' = ' || greatest(coalesce(p_hours,8),0) || ' ч';
end $$;

-- ================= RPC: APS-солвер (эвристика) =================
create or replace function public.app_aps_solve(p_token uuid, p_from date default current_date, p_days integer default 14)
returns table (naryads integer, slots integer, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid; uname text; v_from date; v_days int; i int; d date; wcid uuid; cap numeric; used numeric; take numeric; rem numeric;
        rec record; first_day date; last_day date; cnt_n int := 0; cnt_s int := 0;
begin
  if not public.app_production_allowed(p_token) then return query select 0,0,'Доступ запрещён'; return; end if;
  if not public.app_can_edit(p_token, 'planning') then return query select 0,0,'Нет прав на планирование'; return; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  select s.ulogin into uname from public.app_session_user(p_token) s;
  v_from := coalesce(p_from, current_date);
  v_days := greatest(least(coalesce(p_days,14),60),1);
  delete from public.app_plan_slots where (adm or tenant_id = ten) and source = 'aps'
    and plan_date between v_from and v_from + (v_days - 1);
  for rec in
    select n.id, n.number, n.wc_id, n.plan_hours, n.fact_hours, n.priority, n.due_date
      from public.app_naryads n
     where (adm or n.tenant_id = ten) and n.status in ('open','in_progress','paused','queue')
     order by case n.priority when 'high' then 0 when 'normal' then 1 else 2 end, n.due_date nulls last, n.created_at
  loop
    rem := greatest(coalesce(rec.plan_hours,0) - coalesce(rec.fact_hours,0), 0);
    if rem <= 0 then continue; end if;
    wcid := rec.wc_id;
    if wcid is null then
      select w.id into wcid from public.app_work_centers w
       where (adm or w.tenant_id = ten)
       order by (select coalesce(sum(s.hours),0) from public.app_plan_slots s where s.wc_id = w.id) limit 1;
    end if;
    if wcid is null then continue; end if;
    first_day := null; last_day := null;
    for i in 0 .. (v_days - 1) loop
      exit when rem <= 0;
      d := v_from + i;
      cap := coalesce((select c.capacity_hours from public.app_wc_capacity c where c.wc_id = wcid and c.cap_date = d), 8);
      used := coalesce((select sum(s.hours) from public.app_plan_slots s where s.wc_id = wcid and s.plan_date = d), 0);
      take := least(rem, greatest(cap - used, 0));
      if take > 0 then
        insert into public.app_plan_slots (tenant_id, plan_date, wc_id, naryad_id, hours, source, created_login)
        values (ten, d, wcid, rec.id, take, 'aps', uname);
        cnt_s := cnt_s + 1;
        rem := rem - take;
        if first_day is null then first_day := d; end if;
        last_day := d;
      end if;
    end loop;
    if first_day is not null then
      update public.app_naryads set plan_start = first_day, plan_end = last_day, updated_at = now() where id = rec.id;
      cnt_n := cnt_n + 1;
    end if;
  end loop;
  return query select cnt_n, cnt_s, 'Распределено нарядов: ' || cnt_n || ', слотов: ' || cnt_s;
end $$;

-- ================= RPC: Гант по слотам =================
create or replace function public.app_plan_gantt(p_token uuid, p_from date default current_date, p_to date default null)
returns table (plan_date date, wc_id uuid, wc_name text, naryad_id uuid, naryad_number text, title text,
               hours numeric, priority text, due_date date, day_load numeric, day_cap numeric, overload boolean)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid; v_to date;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  v_to := coalesce(p_to, p_from + 13);
  return query
    select s.plan_date, s.wc_id, w.name, s.naryad_id, n.number, n.title, s.hours, n.priority, n.due_date,
           (select coalesce(sum(s2.hours),0) from public.app_plan_slots s2 where s2.wc_id = s.wc_id and s2.plan_date = s.plan_date),
           coalesce((select c.capacity_hours from public.app_wc_capacity c where c.wc_id = s.wc_id and c.cap_date = s.plan_date), 8),
           ((select coalesce(sum(s2.hours),0) from public.app_plan_slots s2 where s2.wc_id = s.wc_id and s2.plan_date = s.plan_date)
             > coalesce((select c.capacity_hours from public.app_wc_capacity c where c.wc_id = s.wc_id and c.cap_date = s.plan_date), 8))
      from public.app_plan_slots s
      join public.app_naryads n on n.id = s.naryad_id
      left join public.app_work_centers w on w.id = s.wc_id
     where (adm or s.tenant_id = ten) and s.plan_date between p_from and v_to
     order by s.plan_date, w.name, s.hours desc;
end $$;

-- ================= RPC: загрузка РЦ =================
create or replace function public.app_wc_load(p_token uuid, p_from date default current_date, p_days integer default 14)
returns table (wc_id uuid, wc_name text, day date, load numeric, capacity numeric, load_pct numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid; v_from date; v_days int;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  v_from := coalesce(p_from, current_date);
  v_days := greatest(least(coalesce(p_days,14),60),1);
  return query
    with days as (select generate_series(v_from, v_from + (v_days - 1), interval '1 day')::date as day),
         wcs as (select w.id, w.name from public.app_work_centers w where (adm or w.tenant_id = ten))
    select w.id, w.name, d.day,
           coalesce((select sum(s.hours) from public.app_plan_slots s where s.wc_id = w.id and s.plan_date = d.day), 0),
           coalesce((select c.capacity_hours from public.app_wc_capacity c where c.wc_id = w.id and c.cap_date = d.day), 8),
           round(100.0 * coalesce((select sum(s.hours) from public.app_plan_slots s where s.wc_id = w.id and s.plan_date = d.day), 0)
                 / greatest(coalesce((select c.capacity_hours from public.app_wc_capacity c where c.wc_id = w.id and c.cap_date = d.day), 8), 0.01), 1)
      from wcs w cross join days d
     order by d.day, w.name;
end $$;

-- ================= База знаний =================
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Планирование','Планирование 2.0: ёмкость РЦ, APS-слоты, Гант (X12)',
   'Планирование 2.0: ёмкость рабочих центров по дням (app_wc_capacity + app_capacity_set/list; по умолчанию 8 ч/день), слоты плана (app_plan_slots), эвристический APS-солвер (app_aps_solve — распределяет остаток нарядов по дням и РЦ с учётом приоритета, срока и ёмкости; перезаписывает слоты source=aps; проставляет plan_start/plan_end), диаграмма Ганта (app_plan_gantt — слоты с загрузкой дня и флагом перегрузки), загрузка РЦ (app_wc_load — % загрузки по дням).',
   'планирование APS ёмкость рабочий центр слоты Гант загрузка перегрузка расписание')
) as v(category,question,answer,tags)
where not exists (
  select 1 from public.app_knowledge
   where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001'
     and question = 'Планирование 2.0: ёмкость РЦ, APS-слоты, Гант (X12)'
);

-- ================= Права =================
grant execute on function public.app_capacity_list(uuid,date,date) to anon, authenticated;
grant execute on function public.app_capacity_set(uuid,uuid,date,numeric) to anon, authenticated;
grant execute on function public.app_aps_solve(uuid,date,integer) to anon, authenticated;
grant execute on function public.app_plan_gantt(uuid,date,date) to anon, authenticated;
grant execute on function public.app_wc_load(uuid,date,integer) to anon, authenticated;
