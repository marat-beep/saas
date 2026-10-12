-- ============================================================
-- 3DMP Service · 0196_service2.sql  (X17 — Сервис 2.0)
-- Портал дилера (app_dealer_links/_requests), маршрут выездов (app_service_route_plan),
-- счёт по сервис-контракту, акт работ → ЭДО. Идемпотентно. Зависит от 0001..0195.
-- ============================================================

create table if not exists public.app_dealer_links (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid references public.tenants (id),
  app_user_id  uuid not null references public.app_users (id) on delete cascade,
  customer_id  uuid references public.app_customers (id) on delete cascade,
  created_at   timestamptz not null default now()
);
create index if not exists app_dealer_links_idx on public.app_dealer_links (app_user_id);
alter table public.app_dealer_links enable row level security;

create table if not exists public.app_dealer_requests (
  id                 uuid primary key default gen_random_uuid(),
  tenant_id          uuid references public.tenants (id),
  customer_id        uuid references public.app_customers (id) on delete set null,
  title              text not null,
  description        text,
  priority           text not null default 'normal',
  status             text not null default 'new',   -- new|accepted|rejected|closed
  service_request_id uuid references public.app_service_requests (id) on delete set null,
  created_login      text,
  created_at         timestamptz not null default now()
);
create index if not exists app_dealer_requests_idx on public.app_dealer_requests (tenant_id, status);
alter table public.app_dealer_requests enable row level security;

create table if not exists public.app_service_route_plan (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  plan_date     date not null,
  request_id    uuid references public.app_service_requests (id) on delete set null,
  visit_id      uuid references public.app_service_visits (id) on delete set null,
  seq           integer default 0,
  engineer      text,
  place         text,
  status        text not null default 'planned',  -- planned|done|cancelled
  note          text,
  created_login text,
  created_at    timestamptz not null default now()
);
create index if not exists app_service_route_plan_idx on public.app_service_route_plan (tenant_id, plan_date, seq);
alter table public.app_service_route_plan enable row level security;

