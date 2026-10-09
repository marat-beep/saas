-- ============================================================
-- 3DMP Service · 0168_ehs.sql  (W21 — Охрана труда / EHS)
-- Инструктажи, наряды-допуски, СИЗ, медосмотры, инциденты; KPI.
-- Идемпотентно. Зависит от 0001..0167.
-- ============================================================

create table if not exists public.app_safety_briefings (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants (id),
  employee_login text, kind text not null default 'repeat', topic text,
  brief_date date not null default current_date, instructor_login text, next_date date, note text,
  created_at timestamptz not null default now()
);
alter table public.app_safety_briefings enable row level security;

create table if not exists public.app_work_permits (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants (id),
  number text, work_type text not null default 'hot', location text,
  responsible_login text, workers text, valid_from date, valid_to date,
  status text not null default 'draft', note text, created_login text, created_at timestamptz not null default now()
);
alter table public.app_work_permits enable row level security;

create table if not exists public.app_ppe (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants (id),
  employee_login text, item text not null, size text, issued_at date default current_date,
  due_at date, status text not null default 'issued', note text, created_at timestamptz not null default now()
);
alter table public.app_ppe enable row level security;

create table if not exists public.app_medical_checks (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants (id),
  employee_login text, kind text not null default 'periodic', check_date date default current_date,
  next_date date, result text default 'fit', clinic text, note text, created_at timestamptz not null default now()
);
alter table public.app_medical_checks enable row level security;

create table if not exists public.app_safety_incidents (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants (id),
  kind text not null default 'incident', event_date date default current_date, location text,
  description text, severity text default 'low', status text not null default 'open',
  actions text, created_login text, created_at timestamptz not null default now()
);
alter table public.app_safety_incidents enable row level security;

-- ---------- Инструктажи ----------
create or replace function public.app_briefing_list(p_token uuid)
returns table (id uuid, employee_login text, kind text, topic text, brief_date date, instructor_login text, next_date date)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query select b.id,b.employee_login,b.kind,b.topic,b.brief_date,b.instructor_login,b.next_date from public.app_safety_briefings b where adm or b.tenant_id=ten order by b.brief_date desc;
end $$;

create or replace function public.app_briefing_save(p_token uuid, p_id uuid, p_employee text, p_kind text, p_topic text, p_date date, p_instructor text, p_next date, p_note text)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare ten uuid; newid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён',null::uuid; return; end if;
  select u.tenant_id into ten from public.app_session_user(p_token) s join public.app_users u on u.id=s.uid;
  if coalesce(trim(p_employee),'')='' then return query select false,'Укажите сотрудника',null::uuid; return; end if;
  if p_id is null then
    insert into public.app_safety_briefings (tenant_id,employee_login,kind,topic,brief_date,instructor_login,next_date,note)
    values (ten,trim(p_employee),coalesce(nullif(trim(p_kind),''),'repeat'),nullif(trim(p_topic),''),coalesce(p_date,current_date),nullif(trim(p_instructor),''),p_next,nullif(trim(p_note),''))
    returning id into newid;
    return query select true,'Инструктаж добавлен',newid;
  else
    update public.app_safety_briefings b set employee_login=trim(p_employee),kind=coalesce(nullif(trim(p_kind),''),b.kind),topic=nullif(trim(p_topic),''),brief_date=coalesce(p_date,b.brief_date),instructor_login=nullif(trim(p_instructor),''),next_date=p_next,note=nullif(trim(p_note),'')
     where b.id=p_id and (public.app_is_platform_admin(p_token) or b.tenant_id=ten) returning b.id into newid;
    if newid is null then return query select false,'Не найдено',null::uuid; return; end if;
    return query select true,'Инструктаж сохранён',newid;
  end if;
end $$;

create or replace function public.app_briefing_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare ten uuid; n integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten := public.app_my_tenant(p_token);
  delete from public.app_safety_briefings b where b.id=p_id and (public.app_is_platform_admin(p_token) or b.tenant_id=ten);
  get diagnostics n=row_count; if n=0 then return query select false,'Не найдено'; return; end if;
  return query select true,'Удалено';
end $$;

