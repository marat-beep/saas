-- ============================================================
-- 3DMP Service · 0157_crm_trace_scope.sql  (R1+R3+R4)
-- R1 — CRM: напоминания по сделкам и контакт через интеграции.
-- R3 — Склад: генеалогия партий материалов (партия → наряд → паспорт).
-- R4 — Доступ: сквозной гейтинг данных по подразделению (заказы/наряды).
-- Идемпотентно. Зависит от 0001..0156.
-- ============================================================

-- ================= R1: CRM-напоминания =================
create table if not exists public.app_crm_reminders (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  deal_id       uuid references public.app_deals (id) on delete cascade,
  customer_id   uuid references public.app_customers (id) on delete set null,
  title         text not null,
  due_at        timestamptz not null default now(),
  channel       text not null default 'task',   -- call|meeting|email|telegram|sms|task
  note          text,
  status        text not null default 'open',   -- open|done|cancelled
  owner_login   text,
  notified_at   timestamptz,
  created_by    uuid references public.app_users (id) on delete set null,
  created_login text,
  created_at    timestamptz not null default now()
);
create index if not exists app_crm_reminders_idx on public.app_crm_reminders (tenant_id, status, due_at);
alter table public.app_crm_reminders enable row level security;

create or replace function public.app_crm_reminders_list(p_token uuid, p_status text default 'open')
returns table (id uuid, deal_title text, customer text, title text, due_at timestamptz, channel text,
               status text, owner_login text, days_left integer, note text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean; st text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token);
  ten := public.app_my_tenant(p_token);
  st := nullif(trim(coalesce(p_status,'')),'');
  return query
    select r.id, d.title, c.name, r.title, r.due_at, r.channel, r.status, r.owner_login,
           (r.due_at::date - current_date)::int, r.note
      from public.app_crm_reminders r
      left join public.app_deals d on d.id = r.deal_id
      left join public.app_customers c on c.id = r.customer_id
     where (adm or r.tenant_id = ten) and (st is null or r.status = st)
     order by r.due_at;
end $$;

create or replace function public.app_crm_reminder_save(p_token uuid, p_id uuid, p_deal_id uuid, p_title text,
  p_due_at timestamptz, p_channel text, p_note text)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; uname text; me uuid; newid uuid; cust uuid; ch text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid; return; end if;
  select u.tenant_id, s.ulogin, s.uid into ten, uname, me from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  if coalesce(trim(p_title),'') = '' then return query select false,'Укажите тему напоминания', null::uuid; return; end if;
  ch := coalesce(nullif(trim(p_channel),''),'task');
  if ch not in ('call','meeting','email','telegram','sms','task') then return query select false,'Недопустимый канал', null::uuid; return; end if;
  select d.customer_id into cust from public.app_deals d where d.id = p_deal_id and (public.app_is_platform_admin(p_token) or d.tenant_id = ten);
  if p_id is null then
    insert into public.app_crm_reminders (tenant_id, deal_id, customer_id, title, due_at, channel, note, owner_login, created_by, created_login)
    values (ten, p_deal_id, cust, left(trim(p_title),160), coalesce(p_due_at, now()), ch, nullif(trim(p_note),''), uname, me, uname)
    returning app_crm_reminders.id into newid;
    return query select true,'Напоминание создано', newid;
  else
    update public.app_crm_reminders r set deal_id = p_deal_id, customer_id = coalesce(cust, r.customer_id),
           title = left(trim(p_title),160), due_at = coalesce(p_due_at, r.due_at), channel = ch,
           note = nullif(trim(p_note),''), status = 'open', notified_at = null
     where r.id = p_id and (public.app_is_platform_admin(p_token) or r.tenant_id = ten)
     returning r.id into newid;
    if newid is null then return query select false,'Напоминание не найдено', null::uuid; return; end if;
    return query select true,'Напоминание сохранено', newid;
  end if;
end $$;

