-- ============================================================
-- 3DMP Service · 0012_quality.sql  (v1.7 — качество и паспорт изделия)
-- ОТК-чек-листы, дефекты, паспорт изделия. Изоляция по tenant.
-- Роли: admin/owner/manager. Зависит от 0001..0011. public.orders НЕ трогаем.
-- ============================================================

create sequence if not exists public.app_qc_seq;
create sequence if not exists public.app_passport_seq;

-- ---------- Чек-листы ОТК ----------
create table if not exists public.app_qc_checks (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  number        text unique not null,
  naryad_id     uuid references public.app_naryads (id) on delete set null,
  order_id      uuid references public.app_orders (id) on delete set null,
  product       text,
  status        text not null default 'draft',   -- draft | passed | failed
  inspector     text,
  note          text,
  created_by    uuid references public.app_users (id) on delete set null,
  created_login text,
  created_at    timestamptz not null default now(),
  checked_at    timestamptz
);
create index if not exists app_qc_tenant_idx on public.app_qc_checks (tenant_id, created_at desc);

create table if not exists public.app_qc_lines (
  id       uuid primary key default gen_random_uuid(),
  check_id uuid not null references public.app_qc_checks (id) on delete cascade,
  name     text not null,
  norm     text,
  value    text,
  result   text not null default 'ok'     -- ok | no
);
create index if not exists app_qc_lines_idx on public.app_qc_lines (check_id);

-- ---------- Дефекты ----------
create table if not exists public.app_defects (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid references public.tenants (id),
  check_id   uuid references public.app_qc_checks (id) on delete set null,
  title      text not null,
  qty        numeric default 1,
  severity   text not null default 'minor',   -- minor | major | critical
  status     text not null default 'open',    -- open | resolved
  note       text,
  by_login   text,
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);
create index if not exists app_defects_tenant_idx on public.app_defects (tenant_id, created_at desc);

-- ---------- Паспорт изделия ----------
create table if not exists public.app_passports (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  number        text unique not null,
  order_id      uuid references public.app_orders (id) on delete set null,
  product       text not null,
  qc_check_id   uuid references public.app_qc_checks (id) on delete set null,
  data          jsonb default '{}'::jsonb,
  created_by    uuid references public.app_users (id) on delete set null,
  created_login text,
  created_at    timestamptz not null default now()
);
create index if not exists app_passports_tenant_idx on public.app_passports (tenant_id, created_at desc);

alter table public.app_qc_checks enable row level security;
alter table public.app_qc_lines  enable row level security;
alter table public.app_defects   enable row level security;
alter table public.app_passports enable row level security;

