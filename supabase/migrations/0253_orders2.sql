-- ============================================================
-- 3DMP Service · 0253_orders2.sql
-- X15 (остаток) · Заявки: аудит изменений (триггер) + публичная форма
-- заявок с сайта (заявка без входа → конвертация в заявку системы).
-- Идемпотентно. Зависит от 0001..0252.
-- ============================================================

-- ---------- Аудит изменений заявок ----------
create table if not exists public.app_order_audit (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid references public.tenants (id),
  order_id   uuid references public.app_orders (id) on delete cascade,
  action     text not null default 'update',
  changes    jsonb not null default '{}'::jsonb,
  by_login   text,
  at         timestamptz not null default now()
);
create index if not exists app_order_audit_idx on public.app_order_audit (order_id, at desc);
alter table public.app_order_audit enable row level security;

create or replace function public.app_orders_audit() returns trigger
language plpgsql security definer set search_path = public as $$
declare ch jsonb := '{}'::jsonb; k text; o jsonb; n jsonb;
begin
  if TG_OP = 'INSERT' then
    insert into public.app_order_audit (tenant_id, order_id, action, changes)
    values (NEW.tenant_id, NEW.id, 'create', jsonb_build_object('number', NEW.number, 'title', NEW.title, 'status', NEW.status, 'amount', NEW.amount));
    return NEW;
  end if;
  o := to_jsonb(OLD); n := to_jsonb(NEW);
  for k in select jsonb_object_keys(n) loop
    if (o->>k) is distinct from (n->>k) then ch := ch || jsonb_build_object(k, jsonb_build_object('old', o->k, 'new', n->k)); end if;
  end loop;
  if ch <> '{}'::jsonb then
    insert into public.app_order_audit (tenant_id, order_id, action, changes) values (NEW.tenant_id, NEW.id, 'update', ch);
  end if;
  return NEW;
end $$;
drop trigger if exists app_orders_audit_trg on public.app_orders;
create trigger app_orders_audit_trg after insert or update on public.app_orders for each row execute function public.app_orders_audit();

create or replace function public.app_order_audit_list(p_token uuid, p_order_id uuid)
returns table (at timestamptz, action text, changes jsonb, by_login text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query select a.at, a.action, a.changes, a.by_login
    from public.app_order_audit a
   where a.order_id = p_order_id and (adm or a.tenant_id = ten)
   order by a.at desc limit 200;
end $$;

-- ---------- Публичные заявки с сайта ----------
create sequence if not exists public.app_public_req_seq;
create table if not exists public.app_public_requests (
  id          uuid primary key default gen_random_uuid(),
  kind        text not null default 'request',
  name        text,
  contact     text,
  title       text not null,
  description text,
  budget      numeric,
  status      text not null default 'new',   -- new|accepted|rejected|converted
  order_id    uuid references public.app_orders (id) on delete set null,
  number      text,
  at          timestamptz not null default now()
);
create index if not exists app_public_requests_idx on public.app_public_requests (status, at desc);
alter table public.app_public_requests enable row level security;

create or replace function public.app_public_request_add(p_name text, p_contact text, p_title text, p_description text, p_budget numeric default null)
returns table (ok boolean, message text, number text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare num text;
begin
  if coalesce(trim(p_title),'') = '' then return query select false,'Укажите тему заявки',null::text; return; end if;
  num := 'REQ-P-' || lpad(nextval('public.app_public_req_seq')::text, 5, '0');
  insert into public.app_public_requests (kind, name, contact, title, description, budget, number)
  values ('request', nullif(trim(p_name),''), nullif(trim(p_contact),''), left(trim(p_title),200), nullif(trim(p_description),''), p_budget, num);
  return query select true, 'Заявка отправлена', num;
end $$;

create or replace function public.app_public_request_list(p_token uuid)
returns table (id uuid, number text, at timestamptz, name text, contact text, title text, description text, budget numeric, status text, order_number text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query select r.id, r.number, r.at, r.name, r.contact, r.title, r.description, r.budget, r.status, o.number
    from public.app_public_requests r left join public.app_orders o on o.id = r.order_id
   where adm or (o.tenant_id = ten) or o.id is null
   order by r.at desc limit 200;
end $$;

create or replace function public.app_public_request_convert(p_token uuid, p_id uuid)
returns table (ok boolean, message text, number text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare r record; oid uuid; onum text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён',null::text; return; end if;
  select * into r from public.app_public_requests where id = p_id;
  if r.id is null then return query select false,'Заявка не найдена',null::text; return; end if;
  if r.status = 'converted' then return query select false,'Уже конвертирована',null::text; return; end if;
  select o.id, o.number into oid, onum from public.app_order_create(p_token, r.title, coalesce(r.description,''), 'site',
           coalesce(r.name,''), coalesce(r.contact,''), 'normal', null, null, null, r.budget, 'single') o;
  update public.app_public_requests set status='converted', order_id=oid where id=p_id;
  return query select true, 'Заявка создана из формы', onum;
end $$;

grant execute on function public.app_order_audit_list(uuid,uuid) to anon, authenticated;
grant execute on function public.app_public_request_add(text,text,text,text,numeric) to anon, authenticated;
grant execute on function public.app_public_request_list(uuid) to anon, authenticated;
grant execute on function public.app_public_request_convert(uuid,uuid) to anon, authenticated;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select null, v.category, v.question, v.answer, v.tags
from (values
  ('Продажи','Публичная форма заявок и аудит изменений заявок',
   'Публичная форма (страница apps/orders/public.html, без входа) отправляет заявку через app_public_request_add → таблица app_public_requests (номер REQ-P-NNNNN). Менеджер видит список в модуле «Заявки» (app_public_request_list) и конвертирует в заявку системы одной кнопкой (app_public_request_convert → app_order_create, статус converted). Изменения заявок пишутся триггером в app_order_audit (создание и изменения полей: old/new), просмотр — app_order_audit_list.',
   'заявки публичная форма аудит изменений app_public_requests app_order_audit конвертация')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge k where k.question=v.question);
