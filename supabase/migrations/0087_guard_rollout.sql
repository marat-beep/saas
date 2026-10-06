-- ============================================================
-- 3DMP Service · 0087_guard_rollout.sql  (v65 — P8 шаг 2: серверная матрица прав)
-- Внедрение app_guard в мутирующие RPC (слайс: эскроу, маркетплейс).
-- Права берутся из матрицы app_role_permissions: admin/owner — всегда; иначе
-- по роли/модулю. Зависит от 0001..0086.
-- ============================================================

-- ---------- Escrow: save ----------
create or replace function public.app_escrow_save(p_token uuid, p_id uuid, p_order_id uuid, p_customer_id uuid,
  p_buyer text, p_seller text, p_amount numeric, p_fee_pct numeric, p_milestone text, p_note text)
returns table (id uuid, number text, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; ulogin text; did uuid; dnum text; tname text; cname text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  perform public.app_guard(p_token, 'escrow', 'edit');
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
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

-- ---------- Escrow: set_status ----------
create or replace function public.app_escrow_set_status(p_token uuid, p_id uuid, p_status text, p_comment text default null)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; ulogin text; d record;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  if not public.app_can(p_token,'escrow','edit') then return query select false,'Недостаточно прав'; return; end if;
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

-- ---------- Marketplace: listing save ----------
create or replace function public.app_market_listing_save(p_token uuid, p_id uuid, p_title text, p_process text,
  p_machine text, p_capacity_hours numeric, p_price_from numeric, p_region text, p_lead_days int, p_note text)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; ulogin text; lid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  perform public.app_guard(p_token, 'marketplace', 'edit');
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
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

-- ---------- Marketplace: request save ----------
create or replace function public.app_market_request_save(p_token uuid, p_id uuid, p_listing_id uuid, p_title text,
  p_qty numeric, p_due_date date, p_budget numeric, p_note text)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; ulogin text; rid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  perform public.app_guard(p_token, 'marketplace', 'edit');
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

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Платформа','Серверная проверка прав в RPC (P8 шаг 2)',
   'Мутирующие RPC проверяют права на сервере через app_guard(token, module, action) (матрица app_role_permissions): admin/owner — всегда; остальные — по назначенным правам. Начато с эскроу и маркетплейса; rollout продолжается по остальным модулям. UI-скрытие кнопок — только удобство, реальная защита — на сервере.',
   'права app_guard серверная проверка RPC матрица P8 безопасность')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Серверная проверка прав в RPC (P8 шаг 2)');
