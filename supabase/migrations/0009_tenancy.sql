-- ============================================================
-- 3DMP Service · 0009_tenancy.sql  (v1.4.1 — мультитенантность данных)
-- Изоляция по организации (tenant_id): каждый видит только данные своего тенанта.
-- admin (платформа) — видит всё. Поставщики — внешние (витрина + свои КП).
-- Зависит от 0001..0008. public.orders НЕ трогаем.
-- ============================================================

-- ---------- Демо-тенанты ----------
insert into public.tenants (id, name, slug, plan, status) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'ООО «3Д Металлообработка Пресс»', '3dmp', 'business', 'active')
on conflict (id) do nothing;
insert into public.tenants (id, name, slug, plan, status) values
  ('bbbbbbbb-0000-0000-0000-000000000002', 'ООО «Клиент-2»', 'client2', 'business', 'active')
on conflict (id) do nothing;

-- ---------- Тенант у пользователей ----------
alter table public.app_users add column if not exists tenant_id uuid references public.tenants (id);
update public.app_users set tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001' where tenant_id is null;

-- Второй пользователь другого тенанта (для проверки изоляции)
insert into public.app_users (login, password_hash, full_name, role, tenant_id)
values ('client2', extensions.crypt('client2', extensions.gen_salt('bf')), 'Заказчик Клиент-2', 'owner',
        'bbbbbbbb-0000-0000-0000-000000000002')
on conflict (login) do update set tenant_id = 'bbbbbbbb-0000-0000-0000-000000000002', role = 'owner';

-- ---------- tenant_id в бизнес-таблицах ----------
alter table public.app_orders        add column if not exists tenant_id uuid references public.tenants (id);
alter table public.app_naryads       add column if not exists tenant_id uuid references public.tenants (id);
alter table public.app_work_centers  add column if not exists tenant_id uuid references public.tenants (id);
alter table public.app_norms         add column if not exists tenant_id uuid references public.tenants (id);
alter table public.tenders           add column if not exists tenant_id uuid references public.tenants (id);

update public.app_orders       set tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001' where tenant_id is null;
update public.app_naryads      set tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001' where tenant_id is null;
update public.app_work_centers set tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001' where tenant_id is null;
update public.app_norms        set tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001' where tenant_id is null;
update public.tenders          set tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001' where tenant_id is null;

create index if not exists app_orders_tenant_idx   on public.app_orders (tenant_id);
create index if not exists app_naryads_tenant_idx  on public.app_naryads (tenant_id);
create index if not exists tenders_tenant_idx      on public.tenders (tenant_id);

-- ---------- Хелперы тенанта ----------
create or replace function public.app_my_tenant(p_token uuid)
returns uuid language sql security definer set search_path = public
as $$
  select u.tenant_id from public.app_sessions s join public.app_users u on u.id = s.user_id
  where s.token = p_token and s.expires_at > now() and u.active;
$$;

create or replace function public.app_is_platform_admin(p_token uuid)
returns boolean language sql security definer set search_path = public
as $$
  select exists (select 1 from public.app_session_user(p_token) s where s.urole = 'admin');
$$;

-- Уведомления в рамках тенанта
create or replace function public.app_notif_roles_t(p_tenant uuid, p_roles text[], p_title text, p_body text, p_link text)
returns void language sql security definer set search_path = public
as $$
  insert into public.app_notifications (user_id, title, body, link)
  select u.id, left(p_title,200), left(coalesce(p_body,''),500), p_link
  from public.app_users u
  where u.active and u.role = any(p_roles) and (p_tenant is null or u.tenant_id = p_tenant);
$$;

