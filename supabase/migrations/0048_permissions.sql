-- ============================================================
-- 3DMP Service · 0048_permissions.sql  (v30.0 — серверная матрица прав)
-- app_can(module, action): серверная проверка прав по матрице app_role_permissions.
-- Правило: admin/owner — всё; иначе по строке матрицы; если строки нет — просмотр разрешён, правка запрещена.
-- Внедрение в модуль «Заявки» (create/update/status). База знаний. Зависит от 0001..0047.
-- ============================================================

-- ---------- Сидирование роли manager (широкие права для совместимости) ----------
insert into public.app_role_permissions (tenant_id, role, module_id, can_view, can_edit)
select 'aaaaaaaa-0000-0000-0000-000000000001', 'manager', m.module_id, true, true
from (values
  ('panel'),('dashboard'),('guide'),('modules'),('eco'),('orders'),('supplier'),('procurement'),('docs'),
  ('registry'),('bom'),('assistant'),('production'),('mes'),('planning'),('warehouse'),('qc'),('passport'),('quality'),
  ('economics'),('finance'),('bi'),('reports'),('hr'),('org'),('api')
) as m(module_id)
where not exists (
  select 1 from public.app_role_permissions
  where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and role='manager' and module_id = m.module_id
);

-- ---------- Проверка прав ----------
create or replace function public.app_can(p_token uuid, p_module text, p_action text)
returns boolean
language plpgsql stable security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; vw boolean; ed boolean;
begin
  select s.urole into urole from public.app_session_user(p_token) s;
  if urole is null then return false; end if;
  if urole in ('admin','owner') then return true; end if;
  ten := public.app_my_tenant(p_token);
  select p.can_view, p.can_edit into vw, ed
    from public.app_role_permissions p
    where p.role = urole and p.module_id = p_module and (p.tenant_id = ten or p.tenant_id is null)
    limit 1;
  if found then
    return case when lower(coalesce(p_action,'view')) = 'edit' then ed else vw end;
  end if;
  -- строки нет: просмотр разрешён, правка — нет
  return lower(coalesce(p_action,'view')) <> 'edit';
end $$;

create or replace function public.app_can_view(p_token uuid, p_module text)
returns boolean language sql stable as $$ select public.app_can(p_token, p_module, 'view') $$;

create or replace function public.app_can_edit(p_token uuid, p_module text)
returns boolean language sql stable as $$ select public.app_can(p_token, p_module, 'edit') $$;

-- ---------- Права текущего пользователя (для UI) ----------
create or replace function public.app_my_permissions(p_token uuid)
returns table (module_id text, can_view boolean, can_edit boolean)
language plpgsql stable security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  select s.urole into urole from public.app_session_user(p_token) s;
  if urole is null then return; end if;
  ten := public.app_my_tenant(p_token);
  if urole in ('admin','owner') then
    return query select distinct p.module_id, true, true
      from public.app_role_permissions p where p.tenant_id = ten;
    return;
  end if;
  return query select p.module_id, p.can_view, p.can_edit
    from public.app_role_permissions p
    where p.role = urole and (p.tenant_id = ten or p.tenant_id is null);
end $$;

grant execute on function public.app_can(uuid,text,text) to anon, authenticated;
grant execute on function public.app_can_view(uuid,text) to anon, authenticated;
grant execute on function public.app_can_edit(uuid,text) to anon, authenticated;
grant execute on function public.app_my_permissions(uuid) to anon, authenticated;

-- ============================================================
--  Внедрение в модуль «Заявки»
-- ============================================================
create or replace function public.app_order_create(
  p_token uuid, p_title text, p_description text, p_source text, p_customer text, p_contact text, p_priority text,
  p_customer_id uuid default null, p_due_date date default null, p_assignee text default null,
  p_amount numeric default null, p_order_type text default 'single'
) returns table (id uuid, number text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ulogin text; oid uuid; onum text; ten uuid; cname text;
begin
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Сессия недействительна'; end if;
  if not public.app_can(p_token, 'orders', 'edit') then raise exception 'Недостаточно прав'; end if;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_title), '') = '' then raise exception 'Укажите тему заявки'; end if;

  if p_customer_id is not null then
    select c.name into cname from public.app_customers c where c.id = p_customer_id and (ten is null or c.tenant_id = ten);
  end if;

  onum := 'REQ-' || lpad(nextval('public.app_order_seq')::text, 5, '0');
  insert into public.app_orders (number, title, description, source, customer, customer_id, contact, priority,
                                 status, due_date, assignee, amount, order_type, tenant_id, created_by, created_login)
  values (onum, trim(p_title), nullif(trim(p_description), ''), nullif(trim(p_source), ''),
          coalesce(cname, nullif(trim(p_customer),'')), p_customer_id, nullif(trim(p_contact), ''),
          coalesce(nullif(trim(p_priority), ''), 'normal'), 'new', p_due_date, nullif(trim(p_assignee),''),
          p_amount, coalesce(nullif(trim(p_order_type),''),'single'), ten, uid, ulogin)
  returning app_orders.id into oid;

  insert into public.app_order_history (order_id, status, comment, by_login) values (oid, 'new', 'Заявка создана', ulogin);
  perform public.app_notif_roles_t(ten, array['admin','manager','owner'], 'Новая заявка ' || onum, trim(p_title), 'apps/orders/index.html');
  perform public.app_notif_send(uid, 'Заявка ' || onum || ' принята', trim(p_title), 'apps/orders/index.html');
  return query select oid, onum;
