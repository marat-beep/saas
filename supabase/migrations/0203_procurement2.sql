-- ============================================================
-- 3DMP Service · 0203_procurement2.sql  (X16 — Закупки/поставщики/маркетплейс 2.0)
-- Матрица сравнения КП (app_bid_compare), авто-ранжирование (app_bid_rank),
-- рейтинг поставщиков (app_supplier_rating), рефералы и комиссия партнёров.
-- Идемпотентно. Зависит от 0001..0202.
-- ============================================================

-- bids: убираем устаревший FK на auth.users (сервис не использует Supabase Auth) —
-- иначе портал поставщика не может подать КП.
alter table public.bids drop constraint if exists bids_supplier_id_fkey;
alter table public.bids alter column supplier_id drop not null;
alter table public.bids alter column supplier_id set default gen_random_uuid();

alter table public.app_partners add column if not exists referral_code text;
create unique index if not exists app_partners_ref_uq on public.app_partners (tenant_id, referral_code) where referral_code is not null;

-- ================= RPC: сравнение и ранжирование КП =================
create or replace function public.app_bid_compare(p_token uuid, p_tender_id uuid)
returns table (bid_id uuid, supplier text, price numeric, term_days integer, status text, supplier_rating numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  if not (adm or exists (select 1 from public.tenders t where t.id = p_tender_id)) then raise exception 'Закупка не найдена'; end if;
  return query
    select b.id, coalesce(s.name, b.supplier_name), b.price, b.term_days, b.status, coalesce(s.rating,0)
      from public.bids b left join public.app_suppliers s on lower(s.name) = lower(coalesce(b.supplier_name,''))
     where b.tender_id = p_tender_id
     order by b.price;
end $$;

create or replace function public.app_bid_rank(p_token uuid, p_tender_id uuid)
returns table (rank integer, bid_id uuid, supplier text, price numeric, term_days integer, score numeric, basis text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare min_p numeric; min_t numeric;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select min(b.price), min(nullif(b.term_days,0)) into min_p, min_t from public.bids b where b.tender_id = p_tender_id;
  if min_p is null then return; end if;
  return query
    with base as (
      select b.id, coalesce(s.name, b.supplier_name) as sup, b.price, b.term_days, coalesce(s.rating,0) as rt
        from public.bids b left join public.app_suppliers s on lower(s.name) = lower(coalesce(b.supplier_name,''))
       where b.tender_id = p_tender_id
    ), sc as (
      select b.id, b.sup, b.price, b.term_days, b.rt,
             round(0.6 * (100.0 * min_p / greatest(b.price, 0.01))
                 + 0.3 * (case when b.term_days is null or min_t is null then 50 else 100.0 * min_t / greatest(b.term_days,1) end)
                 + 0.1 * (least(b.rt,5) * 20), 1) as score
        from base b
    )
    select row_number() over (order by sc.score desc, sc.price)::int, sc.id, sc.sup, sc.price, sc.term_days, sc.score,
           'цена 60% · срок 30% · рейтинг 10%'
      from sc order by sc.score desc, sc.price;
end $$;

-- ================= RPC: рейтинг поставщиков =================
create or replace function public.app_supplier_rating(p_token uuid)
returns table (id uuid, name text, category text, status text, rating numeric, tenders_won bigint, avg_price numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query
    select s.id, s.name, s.category, s.status, coalesce(s.rating,0),
           (select count(*) from public.bids b where lower(coalesce(b.supplier_name,'')) = lower(s.name) and b.status='accepted'),
           (select round(avg(b.price),2) from public.bids b where lower(coalesce(b.supplier_name,'')) = lower(s.name))
      from public.app_suppliers s where (adm or s.tenant_id = ten)
     order by coalesce(s.rating,0) desc, s.name;
end $$;

-- ================= RPC: партнёры (реферал/комиссия) =================
create or replace function public.app_partner_referral(p_token uuid, p_partner_id uuid)
returns table (ok boolean, code text, url text, commission_pct numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid; p record; code text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  select * into p from public.app_partners where id = p_partner_id and (adm or tenant_id = ten);
  if p.id is null then return query select false, null::text, null::text, null::numeric; return; end if;
  code := coalesce(p.referral_code, 'P' || substr(replace(p.id::text,'-',''),1,10));
  update public.app_partners set referral_code = code where id = p.id;
  return query select true, code, 'https://sapfir.eu/saas/?ref=' || code, p.commission_pct;
end $$;

create or replace function public.app_partner_deal_commission(p_token uuid, p_deal_id uuid)
returns table (ok boolean, message text, commission numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid; d record; pct numeric; comm numeric;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::numeric; return; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  select * into d from public.app_partner_deals where id = p_deal_id and (adm or tenant_id = ten);
  if d.id is null then return query select false,'Сделка не найдена', null::numeric; return; end if;
  select coalesce(commission_pct,5) into pct from public.app_partners where id = d.partner_id;
  comm := round(d.amount * coalesce(pct,5) / 100.0, 2);
  update public.app_partner_deals set commission = comm where id = d.id;
  return query select true, 'Комиссия рассчитана', comm;
end $$;

-- ================= База знаний =================
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Склад','Закупки/поставщики 2.0: матрица КП, ранжирование, рейтинг, партнёры (X16)',
   'Закупки 2.0: матрица сравнения КП (app_bid_compare), авто-ранжирование предложений (app_bid_rank — цена 60% · срок 30% · рейтинг 10%), рейтинг поставщиков (app_supplier_rating — ручной рейтинг + число побед + средняя цена), партнёры (app_partner_referral — реферальный код/ссылка; app_partner_deal_commission — авто-комиссия по commission_pct). Маркетплейс-оплата — через escrow (app_escrow_*).',
   'закупки поставщики матрица КП ранжирование рейтинг партнёры реферал комиссия escrow маркетплейс')
) as v(category,question,answer,tags)
where not exists (
  select 1 from public.app_knowledge
   where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001'
     and question = 'Закупки/поставщики 2.0: матрица КП, ранжирование, рейтинг, партнёры (X16)'
);

-- ================= Права =================
grant execute on function public.app_bid_compare(uuid,uuid) to anon, authenticated;
grant execute on function public.app_bid_rank(uuid,uuid) to anon, authenticated;
grant execute on function public.app_supplier_rating(uuid) to anon, authenticated;
grant execute on function public.app_partner_referral(uuid,uuid) to anon, authenticated;
grant execute on function public.app_partner_deal_commission(uuid,uuid) to anon, authenticated;