-- ============================================================
--  ЗАЯВКИ (app_orders) — изоляция по тенанту
-- ============================================================
create or replace function public.app_order_create(
  p_token uuid, p_title text, p_description text, p_source text, p_customer text, p_contact text, p_priority text
) returns table (id uuid, number text)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; ulogin text; oid uuid; onum text; ten uuid;
begin
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Сессия недействительна'; end if;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_title), '') = '' then raise exception 'Укажите тему заявки'; end if;

  onum := 'REQ-' || lpad(nextval('public.app_order_seq')::text, 5, '0');
  insert into public.app_orders (number, title, description, source, customer, contact, priority, status, created_by, created_login, tenant_id)
  values (onum, trim(p_title), nullif(trim(p_description),''), nullif(trim(p_source),''), nullif(trim(p_customer),''),
          nullif(trim(p_contact),''), coalesce(nullif(trim(p_priority),''),'normal'), 'new', uid, ulogin, ten)
  returning app_orders.id into oid;

  insert into public.app_order_history (order_id, status, comment, by_login) values (oid, 'new', 'Заявка создана', ulogin);
  perform public.app_notif_roles_t(ten, array['admin','manager','owner'], 'Новая заявка ' || onum, trim(p_title), 'apps/orders/index.html');
  perform public.app_notif_send(uid, 'Заявка ' || onum || ' принята', trim(p_title), 'apps/orders/index.html');
  return query select oid, onum;
end $$;