end $$;

create or replace function public.app_order_update(p_token uuid, p_id uuid, p_title text, p_description text,
  p_priority text, p_customer_id uuid, p_contact text, p_due_date date, p_assignee text, p_amount numeric, p_order_type text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ulogin text; urole text; ten uuid; cname text;
begin
  select s.uid, s.ulogin, s.urole into uid, ulogin, urole from public.app_session_user(p_token) s;
  if uid is null then return query select false,'Сессия недействительна'; return; end if;
  if not public.app_can(p_token, 'orders', 'edit') then return query select false,'Недостаточно прав'; return; end if;
  ten := public.app_my_tenant(p_token);
  if not exists (select 1 from public.app_orders o where o.id = p_id and (urole='admin' or (o.tenant_id = ten and (urole in ('owner','manager') or o.created_by = uid)))) then
    return query select false,'Заявка не найдена'; return;
  end if;
  if coalesce(trim(p_title),'') = '' then return query select false,'Укажите тему заявки'; return; end if;

  cname := null;
  if p_customer_id is not null then
    select c.name into cname from public.app_customers c where c.id = p_customer_id and (ten is null or c.tenant_id = ten);
  end if;

  update public.app_orders set title = trim(p_title), description = nullif(trim(p_description),''),
    priority = coalesce(nullif(trim(p_priority),''), priority), customer_id = p_customer_id,
    customer = coalesce(cname, customer), contact = nullif(trim(p_contact),''), due_date = p_due_date,
    assignee = nullif(trim(p_assignee),''), amount = p_amount,
    order_type = coalesce(nullif(trim(p_order_type),''), order_type), updated_at = now()
   where id = p_id;

  insert into public.app_order_history (order_id, status, comment, by_login)
  select p_id, o.status, 'Заявка изменена', ulogin from public.app_orders o where o.id = p_id;
  return query select true,'Заявка обновлена';
end $$;

create or replace function public.app_order_set_status(p_token uuid, p_id uuid, p_status text, p_comment text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ulogin text; urole text; ten uuid; owner uuid; onum text; oten uuid;
begin
  select s.uid, s.ulogin, s.urole into uid, ulogin, urole from public.app_session_user(p_token) s;
  if uid is null then return query select false, 'Сессия недействительна'; return; end if;
  if not public.app_can(p_token, 'orders', 'edit') then return query select false, 'Недостаточно прав'; return; end if;
  ten := public.app_my_tenant(p_token);
  select o.created_by, o.number, o.tenant_id into owner, onum, oten from public.app_orders o where o.id = p_id;
  if owner is null then return query select false, 'Заявка не найдена'; return; end if;
  if not (urole = 'admin' or (oten = ten and (public.app_role_is_staff(urole) or owner = uid))) then
    return query select false, 'Доступ запрещён'; return;
  end if;
  update public.app_orders set status = p_status, updated_at = now() where id = p_id;
  insert into public.app_order_history (order_id, status, comment, by_login) values (p_id, p_status, nullif(trim(p_comment),''), ulogin);
  if owner <> uid then
    perform public.app_notif_send(owner, 'Заявка ' || onum || ': ' || p_status, coalesce(p_comment,''), 'apps/orders/index.html');
  end if;
  return query select true, 'Статус обновлён';
end $$;

-- ---------- База знаний: права ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Роли','Как работает серверная проверка прав (app_can)?',
   'Права проверяются на сервере: функция app_can(модуль, действие) смотрит матрицу app_role_permissions. Владелец и администратор имеют все права; остальные — по строке матрицы. Если строки нет — просмотр разрешён, правка запрещена. Мутирующие операции модулей (например, создание/изменение заявки) выполняются только при праве «правка» на модуль.',
   'права app_can матрица роль модуль правка')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Как работает серверная проверка прав (app_can)?');
