-- ============================================================
-- 3DMP Service · 0119_maintenance_ppr_parts.sql  (W4 — ТОиР: ППР по наработке и запчасти)
-- Норма наработки у планов, авто-наряд ТО по наработке, склад запчастей ТОиР,
-- расход запчастей в работе и затраты по оборудованию.
-- Идемпотентно. Зависит от 0001..0118.
-- ============================================================

alter table public.app_mnt_plans add column if not exists period_hours numeric;   -- норма наработки, ч
alter table public.app_mnt_log   add column if not exists part_cost numeric default 0;

create table if not exists public.app_spare_parts (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid references public.tenants (id),
  code       text,
  name       text not null,
  unit       text default 'шт',
  qty        numeric not null default 0,
  min_qty    numeric not null default 0,
  price      numeric default 0,
  active     boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists app_spare_parts_idx on public.app_spare_parts (tenant_id, name);

create table if not exists public.app_mnt_parts (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  log_id        uuid not null references public.app_mnt_log (id) on delete cascade,
  part_id       uuid references public.app_spare_parts (id) on delete set null,
  part_name     text,
  qty           numeric not null default 0,
  price         numeric default 0,
  created_login text,
  created_at    timestamptz not null default now()
);
create index if not exists app_mnt_parts_idx on public.app_mnt_parts (log_id);

alter table public.app_spare_parts enable row level security;
alter table public.app_mnt_parts   enable row level security;

-- ============================================================
--  ППР по наработке: статус с учётом нормы наработки (period_hours)
-- ============================================================
drop function if exists public.app_mnt_runtime_status(uuid);
create or replace function public.app_mnt_runtime_status(p_token uuid)
returns table (plan_id uuid, equipment text, kind text, period_days int, period_hours numeric, last_done date, next_due date,
               run_hours numeric, due_hours numeric, pct numeric, status text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select p.id, coalesce(e.name, '—'), p.kind, p.period_days, p.period_hours, p.last_done, p.next_due,
           round(coalesce(run.h, 0), 1),
           coalesce(p.period_hours, (coalesce(p.period_days, 30) * 8)::numeric),
           case when coalesce(p.period_hours, (coalesce(p.period_days, 30) * 8)::numeric) > 0
                then round(coalesce(run.h, 0) / coalesce(p.period_hours, (coalesce(p.period_days, 30) * 8)::numeric) * 100, 1) else null end,
           case
             when (p.next_due is not null and p.next_due < current_date)
               or coalesce(run.h, 0) >= coalesce(p.period_hours, (coalesce(p.period_days, 30) * 8)::numeric) then 'overdue'
             when coalesce(run.h, 0) >= 0.8 * coalesce(p.period_hours, (coalesce(p.period_days, 30) * 8)::numeric) then 'soon'
             else 'ok'
           end
      from public.app_mnt_plans p
      left join public.app_equipment e on e.id = p.equipment_id
      left join lateral (
        select sum(o.run_min) / 60.0 as h from public.app_oee_log o
         where o.equipment_id = p.equipment_id and (p.last_done is null or o.shift_date >= p.last_done)
      ) run on true
     where coalesce(p.active, true) and (urole = 'admin' or p.tenant_id = ten)
     order by p.next_due nulls last;
end $$;
grant execute on function public.app_mnt_runtime_status(uuid) to anon, authenticated;

-- Авто-наряд ТО по наработке: для просроченных планов создаёт запланированную работу.
drop function if exists public.app_mnt_auto_schedule(uuid);
create or replace function public.app_mnt_auto_schedule(p_token uuid)
returns table (created bigint, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ten uuid; r record; cnt bigint := 0; lid uuid;
begin
  select s.uid into uid from public.app_session_user(p_token) s;
  if uid is null then return query select 0::bigint, 'Сессия недействительна'; return; end if;
  if not public.app_can(p_token, 'maintenance', 'edit') then return query select 0::bigint, 'Нет прав'; return; end if;
  ten := public.app_my_tenant(p_token);
  for r in
    select p.id, p.tenant_id, p.equipment_id, p.kind, e.name as equipment
      from public.app_mnt_runtime_status(p_token) rs
      join public.app_mnt_plans p on p.id = rs.plan_id
      left join public.app_equipment e on e.id = p.equipment_id
     where rs.status = 'overdue'
       and not exists (select 1 from public.app_mnt_log l where l.plan_id = p.id and l.status = 'planned')
  loop
    insert into public.app_mnt_log (tenant_id, plan_id, equipment_id, kind, work_date, status, note, created_login)
    values (r.tenant_id, r.id, r.equipment_id, r.kind, current_date, 'planned', 'Авто-наряд по наработке (ППР)', (select ulogin from public.app_session_user(p_token)))
    returning app_mnt_log.id into lid;
    perform public.app_notif_roles_t(r.tenant_id, array['admin','owner','manager','chief','master','technologist'],
            'ППР: сформирован наряд ТО', coalesce(r.equipment, '') || ' · ' || coalesce(r.kind, ''), 'apps/maintenance/index.html');
    cnt := cnt + 1;
  end loop;
  return query select cnt, case when cnt > 0 then 'Сформировано нарядов: ' || cnt else 'Нет просроченных планов' end;
end $$;

-- ============================================================
--  Склад запчастей ТОиР
-- ============================================================
drop function if exists public.app_spare_parts_list(uuid);
create or replace function public.app_spare_parts_list(p_token uuid)
returns table (id uuid, code text, name text, unit text, qty numeric, min_qty numeric, price numeric, low boolean, value numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; urole text; ten uuid;
begin
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token);
  return query
    select p.id, p.code, p.name, p.unit, p.qty, p.min_qty, p.price, (p.qty < p.min_qty), (p.qty * p.price)
      from public.app_spare_parts p
     where p.active and (urole = 'admin' or p.tenant_id = ten)
     order by p.name;
end $$;

drop function if exists public.app_spare_part_save(uuid,uuid,text,text,text,numeric,numeric,numeric);
create or replace function public.app_spare_part_save(
  p_token uuid, p_id uuid, p_code text, p_name text, p_unit text, p_qty numeric, p_min_qty numeric, p_price numeric
) returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ten uuid; pid uuid;
begin
  select s.uid into uid from public.app_session_user(p_token) s;
  if uid is null then return query select false, 'Сессия недействительна', null::uuid; return; end if;
  if not public.app_can(p_token, 'maintenance', 'edit') then return query select false, 'Нет прав', null::uuid; return; end if;
  if coalesce(trim(p_name), '') = '' then return query select false, 'Укажите название', null::uuid; return; end if;
  ten := public.app_my_tenant(p_token);
  if p_id is null then
    insert into public.app_spare_parts (tenant_id, code, name, unit, qty, min_qty, price)
    values (ten, nullif(trim(p_code),''), trim(p_name), coalesce(nullif(trim(p_unit),''),'шт'), coalesce(p_qty,0), coalesce(p_min_qty,0), coalesce(p_price,0))
    returning app_spare_parts.id into pid;
  else
    update public.app_spare_parts p
       set code = nullif(trim(p_code),''), name = trim(p_name), unit = coalesce(nullif(trim(p_unit),''),'шт'),
           qty = coalesce(p_qty, p.qty), min_qty = coalesce(p_min_qty, p.min_qty), price = coalesce(p_price, p.price),
           updated_at = now()
     where p.id = p_id and (public.app_is_platform_admin(p_token) or p.tenant_id = ten);
    if not found then return query select false, 'Запчасть не найдена', null::uuid; return; end if;
    pid := p_id;
  end if;
  return query select true, 'Запчасть сохранена', pid;
end $$;

drop function if exists public.app_spare_part_delete(uuid,uuid);
create or replace function public.app_spare_part_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ten uuid;
begin
  select s.uid into uid from public.app_session_user(p_token) s;
  if uid is null then return query select false, 'Сессия недействительна'; return; end if;
  if not public.app_can(p_token, 'maintenance', 'edit') then return query select false, 'Нет прав'; return; end if;
  ten := public.app_my_tenant(p_token);
  update public.app_spare_parts set active = false, updated_at = now()
   where id = p_id and (public.app_is_platform_admin(p_token) or tenant_id = ten);
  if not found then return query select false, 'Запчасть не найдена'; return; end if;
  return query select true, 'Запчасть удалена';
end $$;

drop function if exists public.app_spare_part_move(uuid,uuid,text,numeric,text);
create or replace function public.app_spare_part_move(p_token uuid, p_part_id uuid, p_kind text, p_qty numeric, p_note text default null)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ten uuid; cur_qty numeric;
begin
  select s.uid into uid from public.app_session_user(p_token) s;
  if uid is null then return query select false, 'Сессия недействительна'; return; end if;
  if not public.app_can(p_token, 'maintenance', 'edit') then return query select false, 'Нет прав'; return; end if;
  if p_qty is null or p_qty <= 0 then return query select false, 'Укажите количество > 0'; return; end if;
  if p_kind not in ('in','out') then return query select false, 'Неверный тип движения'; return; end if;
  ten := public.app_my_tenant(p_token);
  select p.qty into cur_qty from public.app_spare_parts p
   where p.id = p_part_id and (public.app_is_platform_admin(p_token) or p.tenant_id = ten) and p.active;
  if cur_qty is null then return query select false, 'Запчасть не найдена'; return; end if;
  if p_kind = 'out' and p_qty > cur_qty then return query select false, 'Недостаточно на складе'; return; end if;
  update public.app_spare_parts set qty = qty + case when p_kind = 'in' then p_qty else -p_qty end, updated_at = now()
   where id = p_part_id;
  return query select true, case when p_kind = 'in' then 'Приход запчасти' else 'Расход запчасти' end;
end $$;

-- ============================================================
--  Расход запчастей в работе
-- ============================================================
drop function if exists public.app_mnt_parts_list(uuid,uuid);
create or replace function public.app_mnt_parts_list(p_token uuid, p_log_id uuid)
returns table (id uuid, part_id uuid, part text, unit text, qty numeric, price numeric, value numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; urole text; ten uuid;
begin
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token);
  return query
    select mp.id, mp.part_id, coalesce(mp.part_name, sp.name), sp.unit, mp.qty, mp.price, (mp.qty * mp.price)
      from public.app_mnt_parts mp
      left join public.app_spare_parts sp on sp.id = mp.part_id
     where mp.log_id = p_log_id and (urole = 'admin' or mp.tenant_id = ten)
     order by mp.created_at;
end $$;

drop function if exists public.app_mnt_part_add(uuid,uuid,uuid,numeric);
create or replace function public.app_mnt_part_add(p_token uuid, p_log_id uuid, p_part_id uuid, p_qty numeric)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ulogin text; ten uuid; sp record; l_id uuid; l_ten uuid; val numeric;
begin
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  if uid is null then return query select false, 'Сессия недействительна'; return; end if;
  if not public.app_can(p_token, 'maintenance', 'edit') then return query select false, 'Нет прав'; return; end if;
  if p_qty is null or p_qty <= 0 then return query select false, 'Укажите количество > 0'; return; end if;
  ten := public.app_my_tenant(p_token);
  select l.id, l.tenant_id into l_id, l_ten from public.app_mnt_log l
   where l.id = p_log_id and (public.app_is_platform_admin(p_token) or l.tenant_id = ten);
  if l_id is null then return query select false, 'Работа не найдена'; return; end if;
  select sp2.id, sp2.name, sp2.qty, sp2.price into sp from public.app_spare_parts sp2
   where sp2.id = p_part_id and sp2.active and (public.app_is_platform_admin(p_token) or sp2.tenant_id = ten);
  if sp.id is null then return query select false, 'Запчасть не найдена'; return; end if;
  if p_qty > sp.qty then return query select false, 'Недостаточно запчасти на складе'; return; end if;
  val := p_qty * coalesce(sp.price, 0);
  update public.app_spare_parts set qty = qty - p_qty, updated_at = now() where id = sp.id;
  insert into public.app_mnt_parts (tenant_id, log_id, part_id, part_name, qty, price, created_login)
  values (l_ten, p_log_id, sp.id, sp.name, p_qty, coalesce(sp.price,0), ulogin);
  update public.app_mnt_log set cost = coalesce(cost,0) + val, part_cost = coalesce(part_cost,0) + val where id = p_log_id;
  return query select true, 'Запчасть списана на работу';
end $$;

drop function if exists public.app_mnt_part_remove(uuid,uuid);
create or replace function public.app_mnt_part_remove(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ten uuid; rec record; val numeric;
begin
  select s.uid into uid from public.app_session_user(p_token) s;
  if uid is null then return query select false, 'Сессия недействительна'; return; end if;
  if not public.app_can(p_token, 'maintenance', 'edit') then return query select false, 'Нет прав'; return; end if;
  ten := public.app_my_tenant(p_token);
  select * into rec from public.app_mnt_parts mp
   where mp.id = p_id and (public.app_is_platform_admin(p_token) or mp.tenant_id = ten);
  if rec.id is null then return query select false, 'Запись не найдена'; return; end if;
  val := rec.qty * coalesce(rec.price, 0);
  if rec.part_id is not null then
    update public.app_spare_parts set qty = qty + rec.qty, updated_at = now() where id = rec.part_id;
  end if;
  delete from public.app_mnt_parts where id = p_id;
  update public.app_mnt_log set cost = greatest(coalesce(cost,0) - val, 0), part_cost = greatest(coalesce(part_cost,0) - val, 0) where id = rec.log_id;
  return query select true, 'Запись удалена, запчасть возвращена';
end $$;

-- ============================================================
--  Затраты по оборудованию
-- ============================================================
drop function if exists public.app_mnt_cost_by_equipment(uuid);
create or replace function public.app_mnt_cost_by_equipment(p_token uuid)
returns table (equipment_id uuid, equipment text, plans bigint, works bigint, parts_cost numeric, total_cost numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; urole text; ten uuid;
begin
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token);
  return query
    select e.id, e.name,
           (select count(*) from public.app_mnt_plans p where p.equipment_id = e.id),
           (select count(*) from public.app_mnt_log l where l.equipment_id = e.id and l.status = 'done'),
           coalesce((select sum(l.part_cost) from public.app_mnt_log l where l.equipment_id = e.id), 0),
           coalesce((select sum(l.cost) from public.app_mnt_log l where l.equipment_id = e.id), 0)
      from public.app_equipment e
     where (urole = 'admin' or e.tenant_id = ten)
       and (exists (select 1 from public.app_mnt_plans p where p.equipment_id = e.id)
         or exists (select 1 from public.app_mnt_log l where l.equipment_id = e.id))
     order by coalesce((select sum(l.cost) from public.app_mnt_log l where l.equipment_id = e.id), 0) desc;
end $$;

grant execute on function public.app_mnt_auto_schedule(uuid)                              to anon, authenticated;
grant execute on function public.app_spare_parts_list(uuid)                               to anon, authenticated;
grant execute on function public.app_spare_part_save(uuid,uuid,text,text,text,numeric,numeric,numeric) to anon, authenticated;
grant execute on function public.app_spare_part_delete(uuid,uuid)                         to anon, authenticated;
grant execute on function public.app_spare_part_move(uuid,uuid,text,numeric,text)         to anon, authenticated;
grant execute on function public.app_mnt_parts_list(uuid,uuid)                            to anon, authenticated;
grant execute on function public.app_mnt_part_add(uuid,uuid,uuid,numeric)                 to anon, authenticated;
grant execute on function public.app_mnt_part_remove(uuid,uuid)                           to anon, authenticated;
grant execute on function public.app_mnt_cost_by_equipment(uuid)                          to anon, authenticated;

-- ---------- Демо-данные (тенант A) ----------
insert into public.app_spare_parts (tenant_id, code, name, unit, qty, min_qty, price)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.code, v.name, v.unit, v.qty, v.min_qty, v.price
from (values ('SP-001','Подшипник 6205','шт',20,5,350),
             ('SP-002','Ремень приводной','шт',8,3,1200),
             ('SP-003','Смазка литиевая','кг',15,4,600)) as v(code,name,unit,qty,min_qty,price)
where not exists (
  select 1 from public.app_spare_parts p
   where p.tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001' and p.name = v.name
);

-- норма наработки для первого плана ТОиР тенанта A (если ещё не задана)
update public.app_mnt_plans set period_hours = coalesce(period_hours, 500)
 where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001' and period_hours is null;

-- ---------- Плана ТОиР: поддержка нормы наработки (period_hours) ----------
drop function if exists public.app_mnt_plan_save(uuid,uuid,uuid,text,text,integer,date,date,text,text);
create or replace function public.app_mnt_plan_save(
  p_token uuid, p_id uuid, p_equipment_id uuid, p_kind text, p_title text,
  p_period_days integer, p_last_done date, p_next_due date, p_responsible text, p_note text,
  p_period_hours numeric default null
) returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; nd date;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','master','chief') then return query select false,'Недостаточно прав'; return; end if;
  nd := coalesce(p_next_due, case when p_last_done is not null and p_period_days is not null then p_last_done + p_period_days else null end);
  if p_id is null then
    insert into public.app_mnt_plans (tenant_id, equipment_id, kind, title, period_days, period_hours, last_done, next_due, responsible, note)
    values (ten, p_equipment_id, coalesce(nullif(trim(p_kind),''),'to1'), nullif(trim(p_title),''), p_period_days, p_period_hours,
            p_last_done, nd, nullif(trim(p_responsible),''), nullif(trim(p_note),''));
  else
    update public.app_mnt_plans set equipment_id=p_equipment_id, kind=coalesce(nullif(trim(p_kind),''),kind),
      title=nullif(trim(p_title),''), period_days=p_period_days, period_hours=p_period_hours, last_done=p_last_done, next_due=nd,
      responsible=nullif(trim(p_responsible),''), note=nullif(trim(p_note),'')
     where id=p_id and (urole='admin' or tenant_id=ten);
  end if;
  return query select true,'Сохранено';
end $$;
grant execute on function public.app_mnt_plan_save(uuid,uuid,uuid,text,text,integer,date,date,text,text,numeric) to anon, authenticated;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Обслуживание','ППР по наработке и запчасти ТОиР',
   'Планы ТОиР имеют норму наработки (period_hours); app_mnt_runtime_status сравнивает наработку (сумма run_min из журнала OEE) с нормой и датой следующего ТО. Кнопка «Авто-наряд по наработке» (app_mnt_auto_schedule) создаёт запланированные наряды (app_mnt_log, status=planned) для просроченных планов без открытого наряда. Склад запчастей ТОиР — app_spare_parts (приход/расход app_spare_part_move); расход запчастей на работу — app_mnt_parts (app_mnt_part_add списывает со склада и увеличивает стоимость работы), затраты по оборудованию — app_mnt_cost_by_equipment.',
   'ТОиР ППР наработка авто-наряд запчасти spare parts стоимость обслуживания затраты')
) as v(category,question,answer,tags)
where not exists (
  select 1 from public.app_knowledge
   where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001' and question = 'ППР по наработке и запчасти ТОиР'
);