-- ---------- ОТК: список ----------
drop function if exists public.app_qc_list(uuid);
create or replace function public.app_qc_list(p_token uuid)
returns table (id uuid, number text, product text, status text, inspector text, naryad_number text,
               order_number text, lines_count bigint, defects_count bigint, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select c.id, c.number, c.product, c.status, c.inspector, n.number, o.number,
           (select count(*) from public.app_qc_lines l where l.check_id = c.id),
           (select count(*) from public.app_defects d where d.check_id = c.id),
           c.created_at
    from public.app_qc_checks c
    left join public.app_naryads n on n.id = c.naryad_id
    left join public.app_orders o on o.id = c.order_id
    where (urole = 'admin' or c.tenant_id = ten)
    order by c.created_at desc;
end $$;

-- ---------- ОТК: создать ----------
create or replace function public.app_qc_create(p_token uuid, p_naryad_id uuid, p_order_id uuid, p_product text, p_inspector text)
returns table (id uuid, number text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ulogin text; ten uuid; cid uuid; cnum text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  cnum := 'QCK-' || lpad(nextval('public.app_qc_seq')::text, 5, '0');
  insert into public.app_qc_checks (tenant_id, number, naryad_id, order_id, product, inspector, created_by, created_login)
  values (ten, cnum, p_naryad_id, p_order_id, nullif(trim(p_product),''), nullif(trim(p_inspector),''), uid, ulogin)
  returning app_qc_checks.id into cid;
  return query select cid, cnum;
end $$;

-- ---------- ОТК: позиции ----------
create or replace function public.app_qc_add_line(p_token uuid, p_check_id uuid, p_name text, p_norm text, p_value text, p_result text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; cid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select c.id into cid from public.app_qc_checks c where c.id = p_check_id and (urole='admin' or c.tenant_id = ten);
  if cid is null then return query select false,'Чек-лист не найден'; return; end if;
  if coalesce(trim(p_name),'') = '' then return query select false,'Укажите параметр'; return; end if;
  insert into public.app_qc_lines (check_id, name, norm, value, result)
  values (cid, trim(p_name), nullif(trim(p_norm),''), nullif(trim(p_value),''), coalesce(nullif(trim(p_result),''),'ok'));
  return query select true,'Позиция добавлена';
end $$;

create or replace function public.app_qc_lines_list(p_token uuid, p_check_id uuid)
returns table (id uuid, name text, norm text, value text, result text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select l.id, l.name, l.norm, l.value, l.result
    from public.app_qc_lines l join public.app_qc_checks c on c.id = l.check_id
    where l.check_id = p_check_id and (urole='admin' or c.tenant_id = ten) order by l.id;
end $$;

-- ---------- ОТК: статус (passed/failed) ----------
create or replace function public.app_qc_set_status(p_token uuid, p_check_id uuid, p_status text, p_note text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; cnum text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select c.number into cnum from public.app_qc_checks c where c.id = p_check_id and (urole='admin' or c.tenant_id = ten);
  if cnum is null then return query select false,'Чек-лист не найден'; return; end if;
  update public.app_qc_checks set status = p_status, note = nullif(trim(p_note),''), checked_at = now() where id = p_check_id;
  if p_status = 'failed' then
    perform public.app_notif_roles_t(ten, array['admin','manager','owner'], 'ОТК: брак по ' || cnum, coalesce(p_note,''), 'apps/qc/index.html');
  end if;
  return query select true, case when p_status = 'passed' then 'Принято' else 'Зафиксирован брак' end;
end $$;

-- ---------- Дефекты ----------
create or replace function public.app_defect_list(p_token uuid)
returns table (id uuid, title text, qty numeric, severity text, status text, note text, by_login text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select d.id, d.title, d.qty, d.severity, d.status, d.note, d.by_login, d.created_at
    from public.app_defects d where (urole='admin' or d.tenant_id = ten) order by d.created_at desc;
end $$;

create or replace function public.app_defect_add(p_token uuid, p_check_id uuid, p_title text, p_qty numeric, p_severity text, p_note text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ulogin text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.ulogin into ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_title),'') = '' then return query select false,'Опишите дефект'; return; end if;
  insert into public.app_defects (tenant_id, check_id, title, qty, severity, note, by_login)
  values (ten, p_check_id, trim(p_title), coalesce(p_qty,1), coalesce(nullif(trim(p_severity),''),'minor'), nullif(trim(p_note),''), ulogin);
  if p_severity = 'critical' then
    perform public.app_notif_roles_t(ten, array['admin','manager','owner'], 'Критический дефект', trim(p_title), 'apps/qc/index.html');
  end if;
  return query select true,'Дефект зарегистрирован';
end $$;

create or replace function public.app_defect_resolve(p_token uuid, p_id uuid, p_note text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  update public.app_defects set status='resolved', note = coalesce(nullif(trim(p_note),''), note), resolved_at = now()
   where id = p_id and (urole='admin' or tenant_id = ten);
  return query select true,'Дефект закрыт';
end $$;

-- ---------- Паспорт изделия ----------
create or replace function public.app_passport_create(p_token uuid, p_order_id uuid, p_product text, p_qc_check_id uuid, p_data jsonb)
returns table (id uuid, number text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ulogin text; ten uuid; pid uuid; pnum text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_product),'') = '' then raise exception 'Укажите изделие'; end if;
  pnum := 'PAS-' || lpad(nextval('public.app_passport_seq')::text, 5, '0');
  insert into public.app_passports (tenant_id, number, order_id, product, qc_check_id, data, created_by, created_login)
  values (ten, pnum, p_order_id, trim(p_product), p_qc_check_id, coalesce(p_data,'{}'::jsonb), uid, ulogin)
  returning app_passports.id into pid;
  return query select pid, pnum;
end $$;

drop function if exists public.app_passport_list(uuid);
create or replace function public.app_passport_list(p_token uuid)
returns table (id uuid, number text, product text, order_number text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select p.id, p.number, p.product, o.number, p.created_at
    from public.app_passports p left join public.app_orders o on o.id = p.order_id
    where (urole='admin' or p.tenant_id = ten) order by p.created_at desc;
end $$;

drop function if exists public.app_passport_get(uuid, uuid);
create or replace function public.app_passport_get(p_token uuid, p_id uuid)
returns table (id uuid, number text, product text, order_number text, data jsonb, created_login text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select p.id, p.number, p.product, o.number, p.data, p.created_login, p.created_at
    from public.app_passports p left join public.app_orders o on o.id = p.order_id
    where p.id = p_id and (urole='admin' or p.tenant_id = ten);
end $$;

grant execute on function public.app_qc_list(uuid) to anon, authenticated;
grant execute on function public.app_qc_create(uuid,uuid,uuid,text,text) to anon, authenticated;
grant execute on function public.app_qc_add_line(uuid,uuid,text,text,text,text) to anon, authenticated;
grant execute on function public.app_qc_lines_list(uuid,uuid) to anon, authenticated;
grant execute on function public.app_qc_set_status(uuid,uuid,text,text) to anon, authenticated;
grant execute on function public.app_defect_list(uuid) to anon, authenticated;
grant execute on function public.app_defect_add(uuid,uuid,text,numeric,text,text) to anon, authenticated;
grant execute on function public.app_defect_resolve(uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_passport_create(uuid,uuid,text,uuid,jsonb) to anon, authenticated;
grant execute on function public.app_passport_list(uuid) to anon, authenticated;
grant execute on function public.app_passport_get(uuid,uuid) to anon, authenticated;
