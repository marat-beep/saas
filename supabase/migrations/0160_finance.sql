-- ============================================================
-- 3DMP Service · 0160_finance.sql  (W18a — Финансы и управленческий учёт, FRP)
-- Бюджеты/ЦФО и план-факт, платёжный календарь (app_cash_plan), финансы KPI, себестоимость.
-- ВАЖНО: app_payments/app_payment_* и app_finance_kpi уже существуют (платежи по счетам) — не трогаем.
-- Идемпотентно. Зависит от 0001..0159.
-- ============================================================

-- ---------- Бюджеты ----------
create table if not exists public.app_budgets (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  name          text not null,
  year          integer not null default extract(year from current_date)::int,
  cfo           text,
  status        text not null default 'draft',   -- draft|approved|closed
  note          text,
  created_login text,
  created_at    timestamptz not null default now()
);
alter table public.app_budgets enable row level security;

create table if not exists public.app_budget_lines (
  id           uuid primary key default gen_random_uuid(),
  budget_id    uuid not null references public.app_budgets (id) on delete cascade,
  category     text not null,
  item         text,
  month        integer not null default 1,   -- 1..12
  amount_plan  numeric not null default 0,
  amount_fact  numeric not null default 0,
  note         text
);
create index if not exists app_budget_lines_idx on public.app_budget_lines (budget_id, category, month);
alter table public.app_budget_lines enable row level security;

-- ---------- Платёжный календарь (собственный, не путать с app_payments = платежи по счетам) ----------
create table if not exists public.app_cash_plan (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  kind          text not null default 'out',     -- in|out
  counterparty  text,
  amount        numeric not null default 0,
  due_date      date,
  status        text not null default 'planned',  -- planned|paid|overdue|cancelled
  doc           text,
  note          text,
  created_login text,
  created_at    timestamptz not null default now(),
  paid_at       timestamptz
);
create index if not exists app_cash_plan_idx on public.app_cash_plan (tenant_id, status, due_date);
alter table public.app_cash_plan enable row level security;