-- ---------- Наряды-допуски ----------
create or replace function public.app_permit_list(p_token uuid)
returns table (id uuid, number text, work_type text, location text, responsible_login text, valid_from date, valid_to date, status text)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query select p.id,p.number,p.work_type,p.location,p.responsible_login,p.valid_from,p.valid_to,p.status from public.app_work_permits p where adm or p.tenant_id=ten order by p.created_at desc;
end $$;

create or replace function public.app_permit_save(p_token uuid, p_id uuid, p_number text, p_work_type text, p_location text, p_responsible text, p_workers text, p_from date, p_to date, p_note text)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare ten uuid; newid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён',null::uuid; return; end if;
  select u.tenant_id into ten from public.app_session_user(p_token) s join public.app_users u on u.id=s.uid;
  if p_id is null then
    insert into public.app_work_permits (tenant_id,number,work_type,location,responsible_login,workers,valid_from,valid_to,note)
    values (ten,nullif(trim(p_number),''),coalesce(nullif(trim(p_work_type),''),'hot'),nullif(trim(p_location),''),nullif(trim(p_responsible),''),nullif(trim(p_workers),''),p_from,p_to,nullif(trim(p_note),''))
    returning id into newid;
    return query select true,'Наряд-допуск создан',newid;
  else
    update public.app_work_permits p set number=nullif(trim(p_number),''),work_type=coalesce(nullif(trim(p_work_type),''),p.work_type),location=nullif(trim(p_location),''),responsible_login=nullif(trim(p_responsible),''),workers=nullif(trim(p_workers),''),valid_from=p_from,valid_to=p_to,note=nullif(trim(p_note),'')
     where p.id=p_id and (public.app_is_platform_admin(p_token) or p.tenant_id=ten) returning p.id into newid;
    if newid is null then return query select false,'Не найдено',null::uuid; return; end if;
    return query select true,'Наряд-допуск сохранён',newid;
  end if;
end $$;

