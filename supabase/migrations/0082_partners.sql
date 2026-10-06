-- ============================================================
-- 3DMP Service · 0082_partners.sql  (v60 — Сессия K: C2 «Партнёрский кабинет»)
-- Партнёры (агенты/интеграторы) и их сделки-рефералы, комиссия, статусы.
-- База знаний. Зависит от 0001..0081.
-- ============================================================

create table if not exists public.app_partners (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid references public.tenants (id),
  name           text not null,
  inn            text,
  contact        text,
  phone          text,
  email          text,
  region         text,
  category       text,                 -- агент|интегратор|сервис|поставщик|прочее
  commission_pct numeric not null default 5,
  status         text not null default 'active', -- active|paused|archived
  note           text,
  created_login  text,
  created_at     timestamptz not null default now()
);
create index if not exists app_partners_idx on public.app_partners (tenant_id, status);
alter table public.app_partners enable row level security;

create table if not exists public.app_partner_deals (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  partner_id    uuid references public.app_partners (id) on delete set null,
  order_id      uuid references public.app_orders (id) on delete set null,
  title         text not null,
  amount        numeric not null default 0,
  commission    numeric not null default 0,
  status        text not null default 'new', -- new|in_work|won|lost
  note          text,
  created_login text,
  created_at    timestamptz not null default now()
);
create index if not exists app_partner_deals_idx on public.app_partner_deals (tenant_id, status);
alter table public.app_partner_deals enable row level security;

