-- ============================================================
-- 3DMP Service · 0021_mes.sql  (v6.0 — MES-ядро, диспетчеризация)
-- Оперативные задания по рабочим центрам (канбан производства).
-- Изоляция по tenant. Роли: admin/owner/manager. Зависит от 0001..0020.
-- ============================================================

create sequence if not exists public.app_mes_seq;

create table if not exists public.app_mes_tasks (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid references public.tenants (id),
  number       text unique not null,
  wc_id        uuid references public.app_work_centers (id) on delete set null,
  naryad_id    uuid references public.app_naryads (id) on delete set null,
  title        text not null,
  status       text not null default 'queued',  -- queued | running | paused | done
  priority     text not null default 'normal',  -- low | normal | high
  operator     text,
  started_at   timestamptz,
  finished_at  timestamptz,
  note         text,
  created_by   uuid references public.app_users (id) on delete set null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index if not exists app_mes_tenant_idx on public.app_mes_tasks (tenant_id, created_at desc);

alter table public.app_mes_tasks enable row level security;

-- ---------- Доска ----------
create or replace function public.app_mes_board(p_token uuid)
returns table (id uuid, number text, title text, wc_name text, naryad_number text, status text, priority text,
               operator text, started_at timestamptz, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select m.id, m.number, m.title, w.name, n.number, m.status, m.priority, m.operator, m.started_at, m.created_at
    from public.app_mes_tasks m
    left join public.app_work_centers w on w.id = m.wc_id
    left join public.app_naryads n on n.id = m.naryad_id
    where (urole='admin' or m.tenant_id = ten)
    order by case m.status when 'running' then 0 when 'paused' then 1 when 'queued' then 2 else 3 end,
             case m.priority when 'high' then 0 when 'normal' then 1 else 2 end, m.created_at;
end $$;

-- ---------- Создать задание ----------
create or replace function public.app_mes_create(p_token uuid, p_wc_id uuid, p_naryad_id uuid, p_title text, p_priority text, p_operator text)
returns table (id uuid, number text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ten uuid; mid uuid; mnum text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.uid into uid from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_title),'') = '' then raise exception 'Укажите задание'; end if;
  mnum := 'MES-' || lpad(nextval('public.app_mes_seq')::text, 5, '0');
  insert into public.app_mes_tasks (tenant_id, number, wc_id, naryad_id, title, priority, operator, created_by)
  values (ten, mnum, p_wc_id, p_naryad_id, trim(p_title), coalesce(nullif(trim(p_priority),''),'normal'), nullif(trim(p_operator),''), uid)
  returning app_mes_tasks.id into mid;
  return query select mid, mnum;
end $$;

-- ---------- Сменить статус ----------
create or replace function public.app_mes_set_status(p_token uuid, p_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; mnum text; ulogin text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select m.number into mnum from public.app_mes_tasks m where m.id = p_id and (urole='admin' or m.tenant_id = ten);
  if mnum is null then return query select false,'Задание не найдено'; return; end if;

  update public.app_mes_tasks set status = p_status,
    started_at = case when p_status='running' and started_at is null then now() else started_at end,
    finished_at = case when p_status='done' then now() else finished_at end,
    updated_at = now()
   where id = p_id;

  if p_status = 'done' then
    perform public.app_notif_roles_t(ten, array['admin','manager','owner'], 'Задание ' || mnum || ' выполнено', 'Выполнил: ' || coalesce(ulogin,''), 'apps/mes/index.html');
  end if;
  return query select true, 'Статус обновлён';
end $$;

create or replace function public.app_mes_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  delete from public.app_mes_tasks where id = p_id and (urole='admin' or tenant_id = ten);
  return query select true,'Задание удалено';
end $$;

-- ---------- KPI ----------
create or replace function public.app_mes_kpi(p_token uuid)
returns table (queued bigint, running bigint, paused bigint, done bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select
    (select count(*) from public.app_mes_tasks m where m.status='queued' and (urole='admin' or m.tenant_id=ten)),
    (select count(*) from public.app_mes_tasks m where m.status='running' and (urole='admin' or m.tenant_id=ten)),
    (select count(*) from public.app_mes_tasks m where m.status='paused' and (urole='admin' or m.tenant_id=ten)),
    (select count(*) from public.app_mes_tasks m where m.status='done' and (urole='admin' or m.tenant_id=ten));
end $$;

grant execute on function public.app_mes_board(uuid) to anon, authenticated;
grant execute on function public.app_mes_create(uuid,uuid,uuid,text,text,text) to anon, authenticated;
grant execute on function public.app_mes_set_status(uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_mes_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_mes_kpi(uuid) to anon, authenticated;