create or replace function public.app_order_list(p_token uuid)
returns table (id uuid, number text, title text, source text, customer text, status text, priority text,
               created_login text, created_at timestamptz, updated_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; urole text; ten uuid; all_admin boolean;
begin
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Сессия недействительна'; end if;
  ten := public.app_my_tenant(p_token);
  all_admin := (urole = 'admin');
  return query
    select o.id, o.number, o.title, o.source, o.customer, o.status, o.priority, o.created_login, o.created_at, o.updated_at
    from public.app_orders o
    where (all_admin or o.tenant_id = ten)
      and (all_admin or urole in ('owner','manager') or o.created_by = uid)
    order by o.created_at desc;
end $$;

create or replace function public.app_order_get(p_token uuid, p_id uuid)
returns table (id uuid, number text, title text, description text, source text, customer text, contact text,
               status text, priority text, created_login text, created_at timestamptz, updated_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; urole text; ten uuid;
begin
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Сессия недействительна'; end if;
  ten := public.app_my_tenant(p_token);
  return query
    select o.id, o.number, o.title, o.description, o.source, o.customer, o.contact,
           o.status, o.priority, o.created_login, o.created_at, o.updated_at
    from public.app_orders o
    where o.id = p_id
      and (urole = 'admin' or (o.tenant_id = ten and (urole in ('owner','manager') or o.created_by = uid)));
end $$;

create or replace function public.app_order_history_list(p_token uuid, p_id uuid)
returns table (status text, comment text, by_login text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; urole text; ten uuid;
begin
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Сессия недействительна'; end if;
  ten := public.app_my_tenant(p_token);
  return query
    select h.status, h.comment, h.by_login, h.created_at
    from public.app_order_history h join public.app_orders o on o.id = h.order_id
    where h.order_id = p_id
      and (urole = 'admin' or (o.tenant_id = ten and (urole in ('owner','manager') or o.created_by = uid)))
    order by h.created_at;
end $$;

create or replace function public.app_order_set_status(p_token uuid, p_id uuid, p_status text, p_comment text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; ulogin text; urole text; ten uuid; owner uuid; onum text; oten uuid;
begin
  select s.uid, s.ulogin, s.urole into uid, ulogin, urole from public.app_session_user(p_token) s;
  if uid is null then return query select false, 'Сессия недействительна'; return; end if;
  ten := public.app_my_tenant(p_token);
  select o.created_by, o.number, o.tenant_id into owner, onum, oten from public.app_orders o where o.id = p_id;
  if owner is null then return query select false, 'Заявка не найдена'; return; end if;
  if not (urole = 'admin' or (oten = ten and (urole in ('owner','manager') or owner = uid))) then
    return query select false, 'Доступ запрещён'; return;
  end if;
  update public.app_orders set status = p_status, updated_at = now() where id = p_id;
  insert into public.app_order_history (order_id, status, comment, by_login) values (p_id, p_status, nullif(trim(p_comment),''), ulogin);
  if owner <> uid then
    perform public.app_notif_send(owner, 'Заявка ' || onum || ': ' || p_status, coalesce(p_comment,''), 'apps/orders/index.html');
  end if;
  return query select true, 'Статус обновлён';
end $$;

-- ============================================================
--  ЗАКУПКИ (tenders/bids) — витрина открыта поставщикам, управление — по тенанту
-- ============================================================
create or replace function public.app_tender_create(
  p_token uuid, p_title text, p_description text, p_category text, p_material text,
  p_qty numeric, p_unit text, p_customer text, p_deadline date
) returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; tid uuid; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.uid into uid from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_title), '') = '' then raise exception 'Укажите название закупки'; end if;
  insert into public.tenders (title, description, category, material, qty, unit, customer, deadline, status, created_by, tenant_id)
  values (trim(p_title), nullif(trim(p_description),''), nullif(trim(p_category),''), nullif(trim(p_material),''),
          p_qty, nullif(trim(p_unit),''), nullif(trim(p_customer),''), p_deadline, 'open', uid, ten)
  returning tenders.id into tid;
  return query select tid, 'Закупка опубликована';
end $$;

create or replace function public.app_tender_list_full(p_token uuid)
returns table (id uuid, title text, category text, customer text, deadline date, status text,
               bids_count bigint, awarded_bid_id uuid, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select t.id, t.title, t.category, t.customer, t.deadline, t.status,
           (select count(*) from public.bids b where b.tender_id = t.id), t.awarded_bid_id, t.created_at
    from public.tenders t
    where (urole = 'admin' or t.tenant_id = ten)
    order by t.created_at desc;
end $$;

create or replace function public.app_bids_for_tender(p_token uuid, p_tender_id uuid)
returns table (id uuid, supplier_name text, price numeric, term_days integer, comment text, status text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if not (urole = 'admin' or exists (select 1 from public.tenders t where t.id = p_tender_id and t.tenant_id = ten)) then
    raise exception 'Доступ запрещён';
  end if;
  return query select b.id, b.supplier_name, b.price, b.term_days, b.comment, b.status, b.created_at
    from public.bids b where b.tender_id = p_tender_id order by b.price asc, b.created_at;
end $$;

create or replace function public.app_tender_award(p_token uuid, p_tender_id uuid, p_bid_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid; ttitle text; win_user uuid; win_name text; sup record;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select t.title into ttitle from public.tenders t
    where t.id = p_tender_id and (urole = 'admin' or t.tenant_id = ten);
  if ttitle is null then return query select false,'Закупка не найдена'; return; end if;
  select b.app_user_id, b.supplier_name into win_user, win_name from public.bids b where b.id = p_bid_id and b.tender_id = p_tender_id;
  if win_user is null then return query select false,'Предложение не найдено'; return; end if;

  update public.bids set status = case when id = p_bid_id then 'accepted' else 'rejected' end where tender_id = p_tender_id;
  update public.tenders set status = 'awarded', awarded_bid_id = p_bid_id, closed_at = now() where id = p_tender_id;

  for sup in select b.app_user_id from public.bids b where b.tender_id = p_tender_id and b.app_user_id is not null loop
    if sup.app_user_id = win_user then
      perform public.app_notif_send(sup.app_user_id, 'Вы выбраны: ' || ttitle, 'Ваше КП принято', 'apps/supplier/index.html');
    else
      perform public.app_notif_send(sup.app_user_id, 'Закупка ' || ttitle || ': победитель определён', 'Ваше КП отклонено', 'apps/supplier/index.html');
    end if;
  end loop;
  return query select true, 'Победитель: ' || coalesce(win_name,'—');
end $$;

create or replace function public.app_tender_set_status(p_token uuid, p_tender_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  update public.tenders set status = p_status,
         closed_at = case when p_status in ('closed','awarded') then now() else closed_at end
   where id = p_tender_id and (urole = 'admin' or tenant_id = ten);
  return query select true, 'Статус обновлён';
end $$;

-- supplier_submit_bid: уведомляем закупщиков тенанта закупки
create or replace function public.supplier_submit_bid(
  p_token uuid, p_tender_id uuid, p_price numeric, p_term_days integer, p_comment text
) returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; uname text; ttitle text; pstatus text; tten uuid;
begin
  select u.id, coalesce(u.full_name, u.login) into uid, uname
  from public.app_sessions s join public.app_users u on u.id = s.user_id
  where s.token = p_token and s.expires_at > now() and u.active;
  if uid is null then return query select false, 'Сессия недействительна'; return; end if;
  if p_price is null or p_price <= 0 then return query select false, 'Укажите цену больше нуля'; return; end if;

  select p.status into pstatus from public.app_supplier_profiles p where p.app_user_id = uid;
  if pstatus = 'rejected' then return query select false, 'Аккредитация отклонена — подача КП недоступна'; return; end if;

  insert into public.bids (tender_id, app_user_id, supplier_name, price, term_days, comment)
  values (p_tender_id, uid, uname, p_price, p_term_days, nullif(p_comment, ''))
  on conflict (tender_id, app_user_id) do update
    set price = excluded.price, term_days = excluded.term_days, comment = excluded.comment;

  select t.title, t.tenant_id into ttitle, tten from public.tenders t where t.id = p_tender_id;
  perform public.app_notif_roles_t(tten, array['admin','manager','owner'], 'Новое КП: ' || coalesce(ttitle,'закупка'),
          uname || ' · ' || to_char(p_price, 'FM999G999G999G999') || ' ₽', 'apps/procurement/index.html');
  return query select true, 'Предложение сохранено';
end $$;

-- ============================================================
--  ПРОИЗВОДСТВО — изоляция по тенанту
-- ============================================================
create or replace function public.app_wc_list(p_token uuid)
returns table (id uuid, code text, name text, kind text, cost_hour numeric, active boolean)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select w.id, w.code, w.name, w.kind, w.cost_hour, w.active from public.app_work_centers w
    where (urole = 'admin' or w.tenant_id = ten) order by w.name;
end $$;

create or replace function public.app_norms_list(p_token uuid)
returns table (id uuid, operation text, machine_kind text, setup_min numeric, unit_min numeric, rate_hour numeric)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select n.id, n.operation, n.machine_kind, n.setup_min, n.unit_min, n.rate_hour from public.app_norms n
    where (urole = 'admin' or n.tenant_id = ten) order by n.operation;
end $$;

create or replace function public.app_naryad_list(p_token uuid)
returns table (id uuid, number text, title text, order_number text, wc_name text, assignee text,
               status text, plan_hours numeric, fact_hours numeric, due_date date, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select n.id, n.number, n.title, o.number, w.name, n.assignee, n.status, n.plan_hours, n.fact_hours, n.due_date, n.created_at
    from public.app_naryads n
    left join public.app_orders o on o.id = n.order_id
    left join public.app_work_centers w on w.id = n.wc_id
    where (urole = 'admin' or n.tenant_id = ten)
    order by n.created_at desc;
end $$;

create or replace function public.app_naryad_create(
  p_token uuid, p_order_id uuid, p_title text, p_wc_id uuid, p_assignee text, p_due_date date
) returns table (id uuid, number text)
language plpgsql security definer set search_path = public
as $$
declare uid uuid; ulogin text; nid uuid; nnum text; target uuid; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_title), '') = '' then raise exception 'Укажите название наряда'; end if;
  nnum := 'NAR-' || lpad(nextval('public.app_naryad_seq')::text, 5, '0');
  insert into public.app_naryads (number, order_id, title, wc_id, assignee, status, created_by, created_login, tenant_id)
  values (nnum, p_order_id, trim(p_title), p_wc_id, nullif(trim(p_assignee),''), 'open', uid, ulogin, ten)
  returning app_naryads.id into nid;
  perform public.app_notif_roles_t(ten, array['admin','manager','owner'], 'Новый наряд ' || nnum, trim(p_title), 'apps/production/index.html');
  if nullif(trim(p_assignee), '') is not null then
    select u.id into target from public.app_users u
      where lower(u.login) = lower(trim(p_assignee)) and u.active and (u.tenant_id = ten) limit 1;
    if target is not null then
      perform public.app_notif_send(target, 'Вам назначен наряд ' || nnum, trim(p_title), 'apps/production/index.html');
    end if;
  end if;
  return query select nid, nnum;
end $$;

create or replace function public.app_naryad_get(p_token uuid, p_id uuid)
returns table (id uuid, number text, title text, order_id uuid, order_number text, wc_name text, assignee text,
               status text, plan_hours numeric, fact_hours numeric, due_date date, created_login text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select n.id, n.number, n.title, n.order_id, o.number, w.name, n.assignee,
    n.status, n.plan_hours, n.fact_hours, n.due_date, n.created_login, n.created_at
    from public.app_naryads n
    left join public.app_orders o on o.id = n.order_id
    left join public.app_work_centers w on w.id = n.wc_id
    where n.id = p_id and (urole = 'admin' or n.tenant_id = ten);
end $$;

create or replace function public.app_naryad_ops(p_token uuid, p_id uuid)
returns table (id uuid, seq integer, operation text, worker text, plan_hours numeric, fact_hours numeric, done boolean)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select op.id, op.seq, op.operation, op.worker, op.plan_hours, op.fact_hours, op.done
    from public.app_naryad_ops op join public.app_naryads n on n.id = op.naryad_id
    where op.naryad_id = p_id and (urole = 'admin' or n.tenant_id = ten)
    order by op.seq, op.created_at;
end $$;

create or replace function public.app_naryad_add_op(
  p_token uuid, p_naryad_id uuid, p_operation text, p_worker text, p_plan_hours numeric
) returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare seqn integer; nid uuid; urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select n.id into nid from public.app_naryads n where n.id = p_naryad_id and (urole = 'admin' or n.tenant_id = ten);
  if nid is null then return query select false,'Наряд не найден'; return; end if;
  if coalesce(trim(p_operation),'') = '' then return query select false,'Укажите операцию'; return; end if;
  select coalesce(max(op.seq),0)+1 into seqn from public.app_naryad_ops op where op.naryad_id = p_naryad_id;
  insert into public.app_naryad_ops (naryad_id, seq, operation, worker, plan_hours)
  values (p_naryad_id, seqn, trim(p_operation), nullif(trim(p_worker),''), coalesce(p_plan_hours,0));
  update public.app_naryads n set plan_hours = (select coalesce(sum(op.plan_hours),0) from public.app_naryad_ops op where op.naryad_id = n.id),
    status = case when n.status = 'open' then 'in_progress' else n.status end, updated_at = now()
   where n.id = p_naryad_id;
  return query select true,'Операция добавлена';
end $$;

create or replace function public.app_naryad_op_done(p_token uuid, p_op_id uuid, p_fact_hours numeric, p_done boolean)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare nid uuid; urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select op.naryad_id into nid from public.app_naryad_ops op join public.app_naryads n on n.id = op.naryad_id
    where op.id = p_op_id and (urole = 'admin' or n.tenant_id = ten);
  if nid is null then return query select false,'Операция не найдена'; return; end if;
  update public.app_naryad_ops set done = coalesce(p_done, true), fact_hours = coalesce(p_fact_hours, fact_hours) where id = p_op_id;
  update public.app_naryads n set fact_hours = (select coalesce(sum(op.fact_hours),0) from public.app_naryad_ops op where op.naryad_id = n.id),
    updated_at = now() where n.id = nid;
  return query select true,'Обновлено';
end $$;

create or replace function public.app_naryad_close(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare ulogin text; nnum text; urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.ulogin, s.urole into ulogin, urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select n.number into nnum from public.app_naryads n where n.id = p_id and (urole = 'admin' or n.tenant_id = ten);
  if nnum is null then return query select false,'Наряд не найден'; return; end if;
  update public.app_naryads n set status = 'closed', updated_at = now(),
    fact_hours = (select coalesce(sum(op.fact_hours),0) from public.app_naryad_ops op where op.naryad_id = n.id)
   where n.id = p_id;
  perform public.app_notif_roles_t(ten, array['admin','manager','owner'], 'Наряд ' || nnum || ' закрыт', 'Закрыл: ' || coalesce(ulogin,''), 'apps/production/index.html');
  return query select true,'Наряд закрыт';
end $$;

-- ---------- app_me: + tenant ----------
drop function if exists public.app_me(uuid);
create function public.app_me(p_token uuid)
returns table (user_id uuid, login text, full_name text, role text, last_login_at timestamptz, tenant_id uuid, tenant_name text)
language sql security definer set search_path = public
as $$
  select u.id, u.login, u.full_name, u.role, u.last_login_at, u.tenant_id, t.name
  from public.app_sessions s
  join public.app_users u on u.id = s.user_id
  left join public.tenants t on t.id = u.tenant_id
  where s.token = p_token and s.expires_at > now() and u.active;
$$;
grant execute on function public.app_me(uuid) to anon, authenticated;

-- ---------- Привязка демо-закупок к тенанту A ----------
update public.tenders set tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001' where tenant_id is null;
