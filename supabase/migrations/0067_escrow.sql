-- ============================================================
-- 3DMP Service · 0067_escrow.sql  (v45 — ЭПИК G: P5 платежи и эскроу)
-- Эскроу-сделки: средства замораживаются до приёмки работ, комиссия платформы,
-- журнал событий, споры. База знаний. Зависит от 0001..0066.
-- ============================================================

create sequence if not exists public.app_escrow_seq;
create table if not exists public.app_escrow_deals (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid references public.tenants (id),
  number       text,
  order_id     uuid references public.app_orders (id) on delete set null,
  customer_id  uuid references public.app_customers (id) on delete set null,
  buyer        text,
  seller       text,
  amount       numeric not null default 0,
  fee_pct      numeric not null default 2.5,
  milestone    text,
  status       text not null default 'created', -- created|funded|in_work|released|dispute|cancelled
  funded_at    timestamptz,
  released_at  timestamptz,
  note         text,
  created_login text,
  created_at   timestamptz not null default now()
);
create index if not exists app_escrow_deals_idx on public.app_escrow_deals (tenant_id, status);
alter table public.app_escrow_deals enable row level security;

create table if not exists public.app_escrow_events (
  id         uuid primary key default gen_random_uuid(),
  deal_id    uuid references public.app_escrow_deals (id) on delete cascade,
  kind       text not null default 'note', -- created|funded|milestone|released|dispute|refund|note
  comment    text,
  by_login   text,
  created_at timestamptz not null default now()
);
create index if not exists app_escrow_events_idx on public.app_escrow_events (deal_id, created_at);
alter table public.app_escrow_events enable row level security;

