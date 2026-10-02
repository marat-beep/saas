-- ============================================================
-- 3DMP Service · 0007_production.sql  (v1.3 — производство: наряды и операции)
-- Роли доступа: admin | owner | manager (расширим на master/operator позже).
-- Зависит от 0001..0006. public.orders НЕ трогаем.
-- ============================================================

create sequence if not exists public.app_naryad_seq;

-- ---------- Рабочие центры ----------
create table if not exists public.app_work_centers (
  id         uuid primary key default gen_random_uuid(),
  code       text unique,
  name       text not null,
  kind       text,                     -- Фрезерный | Токарный | Лазер | Сборка …
  cost_hour  numeric default 0,        -- стоимость нормочаса, ₽
  active     boolean not null default true
);

-- ---------- Нормы операций (заготовки для наряда) ----------
create table if not exists public.app_norms (
  id           uuid primary key default gen_random_uuid(),
  operation    text not null,
  machine_kind text,
  setup_min    numeric default 0,      -- подготовительно-заключительное, мин
  unit_min     numeric default 0,      -- на единицу, мин
  rate_hour    numeric default 0,      -- стоимость нормочаса, ₽
  note         text
);

-- ---------- Наряды ----------
create table if not exists public.app_naryads (
  id           uuid primary key default gen_random_uuid(),
  number       text unique not null,
  order_id     uuid references public.app_orders (id) on delete set null,
  title        text not null,
  wc_id        uuid references public.app_work_centers (id) on delete set null,
  assignee     text,                   -- логин исполнителя
  status       text not null default 'open',  -- open | in_progress | closed
  plan_hours   numeric default 0,
  fact_hours   numeric default 0,
  due_date     date,
  created_by   uuid references public.app_users (id) on delete set null,
  created_login text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index if not exists app_naryads_created_idx on public.app_naryads (created_at desc);
create index if not exists app_naryads_order_idx on public.app_naryads (order_id);

-- ---------- Операции наряда ----------
create table if not exists public.app_naryad_ops (
  id         uuid primary key default gen_random_uuid(),
  naryad_id  uuid not null references public.app_naryads (id) on delete cascade,
  seq        integer default 0,
  operation  text not null,
  worker     text,
  plan_hours numeric default 0,
  fact_hours numeric default 0,
  done       boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists app_naryad_ops_idx on public.app_naryad_ops (naryad_id);

alter table public.app_work_centers enable row level security;
alter table public.app_norms        enable row level security;
alter table public.app_naryads      enable row level security;
alter table public.app_naryad_ops   enable row level security;

-- ---------- Доступ к производству ----------
create or replace function public.app_production_allowed(p_token uuid)
returns boolean language sql security definer set search_path = public
as $$
  select exists (
    select 1 from public.app_session_user(p_token) s
    where s.urole in ('admin','owner','manager')
  );
$$;

-- ---------- Справочники ----------
create or replace function public.app_wc_list(p_token uuid)
returns table (id uuid, code text, name text, kind text, cost_hour numeric, active boolean)
language plpgsql security definer set search_path = public
as $$
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  return query select w.id, w.code, w.name, w.kind, w.cost_hour, w.active from public.app_work_centers w order by w.name;
end $$;

create or replace function public.app_norms_list(p_token uuid)
returns table (id uuid, operation text, machine_kind text, setup_min numeric, unit_min numeric, rate_hour numeric)
language plpgsql security definer set search_path = public
as $$
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  return query select n.id, n.operation, n.machine_kind, n.setup_min, n.unit_min, n.rate_hour from public.app_norms n order by n.operation;
end $$;

-- ---------- Наряды: список ----------
create or replace function public.app_naryad_list(p_token uuid)
returns table (id uuid, number text, title text, order_number text, wc_name text, assignee text,
               status text, plan_hours numeric, fact_hours numeric, due_date date, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  return query
    select n.id, n.number, n.title, o.number, w.name, n.assignee, n.status,
           n.plan_hours, n.fact_hours, n.due_date, n.created_at
    from public.app_naryads n
    left join public.app_orders o on o.id = n.order_id
    left join public.app_work_centers w on w.id = n.wc_id
    order by n.created_at desc;
end $$;

-- ---------- Создать наряд ----------
create or replace function public.app_naryad_create(
  p_token uuid, p_order_id uuid, p_title text, p_wc_id uuid, p_assignee text, p_due_date date
) returns table (id uuid, number text)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; ulogin text; nid uuid; nnum text; target uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  if coalesce(trim(p_title), '') = '' then raise exception 'Укажите название наряда'; end if;

  nnum := 'NAR-' || lpad(nextval('public.app_naryad_seq')::text, 5, '0');
  insert into public.app_naryads (number, order_id, title, wc_id, assignee, status, created_by, created_login)
  values (nnum, p_order_id, trim(p_title), p_wc_id, nullif(trim(p_assignee), ''), 'open', uid, ulogin)
  returning app_naryads.id into nid;

  perform public.app_notif_roles(array['admin','manager','owner'], 'Новый наряд ' || nnum, trim(p_title), 'apps/production/index.html');
  if nullif(trim(p_assignee), '') is not null then
    select u.id into target from public.app_users u where lower(u.login) = lower(trim(p_assignee)) and u.active limit 1;
    if target is not null then
      perform public.app_notif_send(target, 'Вам назначен наряд ' || nnum, trim(p_title), 'apps/production/index.html');
    end if;
  end if;
  return query select nid, nnum;
end $$;

-- ---------- Наряд: карточка + операции ----------
create or replace function public.app_naryad_get(p_token uuid, p_id uuid)
returns table (id uuid, number text, title text, order_id uuid, order_number text, wc_name text, assignee text,
               status text, plan_hours numeric, fact_hours numeric, due_date date, created_login text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  return query select n.id, n.number, n.title, n.order_id, o.number, w.name, n.assignee,
    n.status, n.plan_hours, n.fact_hours, n.due_date, n.created_login, n.created_at
    from public.app_naryads n
    left join public.app_orders o on o.id = n.order_id
    left join public.app_work_centers w on w.id = n.wc_id
    where n.id = p_id;
end $$;

create or replace function public.app_naryad_ops(p_token uuid, p_id uuid)
returns table (id uuid, seq integer, operation text, worker text, plan_hours numeric, fact_hours numeric, done boolean)
language plpgsql security definer set search_path = public
as $$
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  return query select op.id, op.seq, op.operation, op.worker, op.plan_hours, op.fact_hours, op.done
    from public.app_naryad_ops op where op.naryad_id = p_id order by op.seq, op.created_at;
end $$;

-- ---------- Добавить операцию ----------
create or replace function public.app_naryad_add_op(
  p_token uuid, p_naryad_id uuid, p_operation text, p_worker text, p_plan_hours numeric
) returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare seqn integer; nid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select n.id into nid from public.app_naryads n where n.id = p_naryad_id;
  if nid is null then return query select false,'Наряд не найден'; return; end if;
  if coalesce(trim(p_operation),'') = '' then return query select false,'Укажите операцию'; return; end if;

  select coalesce(max(op.seq),0)+1 into seqn from public.app_naryad_ops op where op.naryad_id = p_naryad_id;
  insert into public.app_naryad_ops (naryad_id, seq, operation, worker, plan_hours)
  values (p_naryad_id, seqn, trim(p_operation), nullif(trim(p_worker),''), coalesce(p_plan_hours,0));

  update public.app_naryads n set plan_hours = (select coalesce(sum(op.plan_hours),0) from public.app_naryad_ops op where op.naryad_id = n.id),
    status = case when n.status = 'open' then 'in_progress' else n.status end, updated_at = now()
   where n.id = p_naryad_id;
  return query select true,'Операция добавлена';
end $$;

-- ---------- Отметить операцию выполненной ----------
create or replace function public.app_naryad_op_done(p_token uuid, p_op_id uuid, p_fact_hours numeric, p_done boolean)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare nid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select op.naryad_id into nid from public.app_naryad_ops op where op.id = p_op_id;
  if nid is null then return query select false,'Операция не найдена'; return; end if;
  update public.app_naryad_ops set done = coalesce(p_done, true), fact_hours = coalesce(p_fact_hours, fact_hours) where id = p_op_id;
  update public.app_naryads n set fact_hours = (select coalesce(sum(op.fact_hours),0) from public.app_naryad_ops op where op.naryad_id = n.id),
    updated_at = now() where n.id = nid;
  return query select true,'Обновлено';
end $$;

-- ---------- Закрыть наряд ----------
create or replace function public.app_naryad_close(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare ulogin text; nnum text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.ulogin into ulogin from public.app_session_user(p_token) s;
  select n.number into nnum from public.app_naryads n where n.id = p_id;
  if nnum is null then return query select false,'Наряд не найден'; return; end if;
  update public.app_naryads n set status = 'closed', updated_at = now(),
    fact_hours = (select coalesce(sum(op.fact_hours),0) from public.app_naryad_ops op where op.naryad_id = n.id)
   where n.id = p_id;
  perform public.app_notif_roles(array['admin','manager','owner'], 'Наряд ' || nnum || ' закрыт', 'Закрыл: ' || coalesce(ulogin,''), 'apps/production/index.html');
  return query select true,'Наряд закрыт';
end $$;

grant execute on function public.app_production_allowed(uuid) to anon, authenticated;
grant execute on function public.app_wc_list(uuid) to anon, authenticated;
grant execute on function public.app_norms_list(uuid) to anon, authenticated;
grant execute on function public.app_naryad_list(uuid) to anon, authenticated;
grant execute on function public.app_naryad_create(uuid,uuid,text,uuid,text,date) to anon, authenticated;
grant execute on function public.app_naryad_get(uuid,uuid) to anon, authenticated;
grant execute on function public.app_naryad_ops(uuid,uuid) to anon, authenticated;
grant execute on function public.app_naryad_add_op(uuid,uuid,text,text,numeric) to anon, authenticated;
grant execute on function public.app_naryad_op_done(uuid,uuid,numeric,boolean) to anon, authenticated;
grant execute on function public.app_naryad_close(uuid,uuid) to anon, authenticated;

-- ---------- Демо-данные ----------
insert into public.app_work_centers (code, name, kind, cost_hour)
select v.code, v.name, v.kind, v.cost_hour from (values
  ('WC-01','Фрезерный ЧПУ DMU-50','Фрезерный', 3500),
  ('WC-02','Токарный с ЧПУ','Токарный', 3000),
  ('WC-03','Лазерный комплекс','Лазер', 4200),
  ('WC-04','Слесарная/сборка','Сборка', 1800)
) as v(code,name,kind,cost_hour)
where not exists (select 1 from public.app_work_centers);

insert into public.app_norms (operation, machine_kind, setup_min, unit_min, rate_hour)
select v.operation, v.machine_kind, v.setup_min, v.unit_min, v.rate_hour from (values
  ('Фрезеровка черновая','Фрезерный', 20, 12, 3500),
  ('Фрезеровка чистовая','Фрезерный', 15, 8, 3500),
  ('Токарная обработка','Токарный', 18, 10, 3000),
  ('Лазерная резка','Лазер', 10, 3, 4200),
  ('Слесарная доводка','Сборка', 5, 15, 1800)
) as v(operation,machine_kind,setup_min,unit_min,rate_hour)
where not exists (select 1 from public.app_norms);