create or replace function public.app_crm_reminder_set_status(p_token uuid, p_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; st text; n integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten := public.app_my_tenant(p_token);
  st := lower(trim(coalesce(p_status,'')));
  if st not in ('open','done','cancelled') then return query select false,'Недопустимый статус'; return; end if;
  update public.app_crm_reminders r set status = st where r.id = p_id and (public.app_is_platform_admin(p_token) or r.tenant_id = ten);
  get diagnostics n = row_count;
  if n = 0 then return query select false,'Напоминание не найдено'; return; end if;
  return query select true,'Статус обновлён';
end $$;

create or replace function public.app_crm_reminder_scan(p_token uuid)
returns table (notified integer, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; rec record; uid uuid; cnt integer := 0;
begin
  if not public.app_production_allowed(p_token) then return query select 0,'Доступ запрещён'; return; end if;
  ten := public.app_my_tenant(p_token);
  for rec in
    select r.id, r.title, r.owner_login, r.due_at, coalesce(c.name, d.title, '') as what
      from public.app_crm_reminders r
      left join public.app_customers c on c.id = r.customer_id
      left join public.app_deals d on d.id = r.deal_id
     where r.tenant_id = ten and r.status = 'open' and r.notified_at is null and r.due_at <= now() + interval '1 day'
  loop
    uid := null;
    select u.id into uid from public.app_users u where u.login = rec.owner_login and u.tenant_id = ten limit 1;
    if uid is not null then
      perform public.app_notif_send(uid, 'Напоминание: ' || rec.title, rec.what || ' · срок ' || to_char(rec.due_at, 'DD.MM HH24:MI'), 'apps/crm/index.html');
    end if;
    update public.app_crm_reminders set notified_at = now() where id = rec.id;
    cnt := cnt + 1;
  end loop;
  return query select cnt, 'Уведомлений по напоминаниям: ' || cnt;
end $$;

-- Контакт с клиентом через активную интеграцию канала (e-mail/Telegram/SMS/webhook).
create or replace function public.app_crm_contact_send(p_token uuid, p_customer_id uuid, p_channel text, p_text text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; ch text; k text; iid uuid; cust record;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten := public.app_my_tenant(p_token);
  ch := lower(trim(coalesce(p_channel,'email')));
  k := case ch when 'email' then 'smtp' when 'telegram' then 'telegram' when 'sms' then 'sms' when 'webhook' then 'webhook' else ch end;
  select id, name, contact_person, email, phone into cust from public.app_customers where id = p_customer_id and (public.app_is_platform_admin(p_token) or tenant_id = ten);
  if cust.id is null then return query select false,'Клиент не найден'; return; end if;
  select i.id into iid from public.app_integrations i
   where i.tenant_id = ten and coalesce(i.active,true) and (i.kind = k or i.kind = ch) order by i.created_at limit 1;
  if iid is null then
    return query select false, 'Нет активной интеграции канала «' || ch || '» (настройте в «Интеграции»)';
    return;
  end if;
  perform public.app_integration_enqueue(p_token, iid, 'out', jsonb_build_object(
    'channel', ch, 'customer', coalesce(cust.name,''), 'to', coalesce(cust.email, cust.phone, ''),
    'text', coalesce(p_text,'')));
  return query select true, 'Сообщение поставлено в очередь канала «' || ch || '»';
end $$;

-- ================= R3: генеалогия партий =================
alter table public.app_stock_moves add column if not exists lot_id uuid references public.app_material_lots (id);

create table if not exists public.app_lot_trace (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  lot_id        uuid not null references public.app_material_lots (id) on delete cascade,
  naryad_id     uuid references public.app_naryads (id) on delete set null,
  passport_id   uuid references public.app_passports (id) on delete set null,
  qty           numeric,
  note          text,
  created_login text,
  created_at    timestamptz not null default now()
);
create index if not exists app_lot_trace_lot_idx on public.app_lot_trace (lot_id);
create index if not exists app_lot_trace_passport_idx on public.app_lot_trace (passport_id);
alter table public.app_lot_trace enable row level security;

create or replace function public.app_lot_list(p_token uuid, p_material_id uuid default null)
returns table (id uuid, lot text, material text, supplier text, qty numeric, produced_at date, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token);
  ten := public.app_my_tenant(p_token);
  return query
    select l.id, l.lot, m.name, l.supplier, l.qty, l.produced_at, l.created_at
      from public.app_material_lots l left join public.app_materials m on m.id = l.material_id
     where (adm or l.tenant_id = ten) and (p_material_id is null or l.material_id = p_material_id)
     order by l.created_at desc;
end $$;

create or replace function public.app_lot_trace_add(p_token uuid, p_lot_id uuid, p_naryad_id uuid, p_passport_id uuid, p_qty numeric, p_note text)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; uname text; newid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid; return; end if;
  select u.tenant_id, s.ulogin into ten, uname from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  if not exists (select 1 from public.app_material_lots l where l.id = p_lot_id and (public.app_is_platform_admin(p_token) or l.tenant_id = ten)) then
    return query select false,'Партия не найдена', null::uuid; return;
  end if;
  insert into public.app_lot_trace (tenant_id, lot_id, naryad_id, passport_id, qty, note, created_login)
  values (ten, p_lot_id, p_naryad_id, p_passport_id, p_qty, nullif(trim(p_note),''), uname)
  returning app_lot_trace.id into newid;
  return query select true,'Связь партии добавлена', newid;
end $$;

create or replace function public.app_lot_trace_list(p_token uuid, p_lot_id uuid)
returns table (naryad_number text, passport_number text, qty numeric, note text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token);
  ten := public.app_my_tenant(p_token);
  return query
    select n.number, pp.number, t.qty, t.note, t.created_at
      from public.app_lot_trace t
      left join public.app_naryads n on n.id = t.naryad_id
      left join public.app_passports pp on pp.id = t.passport_id
     where t.lot_id = p_lot_id and (adm or t.tenant_id = ten)
     order by t.created_at;
end $$;

create or replace function public.app_lot_genealogy(p_token uuid, p_lot_id uuid)
returns table (stage text, ref text, detail text, qty numeric, at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token);
  ten := public.app_my_tenant(p_token);
  return query
    select 'Партия'::text, l.lot, coalesce(m.name,'') || coalesce(' · ' || l.supplier, ''), l.qty, l.created_at
      from public.app_material_lots l left join public.app_materials m on m.id = l.material_id
     where l.id = p_lot_id and (adm or l.tenant_id = ten)
  union all
    select 'Движение', sm.kind, coalesce(sm.note,''), sm.qty, sm.created_at
      from public.app_stock_moves sm where sm.lot_id = p_lot_id and (adm or sm.tenant_id = ten)
  union all
    select 'Наряд', n.number, coalesce(t.note,''), t.qty, t.created_at
      from public.app_lot_trace t left join public.app_naryads n on n.id = t.naryad_id
     where t.lot_id = p_lot_id and (adm or t.tenant_id = ten)
  union all
    select 'Паспорт', pp.number, coalesce(pp.product,''), t.qty, t.created_at
      from public.app_lot_trace t left join public.app_passports pp on pp.id = t.passport_id
     where t.lot_id = p_lot_id and t.passport_id is not null and (adm or t.tenant_id = ten);
end $$;

create or replace function public.app_lot_genealogy_by_passport(p_token uuid, p_passport_id uuid)
returns table (lot_id uuid, lot text, material text, qty numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token);
  ten := public.app_my_tenant(p_token);
  return query
    select distinct l.id, l.lot, m.name, t.qty
      from public.app_lot_trace t
      join public.app_material_lots l on l.id = t.lot_id
      left join public.app_materials m on m.id = l.material_id
     where t.passport_id = p_passport_id and (adm or t.tenant_id = ten);
end $$;

-- ================= R4: гейтинг по подразделению =================
alter table public.app_orders  add column if not exists department_id uuid;
alter table public.app_naryads add column if not exists department_id uuid;

update public.app_orders o set department_id = e.department_id
  from public.app_employees e
 where e.user_login = o.created_login and e.tenant_id = o.tenant_id and o.department_id is null and e.department_id is not null;
update public.app_naryads n set department_id = e.department_id
  from public.app_employees e
 where e.user_login = n.created_login and e.tenant_id = n.tenant_id and n.department_id is null and e.department_id is not null;

create or replace function public.app_dept_scope_get(p_token uuid)
returns boolean
language plpgsql stable security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; v boolean;
begin
  ten := public.app_my_tenant(p_token);
  select coalesce((t.features ->> 'dept_scope')::boolean, false) into v from public.tenants t where t.id = ten;
  return coalesce(v, false);
end $$;

create or replace function public.app_dept_scope_set(p_token uuid, p_enabled boolean)
returns table (ok boolean, message text, enabled boolean)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid;
begin
  if not (public.app_is_platform_admin(p_token) or public.app_is_owner(p_token)) then
    return query select false,'Только владелец/администратор', public.app_dept_scope_get(p_token); return;
  end if;
  ten := public.app_my_tenant(p_token);
  update public.tenants t set features = jsonb_set(coalesce(t.features,'{}'::jsonb), '{dept_scope}', to_jsonb(coalesce(p_enabled,false)), true) where t.id = ten;
  return query select true, case when coalesce(p_enabled,false) then 'Гейтинг по подразделению включён' else 'Гейтинг по подразделению выключен' end, coalesce(p_enabled,false);
end $$;

create or replace function public.app_my_department(p_token uuid)
returns table (department_id uuid, department_name text, scope_enabled boolean)
language plpgsql stable security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; ulogin text;
begin
  select s.ulogin into ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select e.department_id, d.name, public.app_dept_scope_get(p_token)
      from public.app_employees e left join public.app_departments d on d.id = e.department_id
     where e.user_login = ulogin and e.tenant_id = ten limit 1;
end $$;

create or replace function public.app_dept_ok(p_token uuid, p_department uuid)
returns boolean
language plpgsql stable security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; ulogin text; mydept uuid;
begin
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  if urole is null then return false; end if;
  if urole in ('admin','owner','manager') then return true; end if;
  if not public.app_dept_scope_get(p_token) then return true; end if;
  ten := public.app_my_tenant(p_token);
  select e.department_id into mydept from public.app_employees e where e.user_login = ulogin and e.tenant_id = ten limit 1;
  if mydept is null or p_department is null then return true; end if;
  return p_department = mydept;
end $$;

-- Переопределяем списки заказов и нарядов с учётом гейтинга по подразделению.
create or replace function public.app_naryad_list(p_token uuid)
returns table (id uuid, number text, title text, order_id uuid, order_number text, route_id uuid, route_number text, wc_name text, assignee text, status text, priority text, plan_hours numeric, fact_hours numeric, ops_total bigint, ops_done bigint, start_date date, due_date date, created_at timestamp with time zone)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select n.id, n.number, n.title, n.order_id, o.number, n.route_id, r.number, w.name, n.assignee, n.status,
           n.priority, n.plan_hours, n.fact_hours,
           (select count(*) from public.app_naryad_ops op where op.naryad_id = n.id),
           (select count(*) from public.app_naryad_ops op where op.naryad_id = n.id and op.done),
           n.start_date, n.due_date, n.created_at
    from public.app_naryads n
    left join public.app_orders o on o.id = n.order_id
    left join public.app_routes r on r.id = n.route_id
    left join public.app_work_centers w on w.id = n.wc_id
    where (urole = 'admin' or n.tenant_id = ten)
      and public.app_dept_ok(p_token, n.department_id)
    order by n.created_at desc;
end $$;

create or replace function public.app_order_list(p_token uuid)
returns table (id uuid, number text, title text, source text, customer text, customer_name text, status text, priority text, due_date date, assignee text, amount numeric, order_type text, created_login text, created_at timestamp with time zone, updated_at timestamp with time zone)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; urole text; ten uuid; all_admin boolean;
begin
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Сессия недействительна'; end if;
  ten := public.app_my_tenant(p_token);
  all_admin := (urole = 'admin');
  return query
    select o.id, o.number, o.title, o.source, o.customer, c.name, o.status, o.priority,
           o.due_date, o.assignee, o.amount, o.order_type, o.created_login, o.created_at, o.updated_at
    from public.app_orders o left join public.app_customers c on c.id = o.customer_id
    where (all_admin or o.tenant_id = ten)
      and (all_admin or public.app_role_is_staff(urole) or o.created_by = uid)
      and public.app_dept_ok(p_token, o.department_id)
    order by o.created_at desc;
end $$;

-- ================= Демо =================
insert into public.app_crm_reminders (tenant_id, deal_id, customer_id, title, due_at, channel, owner_login, created_login)
select 'aaaaaaaa-0000-0000-0000-000000000001', d.id, d.customer_id, 'Позвонить клиенту по КП', now() + interval '1 day', 'call', 'manager', 'owner'
from public.app_deals d
where d.tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001'
  and not exists (select 1 from public.app_crm_reminders where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and title='Позвонить клиенту по КП')
limit 1;

-- ================= База знаний =================
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Продажи','CRM-напоминания и связь с клиентом',
   'R1: напоминания по сделкам (app_crm_reminders: канал call/meeting/email/telegram/sms/task, срок, статус) — список/создание/смена статуса; скан app_crm_reminder_scan рассылает уведомления ответственным по наступившим срокам; контакт с клиентом app_crm_contact_send ставит сообщение в очередь активной интеграции канала (Интеграции: SMTP/Telegram/SMS/webhook).',
   'CRM напоминания сделка контакт email telegram sms интеграции'),
  ('Склад','Генеалогия партий материалов',
   'R3: прослеживаемость «партия → движение → наряд → паспорт». Партии (app_material_lots), связь с нарядами/паспортами (app_lot_trace), движение по партии (app_stock_moves.lot_id). RPC: app_lot_list, app_lot_trace_add, app_lot_trace_list, app_lot_genealogy (цепочка), app_lot_genealogy_by_passport.',
   'склад партия генеалогия прослеживаемость материал наряд паспорт'),
  ('Платформа','Гейтинг данных по подразделению',
   'R4: сквозной доступ по подразделению. Переключатель app_dept_scope_set (владелец/админ), состояние app_dept_scope_get, отдел пользователя app_my_department, проверка app_dept_ok. При включении списки заказов и нарядов фильтруются по подразделению автора; admin/owner/manager и записи без отдела не ограничиваются.',
   'доступ подразделение гейтинг department scope права фильтр')
) as v(category,question,answer,tags)
where not exists (
  select 1 from public.app_knowledge
   where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001'
     and question = v.question
);

-- ================= Права =================
grant execute on function public.app_crm_reminders_list(uuid,text) to anon, authenticated;
grant execute on function public.app_crm_reminder_save(uuid,uuid,uuid,text,timestamptz,text,text) to anon, authenticated;
grant execute on function public.app_crm_reminder_set_status(uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_crm_reminder_scan(uuid) to anon, authenticated;
grant execute on function public.app_crm_contact_send(uuid,uuid,text,text) to anon, authenticated;
grant execute on function public.app_lot_list(uuid,uuid) to anon, authenticated;
grant execute on function public.app_lot_trace_add(uuid,uuid,uuid,uuid,numeric,text) to anon, authenticated;
grant execute on function public.app_lot_trace_list(uuid,uuid) to anon, authenticated;
grant execute on function public.app_lot_genealogy(uuid,uuid) to anon, authenticated;
grant execute on function public.app_lot_genealogy_by_passport(uuid,uuid) to anon, authenticated;
grant execute on function public.app_dept_scope_get(uuid) to anon, authenticated;
grant execute on function public.app_dept_scope_set(uuid,boolean) to anon, authenticated;
grant execute on function public.app_my_department(uuid) to anon, authenticated;
grant execute on function public.app_dept_ok(uuid,uuid) to anon, authenticated;