-- ================= RPC: портал дилера =================
create or replace function public.app_dealer_context(p_token uuid)
returns table (customer_id uuid, customer text, tenant_name text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; urole text;
begin
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Сессия недействительна'; end if;
  if urole <> 'dealer' and urole <> 'admin' then raise exception 'Доступ только для дилера'; end if;
  return query
    select l.customer_id, c.name, t.name
      from public.app_dealer_links l join public.app_customers c on c.id = l.customer_id
      left join public.tenants t on t.id = l.tenant_id
     where l.app_user_id = uid;
end $$;

create or replace function public.app_dealer_request_save(p_token uuid, p_id uuid, p_customer_id uuid, p_title text, p_description text, p_priority text)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; urole text; ten uuid; cust uuid; newid uuid; pr text;
begin
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Сессия недействительна'; end if;
  if urole not in ('dealer','admin') then raise exception 'Доступ только для дилера'; end if;
  select l.customer_id, l.tenant_id into cust, ten from public.app_dealer_links l where l.app_user_id = uid limit 1;
  if cust is null then cust := p_customer_id; end if;
  if cust is null then return query select false,'Не определён заказчик дилера', null::uuid; return; end if;
  if coalesce(trim(p_title),'') = '' then return query select false,'Укажите тему заявки', null::uuid; return; end if;
  pr := coalesce(nullif(trim(p_priority),''),'normal');
  if urole = 'dealer' then ten := coalesce(ten, (select tenant_id from public.app_customers where id = cust)); end if;
  if p_id is null then
    insert into public.app_dealer_requests (tenant_id, customer_id, title, description, priority, created_login)
    values (ten, cust, left(trim(p_title),200), nullif(trim(p_description),''), pr, (select ulogin from public.app_session_user(p_token)))
    returning app_dealer_requests.id into newid;
    return query select true,'Заявка дилера создана', newid;
  else
    update public.app_dealer_requests r set title = left(trim(p_title),200), description = nullif(trim(p_description),''), priority = pr
     where r.id = p_id and (public.app_is_platform_admin(p_token) or customer_id = cust)
     returning r.id into newid;
    if newid is null then return query select false,'Заявка не найдена', null::uuid; return; end if;
    return query select true,'Заявка дилера сохранена', newid;
  end if;
end $$;

create or replace function public.app_dealer_requests_list(p_token uuid, p_all boolean default false)
returns table (id uuid, customer text, title text, priority text, status text, service_number text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; urole text; ten uuid; cust uuid; adm boolean;
begin
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Сессия недействительна'; end if;
  adm := public.app_is_platform_admin(p_token);
  if urole = 'dealer' then
    select l.customer_id, l.tenant_id into cust, ten from public.app_dealer_links l where l.app_user_id = uid limit 1;
    return query
      select r.id, c.name, r.title, r.priority, r.status, sr.number, r.created_at
        from public.app_dealer_requests r
        left join public.app_customers c on c.id = r.customer_id
        left join public.app_service_requests sr on sr.id = r.service_request_id
       where r.customer_id = cust order by r.created_at desc;
  else
    if not (adm or public.app_production_allowed(p_token)) then raise exception 'Доступ запрещён'; end if;
    ten := public.app_my_tenant(p_token);
    return query
      select r.id, c.name, r.title, r.priority, r.status, sr.number, r.created_at
        from public.app_dealer_requests r
        left join public.app_customers c on c.id = r.customer_id
        left join public.app_service_requests sr on sr.id = r.service_request_id
       where adm or r.tenant_id = ten order by r.created_at desc;
  end if;
end $$;

-- Служба сервиса принимает заявку дилера → создаёт сервисную заявку
create or replace function public.app_dealer_request_link(p_token uuid, p_id uuid)
returns table (ok boolean, message text, service_number text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid; r record; res record;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::text; return; end if;
  if not public.app_can_edit(p_token, 'service') then return query select false,'Нет прав на сервис', null::text; return; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  select * into r from public.app_dealer_requests where id = p_id and (adm or tenant_id = ten);
  if r.id is null then return query select false,'Заявка дилера не найдена', null::text; return; end if;
  if r.service_request_id is not null then return query select false,'Уже связано с сервисной заявкой', null::text; return; end if;
  select * into res from public.app_service_save(p_token, null, r.customer_id, null,
    'Дилер: ' || r.title, 'service', null, null, r.description, null, 'Из портала дилера') x;
  update public.app_dealer_requests set status = 'accepted', service_request_id = res.id where id = p_id;
  return query select true,'Создана сервисная заявка: ' || coalesce(res.number,''), res.number;
end $$;

create or replace function public.app_dealer_request_set_status(p_token uuid, p_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; st text; n integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten := public.app_my_tenant(p_token);
  st := lower(trim(coalesce(p_status,'')));
  if st not in ('new','accepted','rejected','closed') then return query select false,'Недопустимый статус'; return; end if;
  update public.app_dealer_requests r set status = st where r.id = p_id and (public.app_is_platform_admin(p_token) or r.tenant_id = ten);
  get diagnostics n = row_count;
  if n = 0 then return query select false,'Заявка не найдена'; return; end if;
  return query select true,'Статус: ' || st;
end $$;

-- ================= RPC: маршрут выездов =================
create or replace function public.app_service_route_build(p_token uuid, p_date date)
returns table (ok boolean, message text, created integer)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid; uname text; d date; cnt integer := 0; rec record;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', 0; return; end if;
  if not public.app_can_edit(p_token, 'service') then return query select false,'Нет прав на сервис', 0; return; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  select s.ulogin into uname from public.app_session_user(p_token) s;
  d := coalesce(p_date, current_date);
  for rec in
    select v.id as visit_id, v.request_id, v.engineer, v.place
      from public.app_service_visits v
      where (adm or v.tenant_id = ten) and v.status <> 'cancelled'
        and (v.planned_at::date = d or (v.planned_at is null and v.arrived_at::date = d))
        and not exists (select 1 from public.app_service_route_plan rp where rp.visit_id = v.id and rp.plan_date = d)
  loop
    insert into public.app_service_route_plan (tenant_id, plan_date, request_id, visit_id, seq, engineer, place, created_login)
    values (ten, d, rec.request_id, rec.visit_id,
            coalesce((select max(rp.seq) from public.app_service_route_plan rp where rp.plan_date = d), 0) + 1,
            rec.engineer, rec.place, uname);
    cnt := cnt + 1;
  end loop;
  return query select true, 'Маршрут на ' || to_char(d,'DD.MM') || ': выездов ' || cnt, cnt;
end $$;

create or replace function public.app_service_route_list(p_token uuid, p_date date)
returns table (id uuid, seq integer, engineer text, place text, request_number text, status text, note text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query
    select rp.id, rp.seq, rp.engineer, rp.place, sr.number, rp.status, rp.note
      from public.app_service_route_plan rp
      left join public.app_service_requests sr on sr.id = rp.request_id
     where (adm or rp.tenant_id = ten) and rp.plan_date = p_date
     order by rp.seq;
end $$;

create or replace function public.app_service_route_save(p_token uuid, p_id uuid, p_seq integer, p_engineer text, p_place text, p_status text, p_note text)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; st text; newid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid; return; end if;
  if not public.app_can_edit(p_token, 'service') then return query select false,'Нет прав на сервис', null::uuid; return; end if;
  ten := public.app_my_tenant(p_token);
  st := coalesce(nullif(trim(p_status),''),'planned');
  if st not in ('planned','done','cancelled') then return query select false,'Недопустимый статус', null::uuid; return; end if;
  update public.app_service_route_plan rp set seq = coalesce(p_seq, rp.seq), engineer = nullif(trim(p_engineer),''),
         place = nullif(trim(p_place),''), status = st, note = nullif(trim(p_note),'')
   where rp.id = p_id and (public.app_is_platform_admin(p_token) or rp.tenant_id = ten)
   returning rp.id into newid;
  if newid is null then return query select false,'Выезд не найден', null::uuid; return; end if;
  return query select true,'Выезд обновлён', newid;
end $$;

-- ================= RPC: сервис ↔ продажи/финансы =================
create or replace function public.app_service_contract_bill(p_token uuid, p_contract_id uuid, p_amount numeric)
returns table (ok boolean, message text, id uuid, number text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid; c record; cname text; res record; amt numeric;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid, null::text; return; end if;
  if not public.app_can_edit(p_token, 'service') then return query select false,'Нет прав на сервис', null::uuid, null::text; return; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  select * into c from public.app_service_contracts where id = p_contract_id and (adm or tenant_id = ten);
  if c.id is null then return query select false,'Контракт не найден', null::uuid, null::text; return; end if;
  select name into cname from public.app_customers where id = c.customer_id;
  amt := coalesce(p_amount, c.cost, 0);
  select * into res from public.app_invoice_create(p_token, null, coalesce(cname,'Сервисный контракт'), amt, current_date + 14,
    'Сервисный контракт ' || coalesce(c.number,'')) x;
  return query select true, 'Счёт по контракту создан', res.id, res.number;
end $$;

create or replace function public.app_service_act_to_edo(p_token uuid, p_request_id uuid)
returns table (ok boolean, message text, id uuid, number text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid; r record; cname text; newid uuid; num text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid, null::text; return; end if;
  if not public.app_can_edit(p_token, 'service') then return query select false,'Нет прав на сервис', null::uuid, null::text; return; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  select * into r from public.app_service_requests where id = p_request_id and (adm or tenant_id = ten);
  if r.id is null then return query select false,'Заявка не найдена', null::uuid, null::text; return; end if;
  select name into cname from public.app_customers where id = r.customer_id;
  num := 'ЭДО-' || to_char(current_date,'YYYY') || '-' || lpad(nextval('public.app_doc_seq')::text, 5, '0');
  insert into public.app_doc_flows (tenant_id, kind, doc_type, title, correspondent, summary, status, responsible_login, reg_number, reg_date, created_login)
  values (ten, 'out', 'акт', 'Акт выполненных работ ' || r.number, cname, left(coalesce(r.works,''),500), 'registered', r.engineer, num, current_date, (select ulogin from public.app_session_user(p_token)))
  returning app_doc_flows.id into newid;
  insert into public.app_doc_links (tenant_id, doc_id, entity_type, entity_id, note)
  values (ten, newid, 'service_request', p_request_id, 'Акт по сервисной заявке');
  return query select true, 'Акт передан в ЭДО: ' || num, newid, num;
end $$;

-- ================= База знаний =================
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Сервис','Сервис 2.0: портал дилера, маршрут выездов, счета и акты (X17)',
   'Сервис 2.0: портал дилера (роль dealer, app_dealer_links + app_dealer_requests; дилер подаёт заявку — app_dealer_request_save/list, служба принимает — app_dealer_request_link создаёт сервисную заявку), маршрут выездов (app_service_route_plan + app_service_route_build/list/save — из запланированных визитов), сервис↔финансы (app_service_contract_bill — счёт по контракту через app_invoice_create), акт работ в ЭДО (app_service_act_to_edo).',
   'сервис дилер портал заявка маршрут выезд контракт счёт акт ЭДО')
) as v(category,question,answer,tags)
where not exists (
  select 1 from public.app_knowledge
   where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001'
     and question = 'Сервис 2.0: портал дилера, маршрут выездов, счета и акты (X17)'
);

-- ================= Права =================
grant execute on function public.app_dealer_context(uuid) to anon, authenticated;
grant execute on function public.app_dealer_request_save(uuid,uuid,uuid,text,text,text) to anon, authenticated;
grant execute on function public.app_dealer_requests_list(uuid,boolean) to anon, authenticated;
grant execute on function public.app_dealer_request_link(uuid,uuid) to anon, authenticated;
grant execute on function public.app_dealer_request_set_status(uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_service_route_build(uuid,date) to anon, authenticated;
grant execute on function public.app_service_route_list(uuid,date) to anon, authenticated;
grant execute on function public.app_service_route_save(uuid,uuid,integer,text,text,text,text) to anon, authenticated;
grant execute on function public.app_service_contract_bill(uuid,uuid,numeric) to anon, authenticated;
grant execute on function public.app_service_act_to_edo(uuid,uuid) to anon, authenticated;
