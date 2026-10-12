-- ============================================================
-- 3DMP Service · 0210_settings_apply2.sql
-- Вторая волна применения настроек мастера в бизнес-логике:
-- orders.default_priority, warehouse.default_min_qty, finance.payment_term_days,
-- safety.briefing_days, kedo.sign_method, qc.require_measure.
-- Идемпотентно. Зависит от 0001..0209.
-- ============================================================

-- ---------- Заявки: приоритет по умолчанию ----------
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
          coalesce(nullif(trim(p_priority), ''), public.app_setting_get(p_token,'orders','default_priority','normal')), 'new', p_due_date, nullif(trim(p_assignee),''),
          p_amount, coalesce(nullif(trim(p_order_type),''),'single'), ten, uid, ulogin)
  returning app_orders.id into oid;
  insert into public.app_order_history (order_id, status, comment, by_login) values (oid, 'new', 'Заявка создана', ulogin);
  perform public.app_notif_roles_t(ten, array['admin','manager','owner'], 'Новая заявка ' || onum, trim(p_title), 'apps/orders/index.html');
  perform public.app_notif_send(uid, 'Заявка ' || onum || ' принята', trim(p_title), 'apps/orders/index.html');
  return query select oid, onum;
end $$;

-- ---------- Материалы: минимальный остаток по умолчанию ----------
create or replace function public.app_material_save(
  p_token uuid, p_id uuid, p_code text, p_name text, p_unit text, p_price numeric, p_min_qty numeric
) returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; def_min numeric;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten := public.app_my_tenant(p_token);
  def_min := coalesce(public.app_setting_get(p_token,'warehouse','default_min_qty',null)::numeric, 0);
  if coalesce(trim(p_name),'') = '' then return query select false,'Укажите наименование'; return; end if;
  if p_id is null then
    insert into public.app_materials (tenant_id, code, name, unit, price, min_qty)
    values (ten, nullif(trim(p_code),''), trim(p_name), nullif(trim(p_unit),''), coalesce(p_price,0), coalesce(p_min_qty, def_min));
  else
    update public.app_materials set code = nullif(trim(p_code),''), name = trim(p_name), unit = nullif(trim(p_unit),''),
      price = coalesce(p_price,0), min_qty = coalesce(p_min_qty, def_min), updated_at = now()
     where id = p_id and (ten is null or tenant_id = ten);
  end if;
  return query select true,'Сохранено';
end $$;

-- ---------- Счета: срок оплаты по умолчанию ----------
create or replace function public.app_invoice_create(p_token uuid, p_order_id uuid, p_customer text, p_amount numeric, p_due_date date, p_note text,
  p_customer_id uuid default null, p_document_id uuid default null, p_assignee text default null)