create or replace function public.app_escrow_list(p_token uuid, p_q text default null)
returns table (id uuid, number text, order_number text, buyer text, seller text, amount numeric, fee_pct numeric,
               fee numeric, payout numeric, milestone text, status text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query
    select d.id, d.number, o.number, d.buyer, d.seller, d.amount, d.fee_pct,
           round(d.amount*d.fee_pct/100.0,2), round(d.amount*(1-d.fee_pct/100.0),2), d.milestone, d.status, d.created_at
    from public.app_escrow_deals d left join public.app_orders o on o.id=d.order_id
    where (urole='admin' or d.tenant_id=ten)
      and (qq='' or lower(coalesce(d.number,'')) like '%'||qq||'%' or lower(coalesce(d.buyer,'')) like '%'||qq||'%' or lower(coalesce(d.seller,'')) like '%'||qq||'%')
    order by d.created_at desc;
end $$;

create or replace function public.app_escrow_kpi(p_token uuid)
returns table (total bigint, active bigint, released_sum numeric, frozen_sum numeric, fee_sum numeric)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select count(*),
    count(*) filter (where status in ('funded','in_work','dispute')),
    coalesce(sum(amount) filter (where status='released'),0),
    coalesce(sum(amount) filter (where status in ('funded','in_work')),0),
    coalesce(sum(amount*fee_pct/100.0) filter (where status='released'),0)
    from public.app_escrow_deals where (urole='admin' or tenant_id=ten);
end $$;

create or replace function public.app_escrow_save(p_token uuid, p_id uuid, p_order_id uuid, p_customer_id uuid,
  p_buyer text, p_seller text, p_amount numeric, p_fee_pct numeric, p_milestone text, p_note text)
returns table (id uuid, number text, message text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid; urole text; ulogin text; did uuid; dnum text; tname text; cname text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director','economist') then raise exception 'Недостаточно прав'; return; end if;
  if coalesce(p_amount,0) <= 0 then raise exception 'Укажите сумму сделки'; return; end if;
  select name into tname from public.tenants where id=ten;
  select name into cname from public.app_customers where id=p_customer_id;
  if p_id is null then
    dnum := 'ESC-' || lpad(nextval('public.app_escrow_seq')::text, 5, '0');
    insert into public.app_escrow_deals (tenant_id, number, order_id, customer_id, buyer, seller, amount, fee_pct, milestone, note, created_login)
    values (ten, dnum, p_order_id, p_customer_id, coalesce(nullif(trim(p_buyer),''), cname), coalesce(nullif(trim(p_seller),''), tname),
            p_amount, coalesce(p_fee_pct,2.5), nullif(trim(p_milestone),''), nullif(trim(p_note),''), ulogin)
    returning id into did;
    insert into public.app_escrow_events (deal_id, kind, comment, by_login) values (did, 'created', 'Сделка создана', ulogin);
    return query select did, dnum, 'Эскроу-сделка создана';
  else
    update public.app_escrow_deals set order_id=p_order_id, customer_id=p_customer_id,
      buyer=coalesce(nullif(trim(p_buyer),''),buyer), seller=coalesce(nullif(trim(p_seller),''),seller),
      amount=p_amount, fee_pct=coalesce(p_fee_pct,fee_pct), milestone=nullif(trim(p_milestone),''), note=nullif(trim(p_note),'')
     where id=p_id and (urole='admin' or tenant_id=ten) returning id, number into did, dnum;
    return query select did, dnum, 'Сделка обновлена';
  end if;
end $$;

create or replace function public.app_escrow_set_status(p_token uuid, p_id uuid, p_status text, p_comment text default null)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid; urole text; ulogin text; d record;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if p_status not in ('created','funded','in_work','released','dispute','cancelled') then return query select false,'Неверный статус'; return; end if;
  select * into d from public.app_escrow_deals where id=p_id and (urole='admin' or tenant_id=ten);
  if d.id is null then return query select false,'Сделка не найдена'; return; end if;
  update public.app_escrow_deals set status=p_status,
    funded_at = case when p_status='funded' then now() else funded_at end,
    released_at = case when p_status='released' then now() else released_at end
   where id=p_id;
  insert into public.app_escrow_events (deal_id, kind, comment, by_login)
  values (p_id, p_status, coalesce(nullif(trim(p_comment),''), 'Статус: '||p_status), ulogin);
  if p_status in ('released','dispute') then
    perform public.app_notif_roles_t(ten, array['admin','owner','manager','director','economist'],
      'Эскроу '||d.number||': '||p_status, coalesce(p_comment,''), 'apps/escrow/index.html');
  end if;
  return query select true,'Статус обновлён';
end $$;

create or replace function public.app_escrow_events_list(p_token uuid, p_deal_id uuid)
returns table (id uuid, kind text, comment text, by_login text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select e.id, e.kind, e.comment, e.by_login, e.created_at
    from public.app_escrow_events e join public.app_escrow_deals d on d.id=e.deal_id
    where e.deal_id=p_deal_id and (urole='admin' or d.tenant_id=ten)
    order by e.created_at desc;
end $$;

grant execute on function public.app_escrow_list(uuid,text) to anon, authenticated;
grant execute on function public.app_escrow_kpi(uuid) to anon, authenticated;
grant execute on function public.app_escrow_save(uuid,uuid,uuid,uuid,text,text,numeric,numeric,text,text) to anon, authenticated;
grant execute on function public.app_escrow_set_status(uuid,uuid,text,text) to anon, authenticated;
grant execute on function public.app_escrow_events_list(uuid,uuid) to anon, authenticated;

-- ---------- Демо (тенант A) ----------
insert into public.app_escrow_deals (tenant_id, number, order_id, customer_id, buyer, seller, amount, fee_pct, milestone, status, funded_at, created_login)
select 'aaaaaaaa-0000-0000-0000-000000000001', 'ESC-' || lpad(nextval('public.app_escrow_seq')::text,5,'0'),
  (select id from public.app_orders where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' order by created_at limit 1),
  (select id from public.app_customers where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' order by name limit 1),
  (select name from public.app_customers where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' order by name limit 1),
  (select name from public.tenants where id='aaaaaaaa-0000-0000-0000-000000000001'),
  450000, 2.5, 'Отгрузка готовой оснастки', 'funded', now(), 'manager'
where not exists (select 1 from public.app_escrow_deals where tenant_id='aaaaaaaa-0000-0000-0000-000000000001');

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Платформа','Эскроу-сделки (P5)',
   'Модуль «Эскроу»: сделка (ESC-NNNNN) связывает заявку и заказчика, фиксирует сумму, комиссию платформы (%) и этап/веху. Средства «замораживаются» (status funded) и высвобождаются исполнителю после приёмки (released); при разногласиях — спор (dispute). Ведётся журнал событий. KPI: всего, активных, высвобождено, заморожено, комиссия.',
   'эскроу платежи сделка комиссия заморозка высвобождение спор P5')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Эскроу-сделки (P5)');
