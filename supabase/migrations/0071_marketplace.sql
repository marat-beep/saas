-- ============================================================
-- 3DMP Service · 0071_marketplace.sql  (v49 — ЭПИК G: M1 маркетплейс мощностей)
-- Витрина свободных мощностей предприятий (кооперация/субподряд) и заявки на
-- выполнение. База знаний. Зависит от 0001..0070.
-- ============================================================

create table if not exists public.app_market_listings (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid references public.tenants (id),
  title          text not null,
  process        text,   -- cnc|edm|grinding|heat|assembly|engraving|other
  machine        text,
  capacity_hours numeric,
  price_from     numeric,
  region         text,
  lead_days      int,
  status         text not null default 'active', -- active|paused|closed
  note           text,
  created_login  text,
  created_at     timestamptz not null default now()
);
create index if not exists app_market_listings_idx on public.app_market_listings (status, process);
alter table public.app_market_listings enable row level security;

create table if not exists public.app_market_requests (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid references public.tenants (id),
  listing_id   uuid references public.app_market_listings (id) on delete set null,
  title        text not null,
  qty          numeric default 1,
  due_date     date,
  budget       numeric,
  status       text not null default 'new', -- new|quoted|accepted|declined|closed
  note         text,
  created_login text,
  created_at   timestamptz not null default now()
);
create index if not exists app_market_requests_idx on public.app_market_requests (tenant_id, status);
alter table public.app_market_requests enable row level security;