returns table (id uuid, number text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ulogin text; ten uuid; iid uuid; inum text; cname text; due date;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if coalesce(p_amount,0) <= 0 then raise exception 'Сумма должна быть больше нуля'; end if;
  due := coalesce(p_due_date, current_date + coalesce(public.app_setting_get(p_token,'finance','payment_term_days',null)::int, 14));
  if p_customer_id is not null then
    select c.name into cname from public.app_customers c where c.id = p_customer_id and (ten is null or c.tenant_id = ten);
  end if;
  inum := 'INV-' || lpad(nextval('public.app_invoice_seq')::text, 5, '0');
  insert into public.app_invoices (tenant_id, number, order_id, customer, customer_id, document_id, amount, status, due_date, assignee, note, created_by, created_login)
  values (ten, inum, p_order_id, coalesce(cname, nullif(trim(p_customer),'')), p_customer_id, p_document_id, p_amount, 'draft',
          due, nullif(trim(p_assignee),''), nullif(trim(p_note),''), uid, ulogin)
  returning app_invoices.id into iid;
  return query select iid, inum;
end $$;

-- ---------- Инструктажи: периодичность по умолчанию ----------
create or replace function public.app_briefing_save(p_token uuid, p_id uuid, p_employee text, p_kind text, p_topic text, p_date date, p_instructor text, p_next date, p_note text)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare ten uuid; newid uuid; nd date;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён',null::uuid; return; end if;
  select u.tenant_id into ten from public.app_session_user(p_token) s join public.app_users u on u.id=s.uid;
  if coalesce(trim(p_employee),'')='' then return query select false,'Укажите сотрудника',null::uuid; return; end if;
  nd := coalesce(p_next, coalesce(p_date, current_date) + coalesce(public.app_setting_get(p_token,'safety','briefing_days',null)::int, 180));
  if p_id is null then
    insert into public.app_safety_briefings (tenant_id,employee_login,kind,topic,brief_date,instructor_login,next_date,note)
    values (ten,trim(p_employee),coalesce(nullif(trim(p_kind),''),'repeat'),nullif(trim(p_topic),''),coalesce(p_date,current_date),nullif(trim(p_instructor),''),nd,nullif(trim(p_note),''))
    returning id into newid;
    return query select true,'Инструктаж добавлен',newid;
  else
    update public.app_safety_briefings b set employee_login=trim(p_employee),kind=coalesce(nullif(trim(p_kind),''),b.kind),topic=nullif(trim(p_topic),''),brief_date=coalesce(p_date,b.brief_date),instructor_login=nullif(trim(p_instructor),''),next_date=nd,note=nullif(trim(p_note),'')
     where b.id=p_id and (public.app_is_platform_admin(p_token) or b.tenant_id=ten) returning b.id into newid;
    if newid is null then return query select false,'Не найдено',null::uuid; return; end if;
    return query select true,'Инструктаж сохранён',newid;
  end if;
end $$;

-- ---------- КЭДО: метод подписи по умолчанию ----------
create or replace function public.app_hr_doc_sign(p_token uuid, p_id uuid, p_action text, p_comment text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; uid uuid; uname text; act text; d record; au uuid; meth text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.uid, s.ulogin into uid, uname from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  act := lower(trim(coalesce(p_action,'')));
  if act not in ('send','sign','decline','archive') then return query select false,'Действие: send/sign/decline/archive'; return; end if;
  meth := coalesce(nullif(public.app_setting_get(p_token,'kedo','sign_method',''),''), 'ПЭП');
  select * into d from public.app_hr_docs where id = p_id and (public.app_is_platform_admin(p_token) or tenant_id = ten);
  if d.id is null then return query select false,'Документ не найден'; return; end if;
  if act in ('sign','decline') and not (public.app_is_platform_admin(p_token) or public.app_is_owner(p_token) or d.employee_login = uname) then
    return query select false,'Подпись доступна сотруднику, которому адресован документ'; return;
  end if;
  if act = 'send' then
    update public.app_hr_docs set status='sent', updated_at=now() where id = p_id;
    select u.id into au from public.app_users u where u.login = d.employee_login and u.tenant_id = ten limit 1;
    if au is not null then perform public.app_notif_send(au, 'Кадровый документ на ознакомление', d.title, 'apps/kedo/index.html'); end if;
    return query select true,'Документ отправлен сотруднику';
  elsif act = 'sign' then
    update public.app_hr_docs set status='signed', signed_at=now(), signed_by=uid, sign_method=meth, comment=nullif(trim(p_comment),''), updated_at=now() where id = p_id;
    return query select true,'Документ подписан (' || meth || ')';
  elsif act = 'decline' then
    update public.app_hr_docs set status='declined', comment=nullif(trim(p_comment),''), updated_at=now() where id = p_id;
    return query select true,'Документ отклонён';
  else
    update public.app_hr_docs set status='archived', updated_at=now() where id = p_id;
    return query select true,'Документ в архив';
  end if;
end $$;

-- ---------- ОТК: обязательность измерений ----------
create or replace function public.app_qc_add_line(p_token uuid, p_check_id uuid, p_name text, p_norm text, p_value text, p_result text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; cid uuid; need boolean;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  need := coalesce(public.app_setting_get(p_token,'qc','require_measure','false')::boolean, false);
  select c.id into cid from public.app_qc_checks c where c.id = p_check_id and (urole='admin' or c.tenant_id = ten);
  if cid is null then return query select false,'Чек-лист не найден'; return; end if;
  if coalesce(trim(p_name),'') = '' then return query select false,'Укажите параметр'; return; end if;
  if need and coalesce(trim(p_value),'') = '' then return query select false,'По настройкам требуются измерения: укажите значение'; return; end if;
  insert into public.app_qc_lines (check_id, name, norm, value, result)
  values (cid, trim(p_name), nullif(trim(p_norm),''), nullif(trim(p_value),''), coalesce(nullif(trim(p_result),''),'ok'));
  return query select true,'Позиция добавлена';
end $$;

-- ================= База знаний =================
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Платформа','Применение настроек модулей (вторая волна, 0210)',
   'Настройки мастера применяются: orders.default_priority — приоритет новых заявок; warehouse.default_min_qty — минимальный остаток материала по умолчанию; finance.payment_term_days — срок оплаты счёта по умолчанию; safety.briefing_days — периодичность инструктажа (next_date); kedo.sign_method — метод подписи кадрового документа; qc.require_measure — обязательность измерений в чек-листе.',
   'настройки применение приоритет минимальный остаток срок оплаты инструктаж подпись измерения')
) as v(category,question,answer,tags)
where not exists (
  select 1 from public.app_knowledge
   where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001'
     and question = 'Применение настроек модулей (вторая волна, 0210)'
);

-- ================= Права =================
grant execute on function public.app_order_create(uuid,text,text,text,text,text,text,uuid,date,text,numeric,text) to anon, authenticated;
grant execute on function public.app_material_save(uuid,uuid,text,text,text,numeric,numeric) to anon, authenticated;
grant execute on function public.app_invoice_create(uuid,uuid,text,numeric,date,text,uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_briefing_save(uuid,uuid,text,text,text,date,text,date,text) to anon, authenticated;
grant execute on function public.app_hr_doc_sign(uuid,uuid,text,text) to anon, authenticated;
grant execute on function public.app_qc_add_line(uuid,uuid,text,text,text,text) to anon, authenticated;