-- ================= RPC: бюджеты =================
create or replace function public.app_budgets_list(p_token uuid)
returns table (id uuid, name text, year integer, cfo text, status text, plan_total numeric, fact_total numeric, lines bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query
    select b.id, b.name, b.year, b.cfo, b.status,
           coalesce((select sum(l.amount_plan) from public.app_budget_lines l where l.budget_id = b.id),0),
           coalesce((select sum(l.amount_fact) from public.app_budget_lines l where l.budget_id = b.id),0),
           (select count(*) from public.app_budget_lines l where l.budget_id = b.id)
      from public.app_budgets b where adm or b.tenant_id = ten order by b.year desc, b.name;
end $$;

create or replace function public.app_budget_save(p_token uuid, p_id uuid, p_name text, p_year integer, p_cfo text, p_status text, p_note text)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; uname text; newid uuid; st text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid; return; end if;
  select u.tenant_id, s.ulogin into ten, uname from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  if coalesce(trim(p_name),'') = '' then return query select false,'Укажите название бюджета', null::uuid; return; end if;
  st := coalesce(nullif(trim(p_status),''),'draft');
  if st not in ('draft','approved','closed') then return query select false,'Недопустимый статус', null::uuid; return; end if;
  if p_id is null then
    insert into public.app_budgets (tenant_id, name, year, cfo, status, note, created_login)
    values (ten, left(trim(p_name),160), coalesce(p_year, extract(year from current_date)::int), nullif(trim(p_cfo),''), st, nullif(trim(p_note),''), uname)
    returning app_budgets.id into newid;
    return query select true,'Бюджет создан', newid;
  else
    update public.app_budgets b set name = left(trim(p_name),160), year = coalesce(p_year, b.year), cfo = nullif(trim(p_cfo),''),
           status = st, note = nullif(trim(p_note),'')
     where b.id = p_id and (public.app_is_platform_admin(p_token) or b.tenant_id = ten)
     returning b.id into newid;
    if newid is null then return query select false,'Бюджет не найден', null::uuid; return; end if;
    return query select true,'Бюджет сохранён', newid;
  end if;
end $$;

create or replace function public.app_budget_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; n integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten := public.app_my_tenant(p_token);
  delete from public.app_budgets b where b.id = p_id and (public.app_is_platform_admin(p_token) or b.tenant_id = ten);
  get diagnostics n = row_count;
  if n = 0 then return query select false,'Бюджет не найден'; return; end if;
  return query select true,'Бюджет удалён';
end $$;

create or replace function public.app_budget_lines_list(p_token uuid, p_budget_id uuid)
returns table (id uuid, category text, item text, month integer, amount_plan numeric, amount_fact numeric, note text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query
    select l.id, l.category, l.item, l.month, l.amount_plan, l.amount_fact, l.note
      from public.app_budget_lines l join public.app_budgets b on b.id = l.budget_id
     where l.budget_id = p_budget_id and (adm or b.tenant_id = ten)
     order by l.category, l.month, l.item;
end $$;

create or replace function public.app_budget_line_save(p_token uuid, p_id uuid, p_budget_id uuid, p_category text, p_item text, p_month integer, p_plan numeric, p_fact numeric, p_note text)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; newid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid; return; end if;
  ten := public.app_my_tenant(p_token);
  if not exists (select 1 from public.app_budgets b where b.id = p_budget_id and (public.app_is_platform_admin(p_token) or b.tenant_id = ten)) then
    return query select false,'Бюджет не найден', null::uuid; return;
  end if;
  if coalesce(trim(p_category),'') = '' then return query select false,'Укажите статью', null::uuid; return; end if;
  if p_month is not null and (p_month < 1 or p_month > 12) then return query select false,'Месяц: 1..12', null::uuid; return; end if;
  if p_id is null then
    insert into public.app_budget_lines (budget_id, category, item, month, amount_plan, amount_fact, note)
    values (p_budget_id, left(trim(p_category),120), nullif(trim(p_item),''), coalesce(p_month,1), coalesce(p_plan,0), coalesce(p_fact,0), nullif(trim(p_note),''))
    returning app_budget_lines.id into newid;
    return query select true,'Строка добавлена', newid;
  else
    update public.app_budget_lines l set category = left(trim(p_category),120), item = nullif(trim(p_item),''), month = coalesce(p_month, l.month),
           amount_plan = coalesce(p_plan, l.amount_plan), amount_fact = coalesce(p_fact, l.amount_fact), note = nullif(trim(p_note),'')
     where l.id = p_id and exists (select 1 from public.app_budgets b where b.id = l.budget_id and (public.app_is_platform_admin(p_token) or b.tenant_id = ten))
     returning l.id into newid;
    if newid is null then return query select false,'Строка не найдена', null::uuid; return; end if;
    return query select true,'Строка сохранена', newid;
  end if;
end $$;

create or replace function public.app_budget_line_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; n integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten := public.app_my_tenant(p_token);
  delete from public.app_budget_lines l using public.app_budgets b
   where l.id = p_id and b.id = l.budget_id and (public.app_is_platform_admin(p_token) or b.tenant_id = ten);
  get diagnostics n = row_count;
  if n = 0 then return query select false,'Строка не найдена'; return; end if;
  return query select true,'Строка удалена';
end $$;

create or replace function public.app_budget_plan_fact(p_token uuid, p_budget_id uuid)
returns table (category text, amount_plan numeric, amount_fact numeric, delta numeric, pct numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query
    select l.category, sum(l.amount_plan), sum(l.amount_fact), sum(l.amount_fact) - sum(l.amount_plan),
           case when sum(l.amount_plan) > 0 then round(sum(l.amount_fact) / sum(l.amount_plan) * 100, 1) end
      from public.app_budget_lines l join public.app_budgets b on b.id = l.budget_id
     where l.budget_id = p_budget_id and (adm or b.tenant_id = ten)
     group by l.category
     order by l.category;
end $$;

create or replace function public.app_budget_kpi(p_token uuid, p_budget_id uuid)
returns table (plan_total numeric, fact_total numeric, delta numeric, pct numeric, lines bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean; pl numeric; fa numeric;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  select coalesce(sum(l.amount_plan),0), coalesce(sum(l.amount_fact),0) into pl, fa
    from public.app_budget_lines l join public.app_budgets b on b.id = l.budget_id
   where l.budget_id = p_budget_id and (adm or b.tenant_id = ten);
  return query select pl, fa, fa - pl,
    case when pl > 0 then round(fa / pl * 100, 1) end,
    (select count(*) from public.app_budget_lines l where l.budget_id = p_budget_id);
end $$;

create or replace function public.app_budget_from_invoices(p_token uuid, p_budget_id uuid, p_year integer, p_month integer)
returns table (ok boolean, message text, amount numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean; amt numeric; l_id uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён',0; return; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  if not exists (select 1 from public.app_budgets b where b.id = p_budget_id and (adm or b.tenant_id = ten)) then
    return query select false,'Бюджет не найден',0; return;
  end if;
  select coalesce(sum(i.amount),0) into amt from public.app_invoices i
   where (adm or i.tenant_id = ten) and i.status = 'paid'
     and extract(year from coalesce(i.paid_at, i.created_at)) = p_year
     and extract(month from coalesce(i.paid_at, i.created_at)) = p_month;
  select l.id into l_id from public.app_budget_lines l where l.budget_id = p_budget_id and l.category = 'Продажи' and l.month = p_month limit 1;
  if l_id is null then
    insert into public.app_budget_lines (budget_id, category, item, month, amount_plan, amount_fact)
    values (p_budget_id, 'Продажи', 'Оплаченные счета', p_month, 0, amt);
  else
    update public.app_budget_lines set amount_fact = amt where id = l_id;
  end if;
  return query select true, 'Факт «Продажи» за ' || p_month || '.' || p_year || ': ' || amt, amt;
end $$;

-- ================= RPC: платёжный календарь (app_cash_plan) =================
create or replace function public.app_cash_list(p_token uuid, p_kind text default null, p_status text default null)
returns table (id uuid, kind text, counterparty text, amount numeric, due_date date, status text, doc text, note text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean; k text; st text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  k := nullif(trim(coalesce(p_kind,'')),''); st := nullif(trim(coalesce(p_status,'')),'');
  return query
    select p.id, p.kind, p.counterparty, p.amount, p.due_date, p.status, p.doc, p.note
      from public.app_cash_plan p where (adm or p.tenant_id = ten)
       and (k is null or p.kind = k) and (st is null or p.status = st)
     order by p.due_date nulls last;
end $$;

create or replace function public.app_cash_save(p_token uuid, p_id uuid, p_kind text, p_counterparty text, p_amount numeric, p_due_date date, p_status text, p_doc text, p_note text)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; uname text; newid uuid; k text; st text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid; return; end if;
  select u.tenant_id, s.ulogin into ten, uname from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  k := coalesce(nullif(trim(p_kind),''),'out');
  if k not in ('in','out') then return query select false,'Тип: in/out', null::uuid; return; end if;
  st := coalesce(nullif(trim(p_status),''),'planned');
  if st not in ('planned','paid','overdue','cancelled') then return query select false,'Недопустимый статус', null::uuid; return; end if;
  if p_id is null then
    insert into public.app_cash_plan (tenant_id, kind, counterparty, amount, due_date, status, doc, note, created_login)
    values (ten, k, nullif(trim(p_counterparty),''), coalesce(p_amount,0), p_due_date, st, nullif(trim(p_doc),''), nullif(trim(p_note),''), uname)
    returning app_cash_plan.id into newid;
    return query select true,'Платёж создан', newid;
  else
    update public.app_cash_plan p set kind = k, counterparty = nullif(trim(p_counterparty),''), amount = coalesce(p_amount, p.amount),
           due_date = p_due_date, status = st, doc = nullif(trim(p_doc),''), note = nullif(trim(p_note),''),
           paid_at = case when st='paid' then coalesce(p.paid_at, now()) else p.paid_at end
     where p.id = p_id and (public.app_is_platform_admin(p_token) or p.tenant_id = ten)
     returning p.id into newid;
    if newid is null then return query select false,'Платёж не найден', null::uuid; return; end if;
    return query select true,'Платёж сохранён', newid;
  end if;
end $$;

create or replace function public.app_cash_set_status(p_token uuid, p_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; st text; n integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten := public.app_my_tenant(p_token);
  st := lower(trim(coalesce(p_status,'')));
  if st not in ('planned','paid','overdue','cancelled') then return query select false,'Недопустимый статус'; return; end if;
  update public.app_cash_plan p set status = st, paid_at = case when st='paid' then coalesce(paid_at, now()) else paid_at end
   where p.id = p_id and (public.app_is_platform_admin(p_token) or p.tenant_id = ten);
  get diagnostics n = row_count;
  if n = 0 then return query select false,'Платёж не найден'; return; end if;
  return query select true,'Статус обновлён';
end $$;

create or replace function public.app_cash_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; n integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten := public.app_my_tenant(p_token);
  delete from public.app_cash_plan p where p.id = p_id and (public.app_is_platform_admin(p_token) or p.tenant_id = ten);
  get diagnostics n = row_count;
  if n = 0 then return query select false,'Платёж не найден'; return; end if;
  return query select true,'Платёж удалён';
end $$;

create or replace function public.app_cash_calendar(p_token uuid, p_days integer default 30)
returns table (at date, kind text, counterparty text, amount numeric, source text, status text, days_left integer)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean; dn integer;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  dn := greatest(least(coalesce(p_days,30), 365), 1);
  return query
    select * from (
      select i.due_date as at, 'in'::text as kind, coalesce(i.customer, c.name) as counterparty, i.amount,
             ('Счёт ' || coalesce(i.number,'')) as source, i.status, (i.due_date - current_date)::int as days_left
        from public.app_invoices i left join public.app_customers c on c.id = i.customer_id
       where (adm or i.tenant_id = ten) and i.status <> 'paid' and i.due_date is not null
         and i.due_date <= current_date + dn
      union all
      select p.due_date, p.kind, p.counterparty, p.amount, coalesce(p.doc, 'Платёж'), p.status, (p.due_date - current_date)::int
        from public.app_cash_plan p
       where (adm or p.tenant_id = ten) and p.status not in ('paid','cancelled') and p.due_date is not null
         and p.due_date <= current_date + dn
    ) t
    order by at;
end $$;

create or replace function public.app_cash_kpi(p_token uuid)
returns table (receivable numeric, payable numeric, overdue_in numeric, overdue_out numeric, cash_plan_30 numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query select
    (select coalesce(sum(i.amount),0) from public.app_invoices i where (adm or i.tenant_id=ten) and i.status<>'paid'),
    (select coalesce(sum(p.amount),0) from public.app_cash_plan p where (adm or p.tenant_id=ten) and p.kind='out' and p.status<>'paid'),
    (select coalesce(sum(i.amount),0) from public.app_invoices i where (adm or i.tenant_id=ten) and i.status<>'paid' and i.due_date < current_date),
    (select coalesce(sum(p.amount),0) from public.app_cash_plan p where (adm or p.tenant_id=ten) and p.kind='out' and p.status<>'paid' and p.due_date < current_date),
    (select coalesce(sum(case when t.kind='in' then t.amount else -t.amount end),0) from public.app_cash_calendar(p_token, 30) t);
end $$;

-- Себестоимость по факту (из экономики заявок)
create or replace function public.app_cost_fact(p_token uuid, p_order_number text)
returns table (number text, work_cost numeric, material_cost numeric, overhead numeric, total numeric, margin numeric, margin_pct numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  return query select e.number, e.work_cost, e.material_cost, 0::numeric,
                      coalesce(e.total, e.work_cost + e.material_cost),
                      e.margin, e.margin_pct
    from public.app_economics_orders(p_token) e
   where e.number = p_order_number;
end $$;

-- ================= Демо =================
insert into public.app_budgets (tenant_id, name, year, cfo, status, created_login)
select 'aaaaaaaa-0000-0000-0000-000000000001', 'Бюджет 2026 (демо)', extract(year from current_date)::int, 'Дирекция', 'approved', 'owner'
where not exists (select 1 from public.app_budgets where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and name='Бюджет 2026 (демо)');

insert into public.app_budget_lines (budget_id, category, item, month, amount_plan, amount_fact)
select b.id, v.cat, v.item, v.m, v.plan, v.fact
from public.app_budgets b,
     (values ('Продажи','Выручка',1,3000000::numeric,0::numeric), ('Материалы','Закупка металла',1,900000::numeric,0::numeric), ('ФОТ','Оплата труда',1,1200000::numeric,0::numeric)) as v(cat,item,m,plan,fact)
where b.tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and b.name='Бюджет 2026 (демо)'
  and not exists (select 1 from public.app_budget_lines l where l.budget_id = b.id and l.category = v.cat and l.item = v.item and l.month = v.m);

insert into public.app_cash_plan (tenant_id, kind, counterparty, amount, due_date, status, doc, created_login)
select 'aaaaaaaa-0000-0000-0000-000000000001', 'out', 'ООО Металл', 450000, current_date + 7, 'planned', 'Счёт поставщика', 'owner'
where not exists (select 1 from public.app_cash_plan where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and doc='Счёт поставщика' and counterparty='ООО Металл');

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Экономика','Финансы и управленческий учёт: бюджеты, план-факт, платёжный календарь',
   'W18a: бюджеты/ЦФО (app_budgets, app_budget_lines: статьи/месяц план и факт; план-факт app_budget_plan_fact, KPI app_budget_kpi, факт «Продажи» из оплаченных счетов app_budget_from_invoices); платёжный календарь (app_cash_plan in/out, app_cash_calendar — входящие счета + платежи, app_cash_kpi: дебиторка/кредиторка/просрочка/касса 30 дней); себестоимость по факту (app_cost_fact из экономики заявок). Модуль «Финансы». Платежи по счетам — app_payment_add/list (ранее).',
   'финансы бюджет ЦФО план-факт платежный календарь дебиторка кредиторка себестоимость FRP')
) as v(category,question,answer,tags)
where not exists (
  select 1 from public.app_knowledge
   where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001' and question = 'Финансы и управленческий учёт: бюджеты, план-факт, платёжный календарь'
);

-- ---------- Права ----------
grant execute on function public.app_budgets_list(uuid) to anon, authenticated;
grant execute on function public.app_budget_save(uuid,uuid,text,integer,text,text,text) to anon, authenticated;
grant execute on function public.app_budget_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_budget_lines_list(uuid,uuid) to anon, authenticated;
grant execute on function public.app_budget_line_save(uuid,uuid,uuid,text,text,integer,numeric,numeric,text) to anon, authenticated;
grant execute on function public.app_budget_line_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_budget_plan_fact(uuid,uuid) to anon, authenticated;
grant execute on function public.app_budget_kpi(uuid,uuid) to anon, authenticated;
grant execute on function public.app_budget_from_invoices(uuid,uuid,integer,integer) to anon, authenticated;
grant execute on function public.app_cash_list(uuid,text,text) to anon, authenticated;
grant execute on function public.app_cash_save(uuid,uuid,text,text,numeric,date,text,text,text) to anon, authenticated;
grant execute on function public.app_cash_set_status(uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_cash_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_cash_calendar(uuid,integer) to anon, authenticated;
grant execute on function public.app_cash_kpi(uuid) to anon, authenticated;
grant execute on function public.app_cost_fact(uuid,text) to anon, authenticated;