-- ---------- Витрина мощностей ----------
create or replace function public.app_market_listings_list(p_token uuid, p_process text default null, p_q text default null)
returns table (id uuid, title text, process text, machine text, capacity_hours numeric, price_from numeric, region text,
               lead_days int, status text, seller text, mine boolean, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query
    select l.id, l.title, l.process, l.machine, l.capacity_hours, l.price_from, l.region, l.lead_days, l.status,
           t.name, (l.tenant_id = ten), l.created_at
    from public.app_market_listings l join public.tenants t on t.id=l.tenant_id
    where (l.status='active' or l.tenant_id=ten or urole='admin')
      and (coalesce(p_process,'')='' or l.process=p_process)
      and (qq='' or lower(l.title) like '%'||qq||'%' or lower(coalesce(l.machine,'')) like '%'||qq||'%' or lower(coalesce(l.region,'')) like '%'||qq||'%')
    order by (l.status<>'active'), l.created_at desc;
end $$;

create or replace function public.app_market_listing_save(p_token uuid, p_id uuid, p_title text, p_process text,
  p_machine text, p_capacity_hours numeric, p_price_from numeric, p_region text, p_lead_days int, p_note text)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; ulogin text; lid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director','chief') then raise exception 'Недостаточно прав'; return; end if;
  if coalesce(trim(p_title),'')='' then raise exception 'Укажите название объявления'; return; end if;
  if p_id is null then
    insert into public.app_market_listings (tenant_id, title, process, machine, capacity_hours, price_from, region, lead_days, note, created_login)
    values (ten, trim(p_title), nullif(trim(p_process),''), nullif(trim(p_machine),''), p_capacity_hours, p_price_from,
            nullif(trim(p_region),''), p_lead_days, nullif(trim(p_note),''), ulogin)
    returning id into lid;
    return query select lid, 'Объявление размещено';
  else
    update public.app_market_listings set title=trim(p_title), process=nullif(trim(p_process),''), machine=nullif(trim(p_machine),''),
      capacity_hours=p_capacity_hours, price_from=p_price_from, region=nullif(trim(p_region),''), lead_days=p_lead_days, note=nullif(trim(p_note),'')
     where id=p_id and (urole='admin' or tenant_id=ten) returning id into lid;
    return query select lid, 'Объявление обновлено';
  end if;
end $$;

create or replace function public.app_market_listing_set_status(p_token uuid, p_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if p_status not in ('active','paused','closed') then return query select false,'Неверный статус'; return; end if;
  update public.app_market_listings set status=p_status where id=p_id and (urole='admin' or tenant_id=ten);
  return query select true,'Статус обновлён';
end $$;

-- ---------- Заявки на выполнение ----------
create or replace function public.app_market_requests_list(p_token uuid, p_q text default null)
returns table (id uuid, listing_title text, seller text, title text, qty numeric, due_date date, budget numeric,
               status text, mine boolean, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query
    select r.id, l.title, st.name, r.title, r.qty, r.due_date, r.budget, r.status, (r.tenant_id=ten), r.created_at
    from public.app_market_requests r
    left join public.app_market_listings l on l.id=r.listing_id
    left join public.tenants st on st.id=l.tenant_id
    where (urole='admin' or r.tenant_id=ten or l.tenant_id=ten)
      and (qq='' or lower(r.title) like '%'||qq||'%' or lower(coalesce(l.title,'')) like '%'||qq||'%')
    order by r.created_at desc;
end $$;

create or replace function public.app_market_request_save(p_token uuid, p_id uuid, p_listing_id uuid, p_title text,
  p_qty numeric, p_due_date date, p_budget numeric, p_note text)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; ulogin text; rid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_title),'')='' then raise exception 'Укажите предмет заявки'; return; end if;
  if p_id is null then
    insert into public.app_market_requests (tenant_id, listing_id, title, qty, due_date, budget, note, created_login)
    values (ten, p_listing_id, trim(p_title), coalesce(p_qty,1), p_due_date, p_budget, nullif(trim(p_note),''), ulogin)
    returning id into rid;
    if p_listing_id is not null then
      perform public.app_notif_roles_t((select tenant_id from public.app_market_listings where id=p_listing_id),
        array['admin','owner','manager'], 'Заявка из маркетплейса: '||trim(p_title), '', 'apps/marketplace/index.html');
    end if;
    return query select rid, 'Заявка отправлена';
  else
    update public.app_market_requests set listing_id=p_listing_id, title=trim(p_title), qty=coalesce(p_qty,qty),
      due_date=p_due_date, budget=p_budget, note=nullif(trim(p_note),'')
     where id=p_id and (urole='admin' or tenant_id=ten) returning id into rid;
    return query select rid, 'Заявка обновлена';
  end if;
end $$;

create or replace function public.app_market_request_set_status(p_token uuid, p_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; lid uuid; seller uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if p_status not in ('new','quoted','accepted','declined','closed') then return query select false,'Неверный статус'; return; end if;
  select r.listing_id, l.tenant_id into lid, seller from public.app_market_requests r
    left join public.app_market_listings l on l.id=r.listing_id
    where r.id=p_id and (urole='admin' or r.tenant_id=ten or l.tenant_id=ten);
  if not found then return query select false,'Заявка не найдена'; return; end if;
  update public.app_market_requests set status=p_status where id=p_id;
  return query select true,'Статус обновлён';
end $$;

create or replace function public.app_market_kpi(p_token uuid)
returns table (my_listings bigint, active_listings bigint, my_requests bigint, accepted bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select
    (select count(*) from public.app_market_listings where (urole='admin' or tenant_id=ten)),
    (select count(*) from public.app_market_listings where status='active' and (urole='admin' or tenant_id=ten)),
    (select count(*) from public.app_market_requests where (urole='admin' or tenant_id=ten)),
    (select count(*) from public.app_market_requests where status='accepted' and (urole='admin' or tenant_id=ten));
end $$;

grant execute on function public.app_market_listings_list(uuid,text,text) to anon, authenticated;
grant execute on function public.app_market_listing_save(uuid,uuid,text,text,text,numeric,numeric,text,int,text) to anon, authenticated;
grant execute on function public.app_market_listing_set_status(uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_market_requests_list(uuid,text) to anon, authenticated;
grant execute on function public.app_market_request_save(uuid,uuid,uuid,text,numeric,date,numeric,text) to anon, authenticated;
grant execute on function public.app_market_request_set_status(uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_market_kpi(uuid) to anon, authenticated;

-- ---------- Демо-объявления (тенант A) ----------
insert into public.app_market_listings (tenant_id, title, process, machine, capacity_hours, price_from, region, lead_days, note, created_login)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.title, v.proc, v.machine, v.cap, v.price, v.region, v.lead, v.note, 'manager'
from (values
  ('Свободные мощности фрезерной группы','cnc','Feeler FTC-350Xl', 320, 2500, 'Пермь', 14, '3/5-осевая обработка'),
  ('Проволочная ЭЭО','edm','Mitsubishi FA10-VS', 180, 2200, 'Пермь', 10, 'Точная резка контура'),
  ('Термообработка (закалка/отпуск)','heat','Камерная печь', 240, 90, 'Пермь', 7, 'По кг'),
  ('Гравирование лазером','engraving','Лазерный маркер', 160, 35, 'Пермь', 3, 'Маркировка партий')
) as v(title,proc,machine,cap,price,region,lead,note)
where not exists (select 1 from public.app_market_listings where tenant_id='aaaaaaaa-0000-0000-0000-000000000001');

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Платформа','Маркетплейс мощностей (M1)',
   'Модуль «Маркетплейс»: предприятия публикуют свободные мощности (процесс, станок, доступные часы, цена от, регион, срок) и видят витрину активных объявлений других организаций. Заявка на выполнение (кол-во, срок, бюджет) уходит владельцу мощности, статусы: новая → предложение → принята/отклонена. Кооперация и субподряд.',
   'маркетплейс мощности кооперация субподряд свободные мощности объявления M1')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Маркетплейс мощностей (M1)');
