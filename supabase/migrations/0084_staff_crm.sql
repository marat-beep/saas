-- ============================================================
-- 3DMP Service · 0084_staff_crm.sql  (v62 — Сессия M: B12 «CRM сотрудников»)
-- Кадровый учёт и развитие: карточки сотрудников, статусы, рейтинг, история
-- взаимодействий (1-на-1, аттестация, повышение, замечание). Зависит от 0001..0083.
-- ============================================================

create table if not exists public.app_staff_crm (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid references public.tenants (id),
  name       text not null,
  pos        text,
  department text,
  manager    text,
  status     text not null default 'active', -- active|leave|fired
  hired_at   date,
  rating     numeric default 0,
  note       text,
  created_at timestamptz not null default now()
);
create index if not exists app_staff_crm_idx on public.app_staff_crm (tenant_id, status);
alter table public.app_staff_crm enable row level security;

create table if not exists public.app_staff_events (
  id         uuid primary key default gen_random_uuid(),
  staff_id   uuid references public.app_staff_crm (id) on delete cascade,
  kind       text not null default 'note', -- note|one_on_one|review|promotion|warning
  note       text,
  author     text,
  created_at timestamptz not null default now()
);
create index if not exists app_staff_events_idx on public.app_staff_events (staff_id, created_at desc);
alter table public.app_staff_events enable row level security;

create or replace function public.app_staff_list(p_token uuid, p_q text default null)
returns table (id uuid, name text, pos text, department text, manager text, status text, hired_at date, rating numeric, events bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query
    select s.id, s.name, s.pos, s.department, s.manager, s.status, s.hired_at, s.rating,
      (select count(*) from public.app_staff_events e where e.staff_id=s.id)
    from public.app_staff_crm s
    where (urole='admin' or s.tenant_id=ten)
      and (qq='' or lower(s.name) like '%'||qq||'%' or lower(coalesce(s.pos,'')) like '%'||qq||'%' or lower(coalesce(s.department,'')) like '%'||qq||'%')
    order by (s.status='fired'), s.name;
end $$;

create or replace function public.app_staff_save(p_token uuid, p_id uuid, p_name text, p_position text, p_department text,
  p_manager text, p_status text, p_hired_at date, p_rating numeric, p_note text)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; sid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director','chief') then raise exception 'Недостаточно прав'; return; end if;
  if coalesce(trim(p_name),'')='' then raise exception 'Укажите ФИО'; return; end if;
  if coalesce(p_status,'active') not in ('active','leave','fired') then raise exception 'Неверный статус'; return; end if;
  if p_id is null then
    insert into public.app_staff_crm (tenant_id, name, pos, department, manager, status, hired_at, rating, note)
    values (ten, trim(p_name), nullif(trim(p_position),''), nullif(trim(p_department),''), nullif(trim(p_manager),''),
            coalesce(nullif(trim(p_status),''),'active'), p_hired_at, coalesce(p_rating,0), nullif(trim(p_note),''))
    returning id into sid;
    return query select sid, 'Сотрудник добавлен';
  else
    update public.app_staff_crm set name=trim(p_name), pos=nullif(trim(p_position),''), department=nullif(trim(p_department),''),
      manager=nullif(trim(p_manager),''), status=coalesce(nullif(trim(p_status),''),status), hired_at=p_hired_at,
      rating=coalesce(p_rating,rating), note=nullif(trim(p_note),'')
     where id=p_id and (urole='admin' or tenant_id=ten) returning id into sid;
    return query select sid, 'Данные обновлены';
  end if;
end $$;

create or replace function public.app_staff_event_add(p_token uuid, p_staff_id uuid, p_kind text, p_note text)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; ulogin text; eid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if not exists (select 1 from public.app_staff_crm s where s.id=p_staff_id and (urole='admin' or s.tenant_id=ten)) then raise exception 'Сотрудник не найден'; return; end if;
  insert into public.app_staff_events (staff_id, kind, note, author)
  values (p_staff_id, coalesce(nullif(trim(p_kind),''),'note'), nullif(trim(p_note),''), ulogin)
  returning id into eid;
  return query select eid, 'Запись добавлена';
end $$;

create or replace function public.app_staff_events_list(p_token uuid, p_staff_id uuid)
returns table (id uuid, kind text, note text, author text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if not exists (select 1 from public.app_staff_crm s where s.id=p_staff_id and (urole='admin' or s.tenant_id=ten)) then raise exception 'Сотрудник не найден'; end if;
  return query select e.id, e.kind, e.note, e.author, e.created_at
    from public.app_staff_events e where e.staff_id=p_staff_id order by e.created_at desc;
end $$;

create or replace function public.app_staff_kpi(p_token uuid)
returns table (total bigint, active bigint, on_leave bigint, fired bigint, avg_rating numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select count(*), count(*) filter (where status='active'), count(*) filter (where status='leave'),
    count(*) filter (where status='fired'), round(coalesce(avg(rating) filter (where rating>0),0),1)
    from public.app_staff_crm where (urole='admin' or tenant_id=ten);
end $$;

grant execute on function public.app_staff_list(uuid,text) to anon, authenticated;
grant execute on function public.app_staff_save(uuid,uuid,text,text,text,text,text,date,numeric,text) to anon, authenticated;
grant execute on function public.app_staff_event_add(uuid,uuid,text,text) to anon, authenticated;
grant execute on function public.app_staff_events_list(uuid,uuid) to anon, authenticated;
grant execute on function public.app_staff_kpi(uuid) to anon, authenticated;

-- ---------- Демо (тенант A) ----------
do $$
declare A constant uuid := 'aaaaaaaa-0000-0000-0000-000000000001'; sid uuid;
begin
  if not exists (select 1 from public.app_staff_crm where tenant_id=A) then
    insert into public.app_staff_crm (tenant_id, name, pos, department, manager, status, hired_at, rating, note)
    values (A, 'Сидоров А.А.', 'Мастер участка', 'Механообработка', 'Начальник цеха', 'active', current_date - 900, 4.6, 'Ключевой сотрудник')
    returning id into sid;
    insert into public.app_staff_events (staff_id, kind, note, author) values
      (sid,'one_on_one','Обсуждены цели на квартал','Директор'),
      (sid,'review','Аттестация: соответствует, премия 10%','Директор');
    insert into public.app_staff_crm (tenant_id, name, pos, department, manager, status, hired_at, rating)
    values (A, 'Петров П.П.', 'Оператор ЧПУ', 'Механообработка', 'Сидоров А.А.', 'active', current_date - 300, 4.1),
           (A, 'Иванов И.И.', 'Технолог', 'Технологический отдел', 'Главный технолог', 'leave', current_date - 600, 4.8);
  end if;
end $$;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Персонал','CRM сотрудников (B12)',
   'Модуль «CRM сотрудников»: кадровые карточки (ФИО, должность, подразделение, руководитель, статус: работает/отпуск/уволен, дата приёма, рейтинг) и история взаимодействий (заметка, 1-на-1, аттестация, повышение, замечание). KPI: всего, работают, в отпуске, уволены, средний рейтинг. Дополняет HR и оргструктуру.',
   'CRM сотрудников кадры развитие аттестация рейтинг B12')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='CRM сотрудников (B12)');
