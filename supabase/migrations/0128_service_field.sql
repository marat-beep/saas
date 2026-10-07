-- ============================================================
-- 3DMP Service · 0128_service_field.sql  (S6 — спецификации/шаблоны, паспорт с выезда)
-- Спецификация к заявке, шаблоны (чек-листы/работы), создание цифрового
-- паспорта станка инженером на выезде. Идемпотентно. Зависит от 0001..0127.
-- ============================================================

create table if not exists public.app_service_templates (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  kind          text not null default 'checklist',  -- checklist|works|act|note
  title         text not null,
  body          text,
  active        boolean not null default true,
  created_login text,
  created_at    timestamptz not null default now()
);
create index if not exists app_service_templates_idx on public.app_service_templates (tenant_id, kind, active);
alter table public.app_service_templates enable row level security;

-- ---------- Шаблоны ----------
drop function if exists public.app_service_templates_list(uuid);
create or replace function public.app_service_templates_list(p_token uuid)
returns table (id uuid, kind text, title text, body text, active boolean)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  select s.urole into urole from public.app_session_user(p_token) s;
  if urole is null then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token);
  return query select t.id, t.kind, t.title, t.body, t.active
    from public.app_service_templates t
    where t.active and (urole='admin' or t.tenant_id = ten)
    order by t.kind, t.title;
end $$;

drop function if exists public.app_service_template_save(uuid,uuid,text,text,text,boolean);
create or replace function public.app_service_template_save(
  p_token uuid, p_id uuid, p_kind text, p_title text, p_body text, p_active boolean
) returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ulogin text; ten uuid; tid uuid;
begin
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  if uid is null then return query select false, 'Сессия недействительна', null::uuid; return; end if;
  if not public.app_can(p_token,'service','edit') then return query select false, 'Нет прав', null::uuid; return; end if;
  if coalesce(trim(p_title),'')='' then return query select false, 'Укажите название шаблона', null::uuid; return; end if;
  ten := public.app_my_tenant(p_token);
  if p_id is null then
    insert into public.app_service_templates (tenant_id, kind, title, body, active, created_login)
    values (ten, coalesce(nullif(trim(p_kind),''),'checklist'), trim(p_title), nullif(trim(p_body),''), coalesce(p_active,true), ulogin)
    returning app_service_templates.id into tid;
  else
    update public.app_service_templates t set kind=coalesce(nullif(trim(p_kind),''),t.kind), title=trim(p_title),
      body=nullif(trim(p_body),''), active=coalesce(p_active,t.active)
     where t.id=p_id and (public.app_is_platform_admin(p_token) or t.tenant_id=ten);
    if not found then return query select false, 'Шаблон не найден', null::uuid; return; end if;
    tid := p_id;
  end if;
  return query select true, 'Шаблон сохранён', tid;
end $$;

drop function if exists public.app_service_template_delete(uuid,uuid);
create or replace function public.app_service_template_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ten uuid;
begin
  select s.uid into uid from public.app_session_user(p_token) s;
  if uid is null then return query select false, 'Сессия недействительна'; return; end if;
  if not public.app_can(p_token,'service','edit') then return query select false, 'Нет прав'; return; end if;
  ten := public.app_my_tenant(p_token);
  update public.app_service_templates set active=false where id=p_id and (public.app_is_platform_admin(p_token) or tenant_id=ten);
  if not found then return query select false, 'Шаблон не найден'; return; end if;
  return query select true, 'Шаблон удалён';
end $$;

-- ---------- Спецификация к заявке ----------
drop function if exists public.app_service_spec(uuid,uuid);
create or replace function public.app_service_spec(p_token uuid, p_id uuid)
returns table (kind text, name text, qty numeric, price numeric, cost numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; r record;
begin
  select s.urole into urole from public.app_session_user(p_token) s;
  if urole is null then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token);
  select s.works, s.solution, s.cost, s.parts_cost, s.labor_hours into r
    from public.app_service_requests s where s.id=p_id and (urole='admin' or s.tenant_id=ten);
  if not found then return; end if;
  return query select 'work'::text, coalesce(nullif(trim(r.works),''),'Работы по заявке'), coalesce(r.labor_hours,1), null::numeric, coalesce(r.cost,0);
  return query
    select 'part'::text, coalesce(sp.part_name,''), sp.qty, sp.price, sp.cost
      from public.app_service_parts sp where sp.request_id = p_id
     order by sp.created_at;
end $$;

