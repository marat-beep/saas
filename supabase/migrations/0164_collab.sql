-- ============================================================
-- 3DMP Service · 0164_collab.sql  (W16 — Совместная работа)
-- Проекты и задачи (канбан), учёт времени, обсуждения объектов, контакт-центр (inbox),
-- база знаний 2.0 (разделы). Идемпотентно. Зависит от 0001..0163.
-- ============================================================

-- ---------- Проекты ----------
create table if not exists public.app_projects (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  name          text not null,
  code          text,
  status        text not null default 'active',   -- active|done|archived
  owner_login   text,
  start_date    date,
  due_date      date,
  note          text,
  created_login text,
  created_at    timestamptz not null default now()
);
alter table public.app_projects enable row level security;

-- ---------- Задачи ----------
create table if not exists public.app_tasks (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  project_id    uuid references public.app_projects (id) on delete set null,
  title         text not null,
  description   text,
  status        text not null default 'todo',      -- todo|in_progress|done|cancelled
  priority      text not null default 'normal',    -- low|normal|high
  assignee_login text,
  due_date      date,
  est_hours     numeric,
  fact_hours    numeric not null default 0,
  pos           integer not null default 0,
  entity_type   text,
  entity_id     uuid,
  created_login text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  done_at       timestamptz
);
create index if not exists app_tasks_idx on public.app_tasks (tenant_id, project_id, status);
create index if not exists app_tasks_assignee_idx on public.app_tasks (tenant_id, assignee_login, status);
alter table public.app_tasks enable row level security;

create table if not exists public.app_task_time (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid references public.tenants (id),
  task_id      uuid not null references public.app_tasks (id) on delete cascade,
  user_login   text,
  hours        numeric not null default 0,
  work_date    date not null default current_date,
  note         text,
  created_at   timestamptz not null default now()
);
create index if not exists app_task_time_idx on public.app_task_time (task_id);
alter table public.app_task_time enable row level security;

-- ---------- Обсуждения объектов ----------
create table if not exists public.app_messages (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  entity_type   text not null,     -- task|order|deal|doc_flow|...
  entity_id     uuid,
  author_login  text,
  body          text not null,
  created_at    timestamptz not null default now()
);
create index if not exists app_messages_idx on public.app_messages (tenant_id, entity_type, entity_id, created_at);
alter table public.app_messages enable row level security;

