-- ============================================================
-- 3DMP Service · 0033_production_ref.sql  (v16.0 — переработка «Производство»)
-- Наряды: приоритет, план-даты, прогресс операций, связи маршрут/заявка/центр.
-- Операции наряда — из справочника операций. База знаний. Tenant-изоляция.
-- Зависит от 0001..0032.
-- ============================================================

alter table public.app_naryads add column if not exists priority   text not null default 'normal'; -- low|normal|high
alter table public.app_naryads add column if not exists start_date date;
alter table public.app_naryads add column if not exists note       text;

-- ---------- Список нарядов (расширенный) ----------
drop function if exists public.app_naryad_list(uuid);
create or replace function public.app_naryad_list(p_token uuid)
returns table (id uuid, number text, title text, order_id uuid, order_number text, route_id uuid, route_number text,
               wc_name text, assignee text, status text, priority text, plan_hours numeric, fact_hours numeric,
               ops_total bigint, ops_done bigint, start_date date, due_date date, created_at timestamptz)
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
    order by n.created_at desc;
end $$;

-- ---------- Создать наряд ----------
drop function if exists public.app_naryad_create(uuid,uuid,text,uuid,text,date);
create or replace function public.app_naryad_create(
  p_token uuid, p_order_id uuid, p_title text, p_wc_id uuid, p_assignee text, p_due_date date,
  p_priority text default 'normal', p_start_date date default null
) returns table (id uuid, number text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ulogin text; nid uuid; nnum text; target uuid; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_title), '') = '' then raise exception 'Укажите название наряда'; end if;

  nnum := 'NAR-' || lpad(nextval('public.app_naryad_seq')::text, 5, '0');
  insert into public.app_naryads (number, order_id, title, wc_id, assignee, status, priority, start_date, due_date, tenant_id, created_by, created_login)
  values (nnum, p_order_id, trim(p_title), p_wc_id, nullif(trim(p_assignee), ''), 'open',
          coalesce(nullif(trim(p_priority),''),'normal'), p_start_date, p_due_date, ten, uid, ulogin)
  returning app_naryads.id into nid;

  perform public.app_notif_roles_t(ten, array['admin','manager','owner','chief','master'], 'Новый наряд ' || nnum, trim(p_title), 'apps/production/index.html');
  if nullif(trim(p_assignee), '') is not null then
    select u.id into target from public.app_users u where lower(u.login) = lower(trim(p_assignee)) and u.active and u.tenant_id = ten limit 1;
    if target is not null then
      perform public.app_notif_send(target, 'Вам назначен наряд ' || nnum, trim(p_title), 'apps/production/index.html');
    end if;
  end if;
  return query select nid, nnum;
end $$;

