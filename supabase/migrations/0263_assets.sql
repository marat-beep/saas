-- ============================================================
-- 3DMP Service · 0263_assets.sql  (R4 · PROP-20 — основные средства и амортизация)
-- Таблица ОС + RPC list/save/delete и начисление амортизации (линейно) за период. Идемпотентно.
-- ============================================================

create table if not exists public.app_fixed_assets (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants (id),
  code text,
  name text not null,
  grp text,
  cost numeric not null default 0,
  salvage numeric not null default 0,
  life_months int not null default 36,
  in_date date,
  accumulated numeric not null default 0,
  status text not null default 'active',  -- active|written_off
  created_at timestamptz not null default now()
);
create index if not exists app_fixed_assets_idx on public.app_fixed_assets (tenant_id, status);

create or replace function public.app_fa_list(p_token uuid)
returns table (id uuid, code text, name text, grp text, cost numeric, salvage numeric, life_months int, in_date date, accumulated numeric, residual numeric, status text)
language plpgsql security definer set search_path = public as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select a.id, a.code, a.name, a.grp, a.cost, a.salvage, a.life_months, a.in_date, a.accumulated,
      greatest(a.cost - a.accumulated, 0), a.status
    from public.app_fixed_assets a where (urole = 'admin' or a.tenant_id = ten) order by a.in_date nulls last, a.name;
end $$;
grant execute on function public.app_fa_list(uuid) to anon, authenticated;

create or replace function public.app_fa_save(p_token uuid, p_id uuid, p_code text, p_name text, p_grp text, p_cost numeric, p_salvage numeric, p_life_months int, p_in_date date)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public as $$
declare urole text; ten uuid; rid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_name), '') = '' then return query select false, 'Укажите наименование'; return; end if;
  if p_id is null then
    insert into public.app_fixed_assets (tenant_id, code, name, grp, cost, salvage, life_months, in_date, accumulated, status)
    values (ten, p_code, p_name, p_grp, coalesce(p_cost, 0), coalesce(p_salvage, 0), greatest(coalesce(p_life_months, 36), 1), p_in_date, 0, 'active') returning id into rid;
  else
    update public.app_fixed_assets set code = p_code, name = p_name, grp = p_grp, cost = coalesce(p_cost, cost),
      salvage = coalesce(p_salvage, salvage), life_months = greatest(coalesce(p_life_months, life_months), 1), in_date = p_in_date
      where id = p_id and (urole = 'admin' or tenant_id = ten) returning id into rid;
  end if;
  if rid is null then return query select false, 'Не найдено'; return; end if;
  return query select true, 'Сохранено';
end $$;
grant execute on function public.app_fa_save(uuid,uuid,text,text,text,numeric,numeric,int,date) to anon, authenticated;

create or replace function public.app_fa_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  delete from public.app_fixed_assets where id = p_id and (urole = 'admin' or tenant_id = ten);
  return query select true, 'Удалено';
end $$;
grant execute on function public.app_fa_delete(uuid,uuid) to anon, authenticated;

create or replace function public.app_fa_amortize(p_token uuid, p_period date)
returns table (ok boolean, message text, charged numeric)
language plpgsql security definer set search_path = public as $$
declare urole text; ten uuid; a record; mon numeric; newacc numeric; total numeric := 0;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  for a in select * from public.app_fixed_assets
      where (urole = 'admin' or tenant_id = ten) and status = 'active' and (in_date is null or in_date <= coalesce(p_period, current_date))
  loop
    mon := round(greatest(a.cost - a.salvage, 0) / greatest(a.life_months, 1), 2);
    newacc := least(a.accumulated + mon, greatest(a.cost - a.salvage, 0));
    update public.app_fixed_assets set accumulated = newacc,
      status = case when newacc >= greatest(a.cost - a.salvage, 0) then 'written_off' else 'active' end
      where id = a.id;
    total := total + (newacc - a.accumulated);
  end loop;
  return query select true, 'Амортизация начислена', round(total, 2);
end $$;
grant execute on function public.app_fa_amortize(uuid,date) to anon, authenticated;