-- ---------- Создать цифровой паспорт станка с выезда ----------
drop function if exists public.app_service_equipment_create(uuid,text,text,text,text,text,uuid,text,date);
create or replace function public.app_service_equipment_create(
  p_token uuid, p_name text, p_code text, p_kind text, p_model text, p_dept text,
  p_customer_id uuid default null, p_warranty_number text default null, p_warranty_end date default null
) returns table (ok boolean, message text, equipment_id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ulogin text; ten uuid; eid uuid;
begin
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  if uid is null then return query select false, 'Сессия недействительна', null::uuid; return; end if;
  if not public.app_can(p_token,'service','edit') then return query select false, 'Нет прав', null::uuid; return; end if;
  if coalesce(trim(p_name),'')='' then return query select false, 'Укажите название станка', null::uuid; return; end if;
  ten := public.app_my_tenant(p_token);
  insert into public.app_equipment (tenant_id, name, code, kind, model, dept, status)
  values (ten, trim(p_name), nullif(trim(p_code),''), coalesce(nullif(trim(p_kind),''),'frezerny'), nullif(trim(p_model),''), nullif(trim(p_dept),''), 'active')
  returning app_equipment.id into eid;
  if coalesce(trim(p_warranty_number),'') <> '' or p_warranty_end is not null then
    insert into public.app_warranties (tenant_id, equipment_id, customer_id, number, provider, start_date, end_date, active, created_login)
    values (ten, eid, p_customer_id, nullif(trim(p_warranty_number),''), 'manufacturer', current_date, p_warranty_end, true, ulogin);
  end if;
  return query select true, 'Паспорт станка создан', eid;
end $$;

drop function if exists public.app_service_equipment_link(uuid,uuid,uuid);
create or replace function public.app_service_equipment_link(p_token uuid, p_id uuid, p_equipment_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ulogin text; ten uuid; ename text;
begin
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  if uid is null then return query select false, 'Сессия недействительна'; return; end if;
  if not public.app_can(p_token,'service','edit') then return query select false, 'Нет прав'; return; end if;
  ten := public.app_my_tenant(p_token);
  if not exists (select 1 from public.app_service_requests r where r.id=p_id and (public.app_is_platform_admin(p_token) or r.tenant_id=ten)) then
    return query select false, 'Заявка не найдена'; return; end if;
  select e.name into ename from public.app_equipment e where e.id=p_equipment_id and (public.app_is_platform_admin(p_token) or e.tenant_id=ten);
  if ename is null then return query select false, 'Оборудование не найдено'; return; end if;
  update public.app_service_requests set equipment_id=p_equipment_id, updated_at=now() where id=p_id;
  insert into public.app_service_history (tenant_id, request_id, kind, text, by_login)
  values (ten, p_id, 'event', 'Привязан станок: ' || ename, ulogin);
  return query select true, 'Станок привязан к заявке';
end $$;

grant execute on function public.app_service_templates_list(uuid)                          to anon, authenticated;
grant execute on function public.app_service_template_save(uuid,uuid,text,text,text,boolean) to anon, authenticated;
grant execute on function public.app_service_template_delete(uuid,uuid)                    to anon, authenticated;
grant execute on function public.app_service_spec(uuid,uuid)                               to anon, authenticated;
grant execute on function public.app_service_equipment_create(uuid,text,text,text,text,text,uuid,text,date) to anon, authenticated;
grant execute on function public.app_service_equipment_link(uuid,uuid,uuid)                to anon, authenticated;

-- ---------- Демо-шаблоны (тенант A) ----------
insert into public.app_service_templates (tenant_id, kind, title, body, active, created_login)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.kind, v.title, v.body, true, 'service'
from (values
  ('checklist','Чек-лист ТО-1 шпиндельного узла', E'Проверить уровень смазки\nОсмотреть ремень/привод\nПроверить биение шпинделя\nПроверить давление СОЖ\nТест-прогон на оборотах'),
  ('checklist','Чек-лист диагностики вибрации', E'Замер вибрации (мм/с)\nПроверить затяжку опор\nОсмотреть подшипники\nПроверить балансировку инструмента'),
  ('works','Работы: замена подшипников шпинделя', 'Демонтаж узла, замена подшипников, регулировка, тест-прогон'),
  ('act','Акт: гарантийный ремонт', 'Ремонт выполнен в рамках гарантии, замена узла, калибровка, станок запущен.')
) as v(kind,title,body)
where not exists (
  select 1 from public.app_service_templates t
   where t.tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and t.title = v.title
);

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Сервис','Спецификации, шаблоны и паспорт станка с выезда',
   'Спецификация к заявке (app_service_spec): работы + запчасти со стоимостями, выгрузка PDF. Шаблоны (app_service_templates): чек-листы, типовые работы, акты — применяются к заявке (добавляются в историю). Цифровой паспорт станка может создать инженер прямо на выезде: app_service_equipment_create (оборудование + опц. гарантия) и привязать к заявке app_service_equipment_link — история обслуживания ведётся с этого момента. Для планшета/телефона интерфейс адаптивен, крупные кнопки статусов, офлайн-очередь.',
   'сервис спецификация шаблон чек-лист паспорт станка мобильный планшет выезд инженер')
) as v(category,question,answer,tags)
where not exists (
  select 1 from public.app_knowledge
   where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001' and question = 'Спецификации, шаблоны и паспорт станка с выезда'
);
