-- ============================================================
-- 3DMP Service · 0251_tkp2.sql
-- X15 (остаток) · Реестр ТКП: документ/КП/заявка, напоминания о сроках,
-- связь со сделкой CRM, текст для печати.
-- Идемпотентно. Зависит от 0001..0250.
-- ============================================================

alter table public.app_tkp_registry add column if not exists deal_id uuid references public.app_deals (id) on delete set null;

-- ---------- определение просроченных ----------
create or replace function public.app_tkp_expire_scan(p_token uuid)
returns table (ok boolean, cnt integer, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid; n int;
begin
  if not public.app_production_allowed(p_token) then return query select false,0,'Доступ запрещён'; return; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  update public.app_tkp_registry set status='expired'
   where status='actual' and valid_until is not null and valid_until < current_date and (adm or tenant_id=ten);
  get diagnostics n = row_count;
  return query select true, n, 'Помечено просроченными: ' || n;
end $$;

-- ---------- напоминания: истекающие в N дней ----------
create or replace function public.app_tkp_expiring(p_token uuid, p_days integer default 14)
returns table (id uuid, number text, subject text, counterparty text, valid_until date, days_left integer)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query select t.id, t.number, t.subject, t.counterparty, t.valid_until, (t.valid_until - current_date)::int
    from public.app_tkp_registry t
   where (adm or t.tenant_id = ten) and t.status='actual' and t.valid_until is not null
     and t.valid_until >= current_date and t.valid_until <= current_date + greatest(coalesce(p_days,14),1)
   order by t.valid_until;
end $$;

-- ---------- ТКП → документ ----------
create or replace function public.app_tkp_to_doc(p_token uuid, p_id uuid)
returns table (ok boolean, message text, number text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid; r record; dn text; content text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён',null::text; return; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  select * into r from public.app_tkp_registry where id=p_id and (adm or tenant_id=ten);
  if r.id is null then return query select false,'ТКП не найдено',null::text; return; end if;
  content := 'Технико-коммерческое предложение ' || coalesce(r.number,'') || chr(10)
          || 'Дата: ' || r.tkp_date || ' · действует до: ' || coalesce(r.valid_until::text,'—') || chr(10)
          || 'Заказчик: ' || coalesce(r.counterparty,'—') || chr(10)
          || 'Предмет: ' || r.subject || chr(10)
          || 'Стоимость: ' || coalesce(r.price::text,'—') || ' ₽' || chr(10) || coalesce(r.note,'');
  select d.number into dn from public.app_doc_create(p_token, 'other', 'ТКП: ' || r.subject, r.order_id, r.counterparty, r.price, content) d;
  update public.app_tkp_registry set document_id = (select id from public.app_documents where number=dn) where id=p_id;
  return query select true, 'Документ ТКП создан', dn;
end $$;

-- ---------- ТКП → КП ----------
create or replace function public.app_tkp_to_quote(p_token uuid, p_id uuid)
returns table (ok boolean, message text, number text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid; r record; dn text; content text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён',null::text; return; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  select * into r from public.app_tkp_registry where id=p_id and (adm or tenant_id=ten);
  if r.id is null then return query select false,'ТКП не найдено',null::text; return; end if;
  content := 'Коммерческое предложение по ТКП ' || coalesce(r.number,'') || chr(10) || 'Предмет: ' || r.subject
          || chr(10) || 'Сумма: ' || coalesce(r.price::text,'—') || ' ₽' || chr(10) || 'Действует до: ' || coalesce(r.valid_until::text,'—');
  select d.number into dn from public.app_doc_create(p_token, 'kp', 'КП: ' || r.subject, r.order_id, r.counterparty, r.price, content) d;
  update public.app_tkp_registry set document_id = (select id from public.app_documents where number=dn) where id=p_id;
  return query select true, 'КП создано по ТКП', dn;
end $$;

-- ---------- ТКП → заявка (+ статус contracted) ----------
create or replace function public.app_tkp_to_order(p_token uuid, p_id uuid)
returns table (ok boolean, message text, number text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid; r record; oid uuid; onum text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён',null::text; return; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  select * into r from public.app_tkp_registry where id=p_id and (adm or tenant_id=ten);
  if r.id is null then return query select false,'ТКП не найдено',null::text; return; end if;
  select o.id, o.number into oid, onum from public.app_order_create(p_token, r.subject, 'Из ТКП ' || coalesce(r.number,''), 'tkp',
           coalesce(r.counterparty,''), '', 'normal', r.customer_id, null, null, r.price, 'single') o;
  update public.app_tkp_registry set order_id = oid, status='contracted' where id=p_id;
  return query select true, 'Заявка создана из ТКП', onum;
end $$;

-- ---------- связь со сделкой ----------
create or replace function public.app_tkp_link_deal(p_token uuid, p_id uuid, p_deal_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  update public.app_tkp_registry set deal_id = p_deal_id where id=p_id and (adm or tenant_id=ten);
  return query select true, 'Связь со сделкой обновлена';
end $$;

-- ---------- текст для печати ----------
create or replace function public.app_tkp_print_text(p_token uuid, p_id uuid)
returns table (number text, content text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid; r record;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  select * into r from public.app_tkp_registry where id=p_id and (adm or tenant_id=ten);
  if r.id is null then return; end if;
  return query select coalesce(r.number,''),
    'ТЕХНИКО-КОММЕРЧЕСКОЕ ПРЕДЛОЖЕНИЕ ' || coalesce(r.number,'') || chr(10) ||
    'Дата: ' || r.tkp_date || '   Действует до: ' || coalesce(r.valid_until::text,'—') || chr(10) ||
    'Заказчик: ' || coalesce(r.counterparty,'—') || chr(10) ||
    'Предмет: ' || r.subject || chr(10) ||
    'Стоимость: ' || coalesce(r.price::text,'—') || ' ₽' || chr(10) ||
    'Статус: ' || r.status || chr(10) || coalesce(r.note,'');
end $$;

grant execute on function public.app_tkp_expire_scan(uuid) to anon, authenticated;
grant execute on function public.app_tkp_expiring(uuid,integer) to anon, authenticated;
grant execute on function public.app_tkp_to_doc(uuid,uuid) to anon, authenticated;
grant execute on function public.app_tkp_to_quote(uuid,uuid) to anon, authenticated;
grant execute on function public.app_tkp_to_order(uuid,uuid) to anon, authenticated;
grant execute on function public.app_tkp_link_deal(uuid,uuid,uuid) to anon, authenticated;
grant execute on function public.app_tkp_print_text(uuid,uuid) to anon, authenticated;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select null, v.category, v.question, v.answer, v.tags
from (values
  ('Продажи','ТКП: документ, КП, заявка, напоминания о сроках, связь со сделкой',
   'Реестр ТКП: из ТКП создаётся документ (app_tkp_to_doc), КП (app_tkp_to_quote) и заявка (app_tkp_to_order, статус contracted); контроль сроков — app_tkp_expiring (истекающие в N дней) и app_tkp_expire_scan (пометить просроченные); связь со сделкой CRM — app_tkp_link_deal; печать — app_tkp_print_text.',
   'ТКП документ КП заявка напоминания сроки сделка CRM app_tkp_to_order app_tkp_expiring')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge k where k.question=v.question);