-- ---------- Изменить наряд ----------
create or replace function public.app_naryad_update(p_token uuid, p_id uuid, p_assignee text, p_priority text,
  p_wc_id uuid, p_start_date date, p_due_date date, p_note text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if not exists (select 1 from public.app_naryads n where n.id = p_id and (urole='admin' or n.tenant_id = ten)) then
    return query select false,'Наряд не найден'; return;
  end if;
  update public.app_naryads set assignee = nullif(trim(p_assignee),''),
    priority = coalesce(nullif(trim(p_priority),''), priority), wc_id = p_wc_id,
    start_date = p_start_date, due_date = p_due_date, note = nullif(trim(p_note),''), updated_at = now()
   where id = p_id;
  return query select true,'Наряд обновлён';
end $$;

-- ---------- Карточка наряда (с новыми полями) ----------
drop function if exists public.app_naryad_get(uuid,uuid);
drop function if exists public.app_naryad_get(uuid, uuid);
create or replace function public.app_naryad_get(p_token uuid, p_id uuid)
returns table (id uuid, number text, title text, order_id uuid, order_number text, route_id uuid, route_number text,
               wc_id uuid, wc_name text, assignee text, status text, priority text,
               plan_hours numeric, fact_hours numeric, start_date date, due_date date, note text,
               created_login text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select n.id, n.number, n.title, n.order_id, o.number, n.route_id, r.number,
    n.wc_id, w.name, n.assignee, n.status, n.priority,
    n.plan_hours, n.fact_hours, n.start_date, n.due_date, n.note, n.created_login, n.created_at
    from public.app_naryads n
    left join public.app_orders o on o.id = n.order_id
    left join public.app_routes r on r.id = n.route_id
    left join public.app_work_centers w on w.id = n.wc_id
    where n.id = p_id and (urole = 'admin' or n.tenant_id = ten);
end $$;

-- ---------- Операции наряда (с связью на операцию/шаг маршрута) ----------
drop function if exists public.app_naryad_ops(uuid,uuid);
drop function if exists public.app_naryad_ops(uuid, uuid);
create or replace function public.app_naryad_ops(p_token uuid, p_id uuid)
returns table (id uuid, seq integer, operation text, operation_id uuid, route_step_id uuid, worker text,
               plan_hours numeric, fact_hours numeric, done boolean)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if not exists (select 1 from public.app_naryads n where n.id = p_id and (urole='admin' or n.tenant_id = ten)) then
    raise exception 'Доступ запрещён';
  end if;
  return query select op.id, op.seq, op.operation, op.operation_id, op.route_step_id, op.worker, op.plan_hours, op.fact_hours, op.done
    from public.app_naryad_ops op where op.naryad_id = p_id order by op.seq, op.created_at;
end $$;

drop function if exists public.app_naryad_add_op(uuid,uuid,text,text,numeric);
create or replace function public.app_naryad_add_op(p_token uuid, p_naryad_id uuid, p_operation text, p_worker text, p_plan_hours numeric,
  p_operation_id uuid default null, p_route_step_id uuid default null)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare seqn integer; nid uuid; urole text; ten uuid; oname text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select n.id into nid from public.app_naryads n where n.id = p_naryad_id and (urole='admin' or n.tenant_id = ten);
  if nid is null then return query select false,'Наряд не найден'; return; end if;
  oname := nullif(trim(p_operation),'');
  if oname is null and p_operation_id is not null then
    select o.name into oname from public.app_operations o where o.id = p_operation_id;
  end if;
  if oname is null then return query select false,'Укажите операцию'; return; end if;

  select coalesce(max(op.seq),0)+1 into seqn from public.app_naryad_ops op where op.naryad_id = p_naryad_id;
  insert into public.app_naryad_ops (naryad_id, seq, operation, operation_id, route_step_id, worker, plan_hours)
  values (p_naryad_id, seqn, oname, p_operation_id, p_route_step_id, nullif(trim(p_worker),''), coalesce(p_plan_hours,0));

  update public.app_naryads n set plan_hours = (select coalesce(sum(op.plan_hours),0) from public.app_naryad_ops op where op.naryad_id = n.id),
    status = case when n.status = 'open' then 'in_progress' else n.status end, updated_at = now()
   where n.id = p_naryad_id;
  return query select true,'Операция добавлена';
end $$;

-- ---------- Отметить операцию выполненной ----------
create or replace function public.app_naryad_op_done(p_token uuid, p_op_id uuid, p_fact_hours numeric, p_done boolean)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare nid uuid; nnum text; left_c integer; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select op.naryad_id into nid from public.app_naryad_ops op where op.id = p_op_id;
  if nid is null then return query select false,'Операция не найдена'; return; end if;
  update public.app_naryad_ops set done = coalesce(p_done, true), fact_hours = coalesce(p_fact_hours, fact_hours) where id = p_op_id;
  update public.app_naryads n set fact_hours = (select coalesce(sum(op.fact_hours),0) from public.app_naryad_ops op where op.naryad_id = n.id),
    updated_at = now() where n.id = nid;

  select n.number, n.tenant_id into nnum, ten from public.app_naryads n where n.id = nid;
  select count(*) into left_c from public.app_naryad_ops op where op.naryad_id = nid and not op.done;
  if left_c = 0 then
    perform public.app_notif_roles_t(ten, array['admin','manager','owner','chief','master'], 'Наряд ' || nnum || ': все операции выполнены', 'Можно закрывать', 'apps/production/index.html');
  end if;
  return query select true,'Обновлено';
end $$;

grant execute on function public.app_naryad_list(uuid) to anon, authenticated;
grant execute on function public.app_naryad_get(uuid,uuid) to anon, authenticated;
grant execute on function public.app_naryad_create(uuid,uuid,text,uuid,text,date,text,date) to anon, authenticated;
grant execute on function public.app_naryad_update(uuid,uuid,text,text,uuid,date,date,text) to anon, authenticated;
grant execute on function public.app_naryad_ops(uuid,uuid) to anon, authenticated;
grant execute on function public.app_naryad_add_op(uuid,uuid,text,text,numeric,uuid,uuid) to anon, authenticated;

-- ---------- База знаний: производство ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Производство','Как создать наряд и операции?',
   'В «Производстве» → «Новый наряд»: укажите заявку, название, рабочий центр, исполнителя, приоритет, план-даты. Можно создать наряд сразу из маршрута (кнопка в «Справочниках» → «Маршруты») — тогда операции и нормо-часы появятся автоматически. Операции можно добавлять и вручную, выбирая из справочника операций.',
   'наряд операции маршрут справочник создать'),
  ('Производство','Как учитывать факт и закрывать наряд?',
   'По каждой операции вносится факт часов и отметка «выполнено». Факт суммируется в наряде. Когда все операции выполнены — приходит уведомление «можно закрывать»; наряд закрывается кнопкой «Закрыть». План/факт часов — основа экономики и MES.',
   'факт часы закрыть наряд операции выполнение'),
  ('Производство','Приоритет и план-даты наряда',
   'Приоритет (низкий/обычный/высокий) и план-даты (старт/срок) используются планированием и диспетчерской: по ним строится Гант и очередь работ. Срок наряда связан со сроком заявки.',
   'приоритет план-даты срок старт планирование')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and category='Производство');