-- ---------- Контакт-центр (единый inbox) ----------
create table if not exists public.app_inbox (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  channel       text not null default 'email',   -- email|chat|sms|call|other
  direction     text not null default 'in',      -- in|out
  counterparty  text,
  subject       text,
  body          text,
  status        text not null default 'new',      -- new|assigned|closed
  assignee_login text,
  entity_type   text,
  entity_id     uuid,
  created_login text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists app_inbox_idx on public.app_inbox (tenant_id, status);
alter table public.app_inbox enable row level security;

-- ---------- БЗ 2.0: разделы ----------
alter table public.app_knowledge add column if not exists section text;

-- ================= RPC: проекты =================
create or replace function public.app_projects_list(p_token uuid, p_q text default null)
returns table (id uuid, name text, code text, status text, owner_login text, due_date date, tasks bigint, done bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query
    select p.id, p.name, p.code, p.status, p.owner_login, p.due_date,
           (select count(*) from public.app_tasks t where t.project_id = p.id),
           (select count(*) from public.app_tasks t where t.project_id = p.id and t.status='done')
      from public.app_projects p
     where (adm or p.tenant_id = ten) and (p_q is null or p_q = '' or p.name ilike '%'||p_q||'%' or coalesce(p.code,'') ilike '%'||p_q||'%')
     order by p.created_at desc;
end $$;

create or replace function public.app_project_save(p_token uuid, p_id uuid, p_name text, p_code text, p_status text, p_owner text, p_start date, p_due date, p_note text)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; uname text; newid uuid; st text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid; return; end if;
  select u.tenant_id, s.ulogin into ten, uname from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  if coalesce(trim(p_name),'') = '' then return query select false,'Укажите название проекта', null::uuid; return; end if;
  st := coalesce(nullif(trim(p_status),''),'active');
  if st not in ('active','done','archived') then return query select false,'Недопустимый статус', null::uuid; return; end if;
  if p_id is null then
    insert into public.app_projects (tenant_id, name, code, status, owner_login, start_date, due_date, note, created_login)
    values (ten, left(trim(p_name),160), nullif(trim(p_code),''), st, coalesce(nullif(trim(p_owner),''),uname), p_start, p_due, nullif(trim(p_note),''), uname)
    returning app_projects.id into newid;
    return query select true,'Проект создан', newid;
  else
    update public.app_projects p set name = left(trim(p_name),160), code = nullif(trim(p_code),''), status = st, owner_login = coalesce(nullif(trim(p_owner),''), p.owner_login),
           start_date = p_start, due_date = p_due, note = nullif(trim(p_note),'')
     where p.id = p_id and (public.app_is_platform_admin(p_token) or p.tenant_id = ten)
     returning p.id into newid;
    if newid is null then return query select false,'Проект не найден', null::uuid; return; end if;
    return query select true,'Проект сохранён', newid;
  end if;
end $$;

create or replace function public.app_project_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; n integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten := public.app_my_tenant(p_token);
  delete from public.app_projects p where p.id = p_id and (public.app_is_platform_admin(p_token) or p.tenant_id = ten);
  get diagnostics n = row_count;
  if n = 0 then return query select false,'Проект не найден'; return; end if;
  return query select true,'Проект удалён';
end $$;

-- ================= RPC: задачи =================
create or replace function public.app_tasks_list(p_token uuid, p_project_id uuid default null, p_status text default null, p_assignee text default null)
returns table (id uuid, project_id uuid, project text, title text, status text, priority text, assignee_login text, due_date date, est_hours numeric, fact_hours numeric, pos integer, entity_type text, entity_id uuid, comments bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean; st text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  st := nullif(trim(coalesce(p_status,'')),'');
  return query
    select t.id, t.project_id, p.name, t.title, t.status, t.priority, t.assignee_login, t.due_date, t.est_hours, t.fact_hours, t.pos, t.entity_type, t.entity_id,
           (select count(*) from public.app_messages m where m.entity_type='task' and m.entity_id = t.id)
      from public.app_tasks t left join public.app_projects p on p.id = t.project_id
     where (adm or t.tenant_id = ten)
       and (p_project_id is null or t.project_id = p_project_id)
       and (st is null or t.status = st)
       and (p_assignee is null or p_assignee = '' or t.assignee_login = p_assignee)
     order by t.pos, t.created_at;
end $$;

create or replace function public.app_task_save(p_token uuid, p_id uuid, p_project_id uuid, p_title text, p_description text, p_status text, p_priority text, p_assignee text, p_due date, p_est numeric, p_pos integer, p_entity_type text, p_entity_id uuid)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; uname text; newid uuid; st text; pr text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid; return; end if;
  select u.tenant_id, s.ulogin into ten, uname from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  if coalesce(trim(p_title),'') = '' then return query select false,'Укажите задачу', null::uuid; return; end if;
  st := coalesce(nullif(trim(p_status),''),'todo');
  if st not in ('todo','in_progress','done','cancelled') then return query select false,'Недопустимый статус', null::uuid; return; end if;
  pr := coalesce(nullif(trim(p_priority),''),'normal');
  if p_id is null then
    insert into public.app_tasks (tenant_id, project_id, title, description, status, priority, assignee_login, due_date, est_hours, pos, entity_type, entity_id, created_login, done_at)
    values (ten, p_project_id, left(trim(p_title),200), nullif(trim(p_description),''), st, pr, nullif(trim(p_assignee),''), p_due, p_est, coalesce(p_pos,0), nullif(trim(p_entity_type),''), p_entity_id, uname,
            case when st='done' then now() else null end)
    returning app_tasks.id into newid;
    return query select true,'Задача создана', newid;
  else
    update public.app_tasks t set project_id = p_project_id, title = left(trim(p_title),200), description = nullif(trim(p_description),''),
           status = st, priority = pr, assignee_login = nullif(trim(p_assignee),''), due_date = p_due, est_hours = p_est, pos = coalesce(p_pos, t.pos),
           entity_type = nullif(trim(p_entity_type),''), entity_id = p_entity_id,
           done_at = case when st='done' then coalesce(t.done_at, now()) else null end, updated_at = now()
     where t.id = p_id and (public.app_is_platform_admin(p_token) or t.tenant_id = ten)
     returning t.id into newid;
    if newid is null then return query select false,'Задача не найдена', null::uuid; return; end if;
    return query select true,'Задача сохранена', newid;
  end if;
end $$;

create or replace function public.app_task_set_status(p_token uuid, p_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; st text; n integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten := public.app_my_tenant(p_token);
  st := lower(trim(coalesce(p_status,'')));
  if st not in ('todo','in_progress','done','cancelled') then return query select false,'Недопустимый статус'; return; end if;
  update public.app_tasks t set status = st, done_at = case when st='done' then now() else null end, updated_at = now()
   where t.id = p_id and (public.app_is_platform_admin(p_token) or t.tenant_id = ten);
  get diagnostics n = row_count;
  if n = 0 then return query select false,'Задача не найдена'; return; end if;
  return query select true,'Статус задачи: ' || st;
end $$;

create or replace function public.app_task_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; n integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten := public.app_my_tenant(p_token);
  delete from public.app_tasks t where t.id = p_id and (public.app_is_platform_admin(p_token) or t.tenant_id = ten);
  get diagnostics n = row_count;
  if n = 0 then return query select false,'Задача не найдена'; return; end if;
  return query select true,'Задача удалена';
end $$;

create or replace function public.app_task_board(p_token uuid, p_project_id uuid)
returns table (status text, cnt bigint, hours numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query
    select t.status, count(*), coalesce(sum(t.fact_hours),0)
      from public.app_tasks t
     where (adm or t.tenant_id = ten) and t.project_id = p_project_id
     group by t.status;
end $$;

create or replace function public.app_my_tasks(p_token uuid)
returns table (id uuid, project text, title text, status text, priority text, due_date date, fact_hours numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; ulogin text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.ulogin into ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select t.id, p.name, t.title, t.status, t.priority, t.due_date, t.fact_hours
      from public.app_tasks t left join public.app_projects p on p.id = t.project_id
     where t.tenant_id = ten and t.assignee_login = ulogin and t.status in ('todo','in_progress')
     order by t.due_date nulls last, t.priority;
end $$;

create or replace function public.app_task_time_add(p_token uuid, p_task_id uuid, p_hours numeric, p_work_date date, p_note text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; ulogin text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.ulogin into ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if not exists (select 1 from public.app_tasks t where t.id = p_task_id and (public.app_is_platform_admin(p_token) or t.tenant_id = ten)) then
    return query select false,'Задача не найдена'; return;
  end if;
  insert into public.app_task_time (tenant_id, task_id, user_login, hours, work_date, note)
  values (ten, p_task_id, ulogin, coalesce(p_hours,0), coalesce(p_work_date, current_date), nullif(trim(p_note),''));
  update public.app_tasks set fact_hours = coalesce(fact_hours,0) + coalesce(p_hours,0), updated_at = now() where id = p_task_id;
  return query select true,'Время учтено';
end $$;

create or replace function public.app_task_time_list(p_token uuid, p_task_id uuid)
returns table (id uuid, user_login text, hours numeric, work_date date, note text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query select tt.id, tt.user_login, tt.hours, tt.work_date, tt.note, tt.created_at
    from public.app_task_time tt where tt.task_id = p_task_id and (adm or tt.tenant_id = ten) order by tt.work_date desc;
end $$;

-- ================= RPC: обсуждения =================
create or replace function public.app_messages_list(p_token uuid, p_entity_type text, p_entity_id uuid)
returns table (id uuid, author_login text, body text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query select m.id, m.author_login, m.body, m.created_at from public.app_messages m
    where m.entity_type = p_entity_type and m.entity_id = p_entity_id and (adm or m.tenant_id = ten)
    order by m.created_at;
end $$;

create or replace function public.app_message_add(p_token uuid, p_entity_type text, p_entity_id uuid, p_body text)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; ulogin text; newid uuid; au uuid; m text; body text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid; return; end if;
  select u.tenant_id, s.ulogin into ten, ulogin from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  if coalesce(trim(p_body),'') = '' then return query select false,'Пустое сообщение', null::uuid; return; end if;
  body := left(trim(p_body), 4000);
  insert into public.app_messages (tenant_id, entity_type, entity_id, author_login, body)
  values (ten, lower(trim(p_entity_type)), p_entity_id, ulogin, body) returning app_messages.id into newid;
  -- упоминания @login → уведомление
  for m in select (rm)[1] from regexp_matches(body, '@([a-zA-Z0-9_.-]+)', 'g') as rm loop
    select u.id into au from public.app_users u where u.login = m and u.tenant_id = ten limit 1;
    if au is not null then perform public.app_notif_send(au, 'Упоминание', ulogin || ': ' || left(body,160), 'index.html'); end if;
  end loop;
  return query select true,'Сообщение добавлено', newid;
end $$;

-- ================= RPC: контакт-центр =================
create or replace function public.app_inbox_list(p_token uuid, p_status text default null)
returns table (id uuid, channel text, direction text, counterparty text, subject text, status text, assignee_login text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean; st text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  st := nullif(trim(coalesce(p_status,'')),'');
  return query select i.id, i.channel, i.direction, i.counterparty, i.subject, i.status, i.assignee_login, i.created_at
    from public.app_inbox i where (adm or i.tenant_id = ten) and (st is null or i.status = st) order by i.created_at desc;
end $$;

create or replace function public.app_inbox_save(p_token uuid, p_id uuid, p_channel text, p_counterparty text, p_subject text, p_body text, p_assignee text)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; ulogin text; newid uuid; ch text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid; return; end if;
  select u.tenant_id, s.ulogin into ten, ulogin from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  ch := coalesce(nullif(trim(p_channel),''),'email');
  if coalesce(trim(p_subject),'') = '' then return query select false,'Укажите тему обращения', null::uuid; return; end if;
  if p_id is null then
    insert into public.app_inbox (tenant_id, channel, direction, counterparty, subject, body, status, assignee_login, created_login)
    values (ten, ch, 'in', nullif(trim(p_counterparty),''), left(trim(p_subject),200), nullif(trim(p_body),''),
            case when coalesce(trim(p_assignee),'') <> '' then 'assigned' else 'new' end, nullif(trim(p_assignee),''), ulogin)
    returning app_inbox.id into newid;
    return query select true,'Обращение создано', newid;
  else
    update public.app_inbox i set channel = ch, counterparty = nullif(trim(p_counterparty),''), subject = left(trim(p_subject),200), body = nullif(trim(p_body),''),
           assignee_login = nullif(trim(p_assignee),''), status = case when coalesce(trim(p_assignee),'')<>'' and i.status='new' then 'assigned' else i.status end, updated_at = now()
     where i.id = p_id and (public.app_is_platform_admin(p_token) or i.tenant_id = ten)
     returning i.id into newid;
    if newid is null then return query select false,'Обращение не найдено', null::uuid; return; end if;
    return query select true,'Обращение сохранено', newid;
  end if;
end $$;

create or replace function public.app_inbox_set_status(p_token uuid, p_id uuid, p_status text, p_assignee text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; ulogin text; st text; n integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.ulogin into ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  st := lower(trim(coalesce(p_status,'')));
  if st not in ('new','assigned','closed') then return query select false,'Недопустимый статус'; return; end if;
  update public.app_inbox i set status = st,
         assignee_login = coalesce(nullif(trim(p_assignee),''), case when st='assigned' then coalesce(i.assignee_login, ulogin) else i.assignee_login end),
         updated_at = now()
   where i.id = p_id and (public.app_is_platform_admin(p_token) or i.tenant_id = ten);
  get diagnostics n = row_count;
  if n = 0 then return query select false,'Обращение не найдено'; return; end if;
  return query select true,'Статус: ' || st;
end $$;

-- ================= RPC: БЗ 2.0 =================
create or replace function public.app_kb_sections(p_token uuid)
returns table (section text, cnt bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query select coalesce(k.section,'Без раздела'), count(*)
    from public.app_knowledge k where (adm or k.tenant_id = ten) group by coalesce(k.section,'Без раздела') order by 1;
end $$;

create or replace function public.app_kb_list(p_token uuid, p_section text default null, p_q text default null)
returns table (id uuid, section text, category text, question text, answer text, tags text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean; sec text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  sec := nullif(trim(coalesce(p_section,'')),'');
  return query select k.id, k.section, k.category, k.question, k.answer, k.tags
    from public.app_knowledge k
   where (adm or k.tenant_id = ten)
     and (sec is null or coalesce(k.section,'Без раздела') = sec)
     and (p_q is null or p_q = '' or k.question ilike '%'||p_q||'%' or k.answer ilike '%'||p_q||'%' or coalesce(k.tags,'') ilike '%'||p_q||'%')
   order by k.section nulls last, k.category, k.question;
end $$;

create or replace function public.app_collab_kpi(p_token uuid)
returns table (projects bigint, tasks_open bigint, tasks_done bigint, overdue bigint, logged_hours numeric, inbox_open bigint, messages bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query select
    (select count(*) from public.app_projects p where adm or p.tenant_id=ten),
    (select count(*) from public.app_tasks t where (adm or t.tenant_id=ten) and t.status in ('todo','in_progress')),
    (select count(*) from public.app_tasks t where (adm or t.tenant_id=ten) and t.status='done'),
    (select count(*) from public.app_tasks t where (adm or t.tenant_id=ten) and t.due_date < current_date and t.status in ('todo','in_progress')),
    (select coalesce(sum(tt.hours),0) from public.app_task_time tt where adm or tt.tenant_id=ten),
    (select count(*) from public.app_inbox i where (adm or i.tenant_id=ten) and i.status<>'closed'),
    (select count(*) from public.app_messages m where adm or m.tenant_id=ten);
end $$;

-- ================= Демо =================
insert into public.app_projects (tenant_id, name, code, status, owner_login, due_date, created_login)
select 'aaaaaaaa-0000-0000-0000-000000000001', 'Освоение нового изделия (демо)', 'PRJ-001', 'active', 'manager', current_date + 30, 'owner'
where not exists (select 1 from public.app_projects where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and code='PRJ-001');

insert into public.app_tasks (tenant_id, project_id, title, status, priority, assignee_login, due_date, est_hours, created_login)
select 'aaaaaaaa-0000-0000-0000-000000000001', p.id, 'Подготовить техпроцесс', 'in_progress', 'high', 'technologist', current_date + 5, 8, 'owner'
from public.app_projects p
where p.tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and p.code='PRJ-001'
  and not exists (select 1 from public.app_tasks where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and title='Подготовить техпроцесс');

insert into public.app_inbox (tenant_id, channel, direction, counterparty, subject, status, created_login)
select 'aaaaaaaa-0000-0000-0000-000000000001', 'email', 'in', 'ООО «Привод»', 'Вопрос по срокам поставки', 'new', 'owner'
where not exists (select 1 from public.app_inbox where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and subject='Вопрос по срокам поставки');

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags, section)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags, v.section
from (values
  ('Платформа','Совместная работа: задачи, проекты, обсуждения, контакт-центр',
   'W16: проекты (app_projects) и задачи (app_tasks: канбан todo/in_progress/done, приоритет, исполнитель, срок, оценка/факт часов, связь с объектом) с доской app_task_board и «моими задачами» app_my_tasks; учёт времени app_task_time; обсуждения объектов (app_messages с упоминаниями @login → уведомления); контакт-центр (app_inbox: каналы email/chat/sms/call, статусы new/assigned/closed); БЗ 2.0 — разделы (app_kb_sections/app_kb_list, поле section у app_knowledge). Модуль «Задачи и проекты» (apps/tasks).',
   'совместная работа задачи проекты канбан обсуждения упоминания контакт-центр inbox база знаний разделы', 'Совместная работа'),
  ('Платформа','Задачи и проекты: как работать',
   'Раздел «Задачи и проекты»: создайте проект, добавьте задачи и перетаскивайте их по статусам (todo→in_progress→done), отмечайте время, обсуждайте в карточке (упоминания @логин дают уведомление). Обращения из контакт-центра (inbox) распределяются на исполнителей. Поиск по базе знаний — по разделам и ключевым словам.',
   'задачи проекты канбан время обсуждения inbox база знаний', 'Совместная работа')
) as v(category,question,answer,tags,section)
where not exists (
  select 1 from public.app_knowledge
   where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001' and question = v.question
);

-- ---------- Права ----------
grant execute on function public.app_projects_list(uuid,text) to anon, authenticated;
grant execute on function public.app_project_save(uuid,uuid,text,text,text,text,date,date,text) to anon, authenticated;
grant execute on function public.app_project_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_tasks_list(uuid,uuid,text,text) to anon, authenticated;
grant execute on function public.app_task_save(uuid,uuid,uuid,text,text,text,text,text,date,numeric,integer,text,uuid) to anon, authenticated;
grant execute on function public.app_task_set_status(uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_task_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_task_board(uuid,uuid) to anon, authenticated;
grant execute on function public.app_my_tasks(uuid) to anon, authenticated;
grant execute on function public.app_task_time_add(uuid,uuid,numeric,date,text) to anon, authenticated;
grant execute on function public.app_task_time_list(uuid,uuid) to anon, authenticated;
grant execute on function public.app_messages_list(uuid,text,uuid) to anon, authenticated;
grant execute on function public.app_message_add(uuid,text,uuid,text) to anon, authenticated;
grant execute on function public.app_inbox_list(uuid,text) to anon, authenticated;
grant execute on function public.app_inbox_save(uuid,uuid,text,text,text,text,text) to anon, authenticated;
grant execute on function public.app_inbox_set_status(uuid,uuid,text,text) to anon, authenticated;
grant execute on function public.app_kb_sections(uuid) to anon, authenticated;
grant execute on function public.app_kb_list(uuid,text,text) to anon, authenticated;
grant execute on function public.app_collab_kpi(uuid) to anon, authenticated;