create or replace function public.app_permit_set_status(p_token uuid, p_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare ten uuid; st text; n integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten := public.app_my_tenant(p_token);
  st := lower(trim(coalesce(p_status,'')));
  if st not in ('draft','approved','active','closed','cancelled') then return query select false,'Недопустимый статус'; return; end if;
  update public.app_work_permits p set status=st where p.id=p_id and (public.app_is_platform_admin(p_token) or p.tenant_id=ten);
  get diagnostics n=row_count; if n=0 then return query select false,'Не найдено'; return; end if;
  return query select true,'Статус: '||st;
end $$;

-- ---------- СИЗ ----------
create or replace function public.app_ppe_list(p_token uuid)
returns table (id uuid, employee_login text, item text, size text, issued_at date, due_at date, status text)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query select p.id,p.employee_login,p.item,p.size,p.issued_at,p.due_at,p.status from public.app_ppe p where adm or p.tenant_id=ten order by p.due_at nulls last;
end $$;

create or replace function public.app_ppe_save(p_token uuid, p_id uuid, p_employee text, p_item text, p_size text, p_issued date, p_due date, p_status text, p_note text)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare ten uuid; newid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён',null::uuid; return; end if;
  select u.tenant_id into ten from public.app_session_user(p_token) s join public.app_users u on u.id=s.uid;
  if coalesce(trim(p_item),'')='' then return query select false,'Укажите СИЗ',null::uuid; return; end if;
  if p_id is null then
    insert into public.app_ppe (tenant_id,employee_login,item,size,issued_at,due_at,status,note)
    values (ten,nullif(trim(p_employee),''),left(trim(p_item),160),nullif(trim(p_size),''),coalesce(p_issued,current_date),p_due,coalesce(nullif(trim(p_status),''),'issued'),nullif(trim(p_note),''))
    returning id into newid;
    return query select true,'СИЗ добавлено',newid;
  else
    update public.app_ppe p set employee_login=nullif(trim(p_employee),''),item=left(trim(p_item),160),size=nullif(trim(p_size),''),issued_at=coalesce(p_issued,p.issued_at),due_at=p_due,status=coalesce(nullif(trim(p_status),''),p.status),note=nullif(trim(p_note),'')
     where p.id=p_id and (public.app_is_platform_admin(p_token) or p.tenant_id=ten) returning p.id into newid;
    if newid is null then return query select false,'Не найдено',null::uuid; return; end if;
    return query select true,'СИЗ сохранено',newid;
  end if;
end $$;

create or replace function public.app_ppe_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare ten uuid; n integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten := public.app_my_tenant(p_token);
  delete from public.app_ppe p where p.id=p_id and (public.app_is_platform_admin(p_token) or p.tenant_id=ten);
  get diagnostics n=row_count; if n=0 then return query select false,'Не найдено'; return; end if;
  return query select true,'Удалено';
end $$;

-- ---------- Медосмотры ----------
create or replace function public.app_medical_list(p_token uuid)
returns table (id uuid, employee_login text, kind text, check_date date, next_date date, result text, clinic text)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query select m.id,m.employee_login,m.kind,m.check_date,m.next_date,m.result,m.clinic from public.app_medical_checks m where adm or m.tenant_id=ten order by m.next_date nulls last;
end $$;

create or replace function public.app_medical_save(p_token uuid, p_id uuid, p_employee text, p_kind text, p_date date, p_next date, p_result text, p_clinic text)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare ten uuid; newid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён',null::uuid; return; end if;
  select u.tenant_id into ten from public.app_session_user(p_token) s join public.app_users u on u.id=s.uid;
  if coalesce(trim(p_employee),'')='' then return query select false,'Укажите сотрудника',null::uuid; return; end if;
  if p_id is null then
    insert into public.app_medical_checks (tenant_id,employee_login,kind,check_date,next_date,result,clinic)
    values (ten,trim(p_employee),coalesce(nullif(trim(p_kind),''),'periodic'),coalesce(p_date,current_date),p_next,coalesce(nullif(trim(p_result),''),'fit'),nullif(trim(p_clinic),''))
    returning id into newid;
    return query select true,'Медосмотр добавлен',newid;
  else
    update public.app_medical_checks m set employee_login=trim(p_employee),kind=coalesce(nullif(trim(p_kind),''),m.kind),check_date=coalesce(p_date,m.check_date),next_date=p_next,result=coalesce(nullif(trim(p_result),''),m.result),clinic=nullif(trim(p_clinic),'')
     where m.id=p_id and (public.app_is_platform_admin(p_token) or m.tenant_id=ten) returning m.id into newid;
    if newid is null then return query select false,'Не найдено',null::uuid; return; end if;
    return query select true,'Медосмотр сохранён',newid;
  end if;
end $$;

-- ---------- Инциденты ----------
create or replace function public.app_incident_list(p_token uuid)
returns table (id uuid, kind text, event_date date, location text, description text, severity text, status text, actions text)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query select i.id,i.kind,i.event_date,i.location,i.description,i.severity,i.status,i.actions from public.app_safety_incidents i where adm or i.tenant_id=ten order by i.event_date desc;
end $$;

create or replace function public.app_incident_save(p_token uuid, p_id uuid, p_kind text, p_date date, p_location text, p_description text, p_severity text, p_actions text)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare ten uuid; uname text; newid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён',null::uuid; return; end if;
  select u.tenant_id,s.ulogin into ten,uname from public.app_session_user(p_token) s join public.app_users u on u.id=s.uid;
  if coalesce(trim(p_description),'')='' then return query select false,'Опишите событие',null::uuid; return; end if;
  if p_id is null then
    insert into public.app_safety_incidents (tenant_id,kind,event_date,location,description,severity,actions,created_login)
    values (ten,coalesce(nullif(trim(p_kind),''),'incident'),coalesce(p_date,current_date),nullif(trim(p_location),''),left(trim(p_description),1000),coalesce(nullif(trim(p_severity),''),'low'),nullif(trim(p_actions),''),uname)
    returning id into newid;
    return query select true,'Инцидент зарегистрирован',newid;
  else
    update public.app_safety_incidents i set kind=coalesce(nullif(trim(p_kind),''),i.kind),event_date=coalesce(p_date,i.event_date),location=nullif(trim(p_location),''),description=left(trim(p_description),1000),severity=coalesce(nullif(trim(p_severity),''),i.severity),actions=nullif(trim(p_actions),'')
     where i.id=p_id and (public.app_is_platform_admin(p_token) or i.tenant_id=ten) returning i.id into newid;
    if newid is null then return query select false,'Не найдено',null::uuid; return; end if;
    return query select true,'Инцидент сохранён',newid;
  end if;
end $$;

create or replace function public.app_incident_set_status(p_token uuid, p_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare ten uuid; st text; n integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten := public.app_my_tenant(p_token);
  st := lower(trim(coalesce(p_status,'')));
  if st not in ('open','investigation','closed') then return query select false,'Недопустимый статус'; return; end if;
  update public.app_safety_incidents i set status=st where i.id=p_id and (public.app_is_platform_admin(p_token) or i.tenant_id=ten);
  get diagnostics n=row_count; if n=0 then return query select false,'Не найдено'; return; end if;
  return query select true,'Статус: '||st;
end $$;

-- ---------- KPI ----------
create or replace function public.app_ehs_kpi(p_token uuid)
returns table (briefings bigint, briefings_overdue bigint, permits_active bigint, ppe_due bigint, medical_due bigint, incidents_open bigint)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query select
    (select count(*) from public.app_safety_briefings b where adm or b.tenant_id=ten),
    (select count(*) from public.app_safety_briefings b where (adm or b.tenant_id=ten) and b.next_date is not null and b.next_date < current_date),
    (select count(*) from public.app_work_permits p where (adm or p.tenant_id=ten) and p.status='active'),
    (select count(*) from public.app_ppe p where (adm or p.tenant_id=ten) and p.due_at is not null and p.due_at < current_date and p.status<>'written_off'),
    (select count(*) from public.app_medical_checks m where (adm or m.tenant_id=ten) and m.next_date is not null and m.next_date < current_date),
    (select count(*) from public.app_safety_incidents i where (adm or i.tenant_id=ten) and i.status<>'closed');
end $$;

-- ---------- Демо ----------
insert into public.app_safety_briefings (tenant_id, employee_login, kind, topic, instructor_login, next_date)
select 'aaaaaaaa-0000-0000-0000-000000000001','master','repeat','Повторный инструктаж по ОТ','chief', current_date + 180
where not exists (select 1 from public.app_safety_briefings where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and topic='Повторный инструктаж по ОТ');

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags, section)
select 'aaaaaaaa-0000-0000-0000-000000000001','Охрана труда','Охрана труда / EHS: инструктажи, допуски, СИЗ, медосмотры, инциденты',
       'W21: журналы инструктажей (app_safety_briefings), наряды-допуски (app_work_permits: вид работ hot/height/electric..., статусы), СИЗ (app_ppe: выдача/срок), медосмотры (app_medical_checks), инциденты/расследования (app_safety_incidents), KPI (app_ehs_kpi: просроченные инструктажи/СИЗ/медосмотры, активные допуски, открытые инциденты). Модуль «Охрана труда» (apps/safety).',
       'охрана труда EHS инструктаж наряд-допуск СИЗ медосмотр инцидент','Охрана труда'
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Охрана труда / EHS: инструктажи, допуски, СИЗ, медосмотры, инциденты');

-- ---------- Права ----------
grant execute on function public.app_briefing_list(uuid) to anon, authenticated;
grant execute on function public.app_briefing_save(uuid,uuid,text,text,text,date,text,date,text) to anon, authenticated;
grant execute on function public.app_briefing_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_permit_list(uuid) to anon, authenticated;
grant execute on function public.app_permit_save(uuid,uuid,text,text,text,text,text,date,date,text) to anon, authenticated;
grant execute on function public.app_permit_set_status(uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_ppe_list(uuid) to anon, authenticated;
grant execute on function public.app_ppe_save(uuid,uuid,text,text,text,date,date,text,text) to anon, authenticated;
grant execute on function public.app_ppe_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_medical_list(uuid) to anon, authenticated;
grant execute on function public.app_medical_save(uuid,uuid,text,text,date,date,text,text) to anon, authenticated;
grant execute on function public.app_incident_list(uuid) to anon, authenticated;
grant execute on function public.app_incident_save(uuid,uuid,text,date,text,text,text,text) to anon, authenticated;
grant execute on function public.app_incident_set_status(uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_ehs_kpi(uuid) to anon, authenticated;
