-- ============================================================
-- 3DMP Service · 0270_abc_consol.sql  (R4 · PROP-29 — ABC-костинг и консолидация группы)
-- ABC: виды деятельности с драйверами (qty×rate → стоимость). Консолидация: элиминации
-- внутригрупповых оборотов. Идемпотентно.
-- ============================================================

create table if not exists public.app_activity_costs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants (id),
  period date not null default date_trunc('month', current_date)::date,
  activity text not null,
  driver text,
  qty numeric not null default 0,
  rate numeric not null default 0,
  cost numeric not null default 0,
  note text,
  created_at timestamptz not null default now()
);
create index if not exists app_activity_costs_idx on public.app_activity_costs (tenant_id, period);

create or replace function public.app_abc_list(p_token uuid)
returns table (id uuid, period date, activity text, driver text, qty numeric, rate numeric, cost numeric, note text)
language plpgsql security definer set search_path = public as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select a.id, a.period, a.activity, a.driver, a.qty, a.rate, a.cost, a.note
    from public.app_activity_costs a where (urole = 'admin' or a.tenant_id = ten) order by a.period desc, a.activity;
end $$;
grant execute on function public.app_abc_list(uuid) to anon, authenticated;

create or replace function public.app_abc_save(p_token uuid, p_id uuid, p_period date, p_activity text, p_driver text, p_qty numeric, p_rate numeric, p_note text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public as $$
declare urole text; ten uuid; rid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_activity), '') = '' then return query select false, 'Укажите вид деятельности'; return; end if;
  if p_id is null then
    insert into public.app_activity_costs (tenant_id, period, activity, driver, qty, rate, cost, note)
    values (ten, coalesce(p_period, date_trunc('month', current_date)::date), p_activity, p_driver, coalesce(p_qty,0), coalesce(p_rate,0), coalesce(p_qty,0)*coalesce(p_rate,0), p_note) returning id into rid;
  else
    update public.app_activity_costs set period = coalesce(p_period, period), activity = p_activity, driver = p_driver, qty = coalesce(p_qty,0), rate = coalesce(p_rate,0),
      cost = coalesce(p_qty,0)*coalesce(p_rate,0), note = p_note where id = p_id and (urole = 'admin' or tenant_id = ten) returning id into rid;
  end if;
  if rid is null then return query select false, 'Не найдено'; return; end if;
  return query select true, 'Сохранено';
end $$;
grant execute on function public.app_abc_save(uuid,uuid,date,text,text,numeric,numeric,text) to anon, authenticated;

create or replace function public.app_abc_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  delete from public.app_activity_costs where id = p_id and (urole = 'admin' or tenant_id = ten);
  return query select true, 'Удалено';
end $$;
grant execute on function public.app_abc_delete(uuid,uuid) to anon, authenticated;

-- ---------- Консолидация: элиминации внутригрупповых оборотов ----------
create table if not exists public.app_consol_elim (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants (id),
  period date not null default date_trunc('month', current_date)::date,
  from_unit text,
  to_unit text,
  amount numeric not null default 0,
  note text,
  created_at timestamptz not null default now()
);
create index if not exists app_consol_elim_idx on public.app_consol_elim (tenant_id, period);

create or replace function public.app_consol_list(p_token uuid)
returns table (id uuid, period date, from_unit text, to_unit text, amount numeric, note text)
language plpgsql security definer set search_path = public as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select e.id, e.period, e.from_unit, e.to_unit, e.amount, e.note
    from public.app_consol_elim e where (urole = 'admin' or e.tenant_id = ten) order by e.period desc;
end $$;
grant execute on function public.app_consol_list(uuid) to anon, authenticated;

create or replace function public.app_consol_save(p_token uuid, p_id uuid, p_period date, p_from text, p_to text, p_amount numeric, p_note text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public as $$
declare urole text; ten uuid; rid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if p_id is null then
    insert into public.app_consol_elim (tenant_id, period, from_unit, to_unit, amount, note)
    values (ten, coalesce(p_period, date_trunc('month', current_date)::date), p_from, p_to, coalesce(p_amount,0), p_note) returning id into rid;
  else
    update public.app_consol_elim set period = coalesce(p_period, period), from_unit = p_from, to_unit = p_to, amount = coalesce(p_amount,0), note = p_note
      where id = p_id and (urole = 'admin' or tenant_id = ten) returning id into rid;
  end if;
  if rid is null then return query select false, 'Не найдено'; return; end if;
  return query select true, 'Сохранено';
end $$;
grant execute on function public.app_consol_save(uuid,uuid,date,text,text,numeric,text) to anon, authenticated;

create or replace function public.app_consol_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  delete from public.app_consol_elim where id = p_id and (urole = 'admin' or tenant_id = ten);
  return query select true, 'Удалено';
end $$;
grant execute on function public.app_consol_delete(uuid,uuid) to anon, authenticated;