-- ---------- Партнёры ----------
create or replace function public.app_partners_list(p_token uuid, p_q text default null)
returns table (id uuid, name text, inn text, contact text, phone text, email text, region text, category text,
               commission_pct numeric, status text, deals bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query
    select p.id, p.name, p.inn, p.contact, p.phone, p.email, p.region, p.category, p.commission_pct, p.status,
      (select count(*) from public.app_partner_deals d where d.partner_id=p.id)
    from public.app_partners p
    where (urole='admin' or p.tenant_id=ten)
      and (qq='' or lower(p.name) like '%'||qq||'%' or lower(coalesce(p.contact,'')) like '%'||qq||'%')
    order by (p.status='archived'), p.name;
end $$;

create or replace function public.app_partner_save(p_token uuid, p_id uuid, p_name text, p_inn text, p_contact text,
  p_phone text, p_email text, p_region text, p_category text, p_commission_pct numeric, p_note text)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; ulogin text; pid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director') then raise exception 'Недостаточно прав'; return; end if;
  if coalesce(trim(p_name),'')='' then raise exception 'Укажите наименование партнёра'; return; end if;
  if p_id is null then
    insert into public.app_partners (tenant_id, name, inn, contact, phone, email, region, category, commission_pct, note, created_login)
    values (ten, trim(p_name), nullif(trim(p_inn),''), nullif(trim(p_contact),''), nullif(trim(p_phone),''), nullif(trim(p_email),''),
            nullif(trim(p_region),''), nullif(trim(p_category),''), coalesce(p_commission_pct,5), nullif(trim(p_note),''), ulogin)
    returning id into pid;
    return query select pid, 'Партнёр добавлен';
  else
    update public.app_partners set name=trim(p_name), inn=nullif(trim(p_inn),''), contact=nullif(trim(p_contact),''),
      phone=nullif(trim(p_phone),''), email=nullif(trim(p_email),''), region=nullif(trim(p_region),''),
      category=nullif(trim(p_category),''), commission_pct=coalesce(p_commission_pct,commission_pct), note=nullif(trim(p_note),'')
     where id=p_id and (urole='admin' or tenant_id=ten) returning id into pid;
    return query select pid, 'Партнёр обновлён';
  end if;
end $$;

create or replace function public.app_partner_set_status(p_token uuid, p_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if p_status not in ('active','paused','archived') then return query select false,'Неверный статус'; return; end if;
  update public.app_partners set status=p_status where id=p_id and (urole='admin' or tenant_id=ten);
  return query select true,'Статус обновлён';
end $$;

create or replace function public.app_partners_kpi(p_token uuid)
returns table (partners bigint, active bigint, deals bigint, won_amount numeric, commission_sum numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select
    (select count(*) from public.app_partners where (urole='admin' or tenant_id=ten)),
    (select count(*) from public.app_partners where status='active' and (urole='admin' or tenant_id=ten)),
    (select count(*) from public.app_partner_deals where (urole='admin' or tenant_id=ten)),
    (select coalesce(sum(amount),0) from public.app_partner_deals where status='won' and (urole='admin' or tenant_id=ten)),
    (select coalesce(sum(commission),0) from public.app_partner_deals where status='won' and (urole='admin' or tenant_id=ten));
end $$;

-- ---------- Сделки партнёров ----------
create or replace function public.app_partner_deals_list(p_token uuid, p_q text default null)
returns table (id uuid, partner_id uuid, partner_name text, order_number text, title text, amount numeric,
               commission numeric, status text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query
    select d.id, d.partner_id, p.name, o.number, d.title, d.amount, d.commission, d.status, d.created_at
    from public.app_partner_deals d
    left join public.app_partners p on p.id=d.partner_id
    left join public.app_orders o on o.id=d.order_id
    where (urole='admin' or d.tenant_id=ten)
      and (qq='' or lower(d.title) like '%'||qq||'%' or lower(coalesce(p.name,'')) like '%'||qq||'%')
    order by d.created_at desc;
end $$;

create or replace function public.app_partner_deal_save(p_token uuid, p_id uuid, p_partner_id uuid, p_order_id uuid,
  p_title text, p_amount numeric, p_commission numeric, p_note text)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; ulogin text; did uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director') then raise exception 'Недостаточно прав'; return; end if;
  if coalesce(trim(p_title),'')='' then raise exception 'Укажите предмет сделки'; return; end if;
  if p_id is null then
    insert into public.app_partner_deals (tenant_id, partner_id, order_id, title, amount, commission, note, created_login)
    values (ten, p_partner_id, p_order_id, trim(p_title), coalesce(p_amount,0), coalesce(p_commission,0), nullif(trim(p_note),''), ulogin)
    returning id into did;
    return query select did, 'Сделка добавлена';
  else
    update public.app_partner_deals set partner_id=p_partner_id, order_id=p_order_id, title=trim(p_title),
      amount=coalesce(p_amount,0), commission=coalesce(p_commission,0), note=nullif(trim(p_note),'')
     where id=p_id and (urole='admin' or tenant_id=ten) returning id into did;
    return query select did, 'Сделка обновлена';
  end if;
end $$;

create or replace function public.app_partner_deal_set_status(p_token uuid, p_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if p_status not in ('new','in_work','won','lost') then return query select false,'Неверный статус'; return; end if;
  update public.app_partner_deals set status=p_status where id=p_id and (urole='admin' or tenant_id=ten);
  return query select true,'Статус обновлён';
end $$;

grant execute on function public.app_partners_list(uuid,text) to anon, authenticated;
grant execute on function public.app_partner_save(uuid,uuid,text,text,text,text,text,text,text,numeric,text) to anon, authenticated;
grant execute on function public.app_partner_set_status(uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_partners_kpi(uuid) to anon, authenticated;
grant execute on function public.app_partner_deals_list(uuid,text) to anon, authenticated;
grant execute on function public.app_partner_deal_save(uuid,uuid,uuid,uuid,text,numeric,numeric,text) to anon, authenticated;
grant execute on function public.app_partner_deal_set_status(uuid,uuid,text) to anon, authenticated;

-- ---------- Демо (тенант A) ----------
do $$
declare A constant uuid := 'aaaaaaaa-0000-0000-0000-000000000001'; pid uuid;
begin
  if not exists (select 1 from public.app_partners where tenant_id=A) then
    insert into public.app_partners (tenant_id, name, inn, contact, phone, email, region, category, commission_pct, status, created_login)
    values (A, 'ООО «Промтех-Агент»', '5901234567', 'Орлов О.О.', '+7 342 111-22-33', 'agent@promtech.ru', 'Пермь', 'агент', 5, 'active', 'manager')
    returning id into pid;
    insert into public.app_partners (tenant_id, name, contact, phone, email, region, category, commission_pct, status, created_login)
    values (A, 'ИП Смирнов (интегратор)', 'Смирнов С.С.', '+7 342 222-33-44', 'smirnov@int.ru', 'Екатеринбург', 'интегратор', 7, 'active', 'manager');
    insert into public.app_partner_deals (tenant_id, partner_id, order_id, title, amount, commission, status, created_login)
    values (A, pid, (select id from public.app_orders where tenant_id=A order by created_at limit 1),
            'Поставка оснастки (реферал)', 380000, 19000, 'in_work', 'manager');
  end if;
end $$;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Продажи','Партнёрский кабинет (C2)',
   'Модуль «Партнёры»: реестр агентов/интеграторов/сервис-партнёров с реквизитами, категорией, процентом комиссии и статусом (активен/пауза/архив); сделки-рефералы с суммой и комиссией, статусы (новая → в работе → выиграна/проиграна). KPI: партнёры, активные, сделки, выигранная сумма, комиссия.',
   'партнёры агенты интеграторы рефералы комиссия сделки C2')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Партнёрский кабинет (C2)');
