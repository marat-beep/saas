-- ============================================================
-- 3DMP Service · 0159_workflow.sql  (W15 — Low-code workflow)
-- L1 процессы (defs/instances/tasks/actions), L2 правила (rules/triggers),
-- L3 конструктор форм (form_defs). Согласования W10 — частный случай.
-- Идемпотентно. Зависит от 0001..0158.
-- ============================================================

-- ---------- L3: конструктор форм ----------
create table if not exists public.app_form_defs (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid references public.tenants (id),
  code        text,
  name        text not null,
  module      text,
  fields      jsonb not null default '[]'::jsonb,  -- [{key,label,type,required,options}]
  created_login text,
  created_at  timestamptz not null default now()
);
alter table public.app_form_defs enable row level security;

-- ---------- L1: процессы ----------
create table if not exists public.app_process_defs (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  name          text not null,
  code          text,
  doc_type      text,
  entity_type   text,
  steps         jsonb not null default '[]'::jsonb,  -- [{ord,name,role,user_id,form_code,sla_hours}]
  active        boolean not null default true,
  created_by    uuid references public.app_users (id) on delete set null,
  created_login text,
  created_at    timestamptz not null default now()
);
alter table public.app_process_defs enable row level security;

create table if not exists public.app_process_instances (
  id              uuid primary key default gen_random_uuid(),
  tenant_id       uuid references public.tenants (id),
  def_id          uuid references public.app_process_defs (id) on delete set null,
  def_name        text,
  entity_type     text,
  entity_id       uuid,
  entity_title    text,
  status          text not null default 'running',  -- running|done|rejected|cancelled
  current_step    integer not null default 1,
  total_steps     integer not null default 1,
  data            jsonb not null default '{}'::jsonb,
  requested_by    uuid references public.app_users (id) on delete set null,
  requested_login text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index if not exists app_process_inst_idx on public.app_process_instances (tenant_id, status);
alter table public.app_process_instances enable row level security;

create table if not exists public.app_process_tasks (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid references public.tenants (id),
  instance_id    uuid not null references public.app_process_instances (id) on delete cascade,
  step_ord       integer not null,
  name           text,
  role           text,
  user_id        uuid references public.app_users (id) on delete set null,
  assignee_login text,
  status         text not null default 'open',   -- open|done|skipped
  data           jsonb not null default '{}'::jsonb,
  comment        text,
  due_at         timestamptz,
  acted_at       timestamptz,
  created_at     timestamptz not null default now()
);
create index if not exists app_process_tasks_idx on public.app_process_tasks (instance_id, status);
alter table public.app_process_tasks enable row level security;

create table if not exists public.app_process_actions (
  id          uuid primary key default gen_random_uuid(),
  instance_id uuid not null references public.app_process_instances (id) on delete cascade,
  step_ord    integer,
  actor       uuid references public.app_users (id) on delete set null,
  actor_login text,
  action      text not null,   -- start|approve|reject|complete|cancel
  comment     text,
  created_at  timestamptz not null default now()
);
create index if not exists app_process_actions_idx on public.app_process_actions (instance_id, created_at);
alter table public.app_process_actions enable row level security;

-- ---------- L2: правила/триггеры ----------
create table if not exists public.app_rules (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  name          text not null,
  event         text not null,       -- order_created|status_changed|process_started|invoice_overdue|custom
  condition     jsonb not null default '{}'::jsonb,  -- {field,op,value}
  actions       jsonb not null default '[]'::jsonb,  -- [{type,params}]
  active        boolean not null default true,
  run_count     integer not null default 0,
  last_run      timestamptz,
  created_login text,
  created_at    timestamptz not null default now()
);
alter table public.app_rules enable row level security;

-- ================= RPC: формы (L3) =================
create or replace function public.app_form_defs_list(p_token uuid)
returns table (id uuid, code text, name text, module text, fields jsonb)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query select f.id, f.code, f.name, f.module, f.fields from public.app_form_defs f
    where adm or f.tenant_id = ten order by f.name;
end $$;

create or replace function public.app_form_def_save(p_token uuid, p_id uuid, p_code text, p_name text, p_module text, p_fields jsonb)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; uname text; newid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid; return; end if;
  select u.tenant_id, s.ulogin into ten, uname from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  if coalesce(trim(p_name),'') = '' then return query select false,'Укажите название формы', null::uuid; return; end if;
  if p_fields is not null and jsonb_typeof(p_fields) <> 'array' then return query select false,'Поля должны быть массивом', null::uuid; return; end if;
  if p_id is null then
    insert into public.app_form_defs (tenant_id, code, name, module, fields, created_login)
    values (ten, nullif(trim(p_code),''), left(trim(p_name),120), nullif(trim(p_module),''), coalesce(p_fields,'[]'::jsonb), uname)
    returning app_form_defs.id into newid;
    return query select true,'Форма создана', newid;
  else
    update public.app_form_defs f set code = nullif(trim(p_code),''), name = left(trim(p_name),120), module = nullif(trim(p_module),''),
           fields = coalesce(p_fields, f.fields)
     where f.id = p_id and (public.app_is_platform_admin(p_token) or f.tenant_id = ten)
     returning f.id into newid;
    if newid is null then return query select false,'Форма не найдена', null::uuid; return; end if;
    return query select true,'Форма сохранена', newid;
  end if;
end $$;

create or replace function public.app_form_def_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; n integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten := public.app_my_tenant(p_token);
  delete from public.app_form_defs f where f.id = p_id and (public.app_is_platform_admin(p_token) or f.tenant_id = ten);
  get diagnostics n = row_count;
  if n = 0 then return query select false,'Форма не найдена'; return; end if;
  return query select true,'Форма удалена';
end $$;

-- ================= RPC: процессы (L1) =================
create or replace function public.app_process_defs_list(p_token uuid)
returns table (id uuid, name text, code text, doc_type text, entity_type text, steps jsonb, active boolean)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query select d.id, d.name, d.code, d.doc_type, d.entity_type, d.steps, d.active
    from public.app_process_defs d where adm or d.tenant_id = ten order by d.name;
end $$;

create or replace function public.app_process_def_save(p_token uuid, p_id uuid, p_name text, p_code text, p_doc_type text, p_entity_type text, p_steps jsonb, p_active boolean)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; me uuid; uname text; newid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid; return; end if;
  select u.tenant_id, s.uid, s.ulogin into ten, me, uname from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  if coalesce(trim(p_name),'') = '' then return query select false,'Укажите название процесса', null::uuid; return; end if;
  if p_steps is not null and (jsonb_typeof(p_steps) <> 'array' or jsonb_array_length(p_steps) = 0) then return query select false,'Нужен хотя бы один этап', null::uuid; return; end if;
  if p_id is null then
    insert into public.app_process_defs (tenant_id, name, code, doc_type, entity_type, steps, active, created_by, created_login)
    values (ten, left(trim(p_name),140), nullif(trim(p_code),''), nullif(trim(p_doc_type),''), nullif(trim(p_entity_type),''),
            coalesce(p_steps,'[]'::jsonb), coalesce(p_active,true), me, uname)
    returning app_process_defs.id into newid;
    return query select true,'Процесс создан', newid;
  else
    update public.app_process_defs d set name = left(trim(p_name),140), code = nullif(trim(p_code),''), doc_type = nullif(trim(p_doc_type),''),
           entity_type = nullif(trim(p_entity_type),''), steps = coalesce(p_steps, d.steps), active = coalesce(p_active, d.active)
     where d.id = p_id and (public.app_is_platform_admin(p_token) or d.tenant_id = ten)
     returning d.id into newid;
    if newid is null then return query select false,'Процесс не найден', null::uuid; return; end if;
    return query select true,'Процесс сохранён', newid;
  end if;
end $$;

create or replace function public.app_process_def_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; n integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten := public.app_my_tenant(p_token);
  delete from public.app_process_defs d where d.id = p_id and (public.app_is_platform_admin(p_token) or d.tenant_id = ten);
  get diagnostics n = row_count;
  if n = 0 then return query select false,'Процесс не найден'; return; end if;
  return query select true,'Процесс удалён';
end $$;

create or replace function public.app_process_start(p_token uuid, p_def_id uuid, p_entity_type text, p_entity_id uuid, p_entity_title text, p_data jsonb)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; me uuid; uname text; steps jsonb; total int; newid uuid; step jsonb; role text; uid uuid; due timestamptz; dh numeric;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid; return; end if;
  select u.tenant_id, s.uid, s.ulogin into ten, me, uname from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  select d.steps into steps from public.app_process_defs d where d.id = p_def_id and (public.app_is_platform_admin(p_token) or d.tenant_id = ten) and d.active;
  if steps is null then return query select false,'Процесс не найден или неактивен', null::uuid; return; end if;
  total := jsonb_array_length(steps);
  if total = 0 then return query select false,'Нет этапов', null::uuid; return; end if;
  insert into public.app_process_instances (tenant_id, def_id, def_name, entity_type, entity_id, entity_title, status, current_step, total_steps, data, requested_by, requested_login)
  select ten, d.id, d.name, nullif(trim(p_entity_type),''), p_entity_id, left(coalesce(p_entity_title,''),200), 'running', 1, total, coalesce(p_data,'{}'::jsonb), me, uname
    from public.app_process_defs d where d.id = p_def_id
  returning app_process_instances.id into newid;

  step := steps -> 0; role := nullif(step->>'role',''); uid := null;
  begin uid := (step->>'user_id')::uuid; exception when others then uid := null; end;
  dh := nullif(step->>'sla_hours','')::numeric;
  due := case when dh is not null then now() + (dh || ' hours')::interval else null end;
  insert into public.app_process_tasks (tenant_id, instance_id, step_ord, name, role, user_id, status, due_at)
  values (ten, newid, 1, coalesce(step->>'name', role), role, uid, 'open', due);
  insert into public.app_process_actions (instance_id, step_ord, actor, actor_login, action, comment)
  values (newid, 1, me, uname, 'start', 'Запущен процесс');

  if uid is not null then perform public.app_notif_send(uid, 'Новая задача процесса', coalesce(p_entity_title,''), 'apps/workflow/index.html');
  elsif role is not null then perform public.app_notif_roles_t(ten, array[role], 'Новая задача процесса', coalesce(p_entity_title,''), 'apps/workflow/index.html'); end if;

  return query select true,'Процесс запущен', newid;
end $$;

create or replace function public.app_process_my(p_token uuid)
returns table (task_id uuid, instance_id uuid, def_name text, entity_title text, step_ord integer, total_steps integer, name text, role text, due_at timestamptz, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; urole text; ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  adm := public.app_is_platform_admin(p_token);
  return query
    select t.id, i.id, i.def_name, i.entity_title, i.current_step, i.total_steps, t.name, t.role, t.due_at, t.created_at
      from public.app_process_tasks t join public.app_process_instances i on i.id = t.instance_id
     where t.status = 'open' and i.status = 'running'
       and (adm or public.app_is_owner(p_token) or t.user_id = uid or t.role = urole)
     order by t.due_at nulls last, t.created_at;
end $$;

create or replace function public.app_process_instances_list(p_token uuid, p_status text default null)
returns table (id uuid, def_name text, entity_type text, entity_title text, status text, current_step integer, total_steps integer, requested_login text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean; st text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  st := nullif(trim(coalesce(p_status,'')),'');
  return query select i.id, i.def_name, i.entity_type, i.entity_title, i.status, i.current_step, i.total_steps, i.requested_login, i.created_at
    from public.app_process_instances i where (adm or i.tenant_id = ten) and (st is null or i.status = st)
    order by i.created_at desc;
end $$;

create or replace function public.app_process_task_act(p_token uuid, p_task_id uuid, p_action text, p_comment text, p_data jsonb)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; urole text; uname text; ten uuid; t record; inst record; steps jsonb; step jsonb; role text; nid uuid; due timestamptz; dh numeric; act text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.uid, s.urole, s.ulogin into uid, urole, uname from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  act := lower(trim(coalesce(p_action,'')));
  if act not in ('approve','reject','complete') then return query select false,'Действие: approve/reject/complete'; return; end if;
  select * into t from public.app_process_tasks where id = p_task_id and status = 'open' and tenant_id = ten;
  if t.id is null then return query select false,'Задача не найдена или закрыта'; return; end if;
  if not (public.app_is_platform_admin(p_token) or public.app_is_owner(p_token) or t.user_id = uid or t.role = urole) then
    return query select false,'Нет прав на эту задачу'; return;
  end if;
  select * into inst from public.app_process_instances where id = t.instance_id and status = 'running';
  if inst.id is null then return query select false,'Процесс уже завершён'; return; end if;

  update public.app_process_tasks set status = 'done', acted_at = now(), comment = nullif(trim(p_comment),''),
         data = coalesce(p_data, data) where id = p_task_id;
  insert into public.app_process_actions (instance_id, step_ord, actor, actor_login, action, comment)
  values (inst.id, t.step_ord, uid, uname, act, nullif(trim(p_comment),''));

  if act = 'reject' then
    update public.app_process_instances set status='rejected', updated_at=now() where id = inst.id;
    if inst.requested_by is not null then perform public.app_notif_send(inst.requested_by, 'Процесс отклонён', coalesce(inst.entity_title,''), 'apps/workflow/index.html'); end if;
    return query select true,'Процесс отклонён';
  end if;

  if inst.current_step < inst.total_steps then
    update public.app_process_instances set current_step = current_step + 1, updated_at = now() where id = inst.id;
    select d.steps into steps from public.app_process_defs d where d.id = inst.def_id;
    step := steps -> inst.current_step;   -- 0-based следующий
    role := nullif(step->>'role',''); nid := null;
    begin nid := (step->>'user_id')::uuid; exception when others then nid := null; end;
    dh := nullif(step->>'sla_hours','')::numeric;
    due := case when dh is not null then now() + (dh || ' hours')::interval else null end;
    insert into public.app_process_tasks (tenant_id, instance_id, step_ord, name, role, user_id, status, due_at)
    values (ten, inst.id, inst.current_step + 1, coalesce(step->>'name', role), role, nid, 'open', due);
    if nid is not null then perform public.app_notif_send(nid, 'Следующий этап процесса', coalesce(inst.entity_title,''), 'apps/workflow/index.html');
    elsif role is not null then perform public.app_notif_roles_t(ten, array[role], 'Следующий этап процесса', coalesce(inst.entity_title,''), 'apps/workflow/index.html'); end if;
    return query select true,'Этап пройден, передано дальше';
  else
    update public.app_process_instances set status='done', updated_at=now() where id = inst.id;
    if inst.requested_by is not null then perform public.app_notif_send(inst.requested_by, 'Процесс завершён', coalesce(inst.entity_title,''), 'apps/workflow/index.html'); end if;
    return query select true,'Процесс завершён';
  end if;
end $$;

create or replace function public.app_process_cancel(p_token uuid, p_instance_id uuid, p_comment text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; uid uuid; uname text; n integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.uid, s.ulogin into uid, uname from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  update public.app_process_instances i set status='cancelled', updated_at=now()
   where i.id = p_instance_id and i.status='running' and (public.app_is_platform_admin(p_token) or i.requested_by = uid or i.tenant_id = ten and public.app_is_owner(p_token));
  get diagnostics n = row_count;
  if n = 0 then return query select false,'Процесс не найден или не может быть отменён'; return; end if;
  update public.app_process_tasks set status='skipped' where instance_id = p_instance_id and status='open';
  insert into public.app_process_actions (instance_id, actor, actor_login, action, comment) values (p_instance_id, uid, uname, 'cancel', nullif(trim(p_comment),''));
  return query select true,'Процесс отменён';
end $$;

-- ================= RPC: правила (L2) =================
create or replace function public.app_rules_list(p_token uuid)
returns table (id uuid, name text, event text, condition jsonb, actions jsonb, active boolean, run_count integer, last_run timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query select r.id, r.name, r.event, r.condition, r.actions, r.active, r.run_count, r.last_run
    from public.app_rules r where adm or r.tenant_id = ten order by r.created_at desc;
end $$;

create or replace function public.app_rule_save(p_token uuid, p_id uuid, p_name text, p_event text, p_condition jsonb, p_actions jsonb, p_active boolean)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; uname text; newid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid; return; end if;
  select u.tenant_id, s.ulogin into ten, uname from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  if coalesce(trim(p_name),'') = '' or coalesce(trim(p_event),'') = '' then return query select false,'Укажите название и событие', null::uuid; return; end if;
  if p_actions is not null and jsonb_typeof(p_actions) <> 'array' then return query select false,'Действия должны быть массивом', null::uuid; return; end if;
  if p_id is null then
    insert into public.app_rules (tenant_id, name, event, condition, actions, active, created_login)
    values (ten, left(trim(p_name),140), trim(p_event), coalesce(p_condition,'{}'::jsonb), coalesce(p_actions,'[]'::jsonb), coalesce(p_active,true), uname)
    returning app_rules.id into newid;
    return query select true,'Правило создано', newid;
  else
    update public.app_rules r set name = left(trim(p_name),140), event = trim(p_event), condition = coalesce(p_condition, r.condition),
           actions = coalesce(p_actions, r.actions), active = coalesce(p_active, r.active)
     where r.id = p_id and (public.app_is_platform_admin(p_token) or r.tenant_id = ten)
     returning r.id into newid;
    if newid is null then return query select false,'Правило не найдено', null::uuid; return; end if;
    return query select true,'Правило сохранено', newid;
  end if;
end $$;

create or replace function public.app_rule_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; n integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten := public.app_my_tenant(p_token);
  delete from public.app_rules r where r.id = p_id and (public.app_is_platform_admin(p_token) or r.tenant_id = ten);
  get diagnostics n = row_count;
  if n = 0 then return query select false,'Правило не найдено'; return; end if;
  return query select true,'Правило удалено';
end $$;

-- Движок правил: оценивает условие против контекста и выполняет действия (notify/audit/start_process).
create or replace function public.app_rule_run(p_token uuid, p_event text, p_context jsonb)
returns table (fired integer, messages text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; r record; cond jsonb; fld text; op text; val text; ctxv text; ok boolean; ac jsonb; at text; prm jsonb; cnt integer := 0; msg text := ''; roles text[]; au uuid; defid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select 0,'Доступ запрещён'; return; end if;
  ten := public.app_my_tenant(p_token);
  for r in select * from public.app_rules where tenant_id = ten and active and event = p_event order by created_at
  loop
    cond := coalesce(r.condition,'{}'::jsonb);
    fld := cond->>'field'; op := lower(coalesce(cond->>'op','')); val := cond->>'value';
    if fld is null or fld = '' then ok := true;
    else
      ctxv := p_context->>fld;
      ok := case op
        when 'eq' then ctxv = val
        when 'ne' then ctxv is distinct from val
        when 'contains' then coalesce(ctxv,'') ilike '%'||coalesce(val,'')||'%'
        when 'gt' then (nullif(ctxv,''))::numeric > (nullif(val,''))::numeric
        when 'lt' then (nullif(ctxv,''))::numeric < (nullif(val,''))::numeric
        else ctxv = val end;
    end if;
    if coalesce(ok,false) then
      for ac in select * from jsonb_array_elements(coalesce(r.actions,'[]'::jsonb)) loop
        at := lower(coalesce(ac->>'type','')); prm := coalesce(ac->'params','{}'::jsonb);
        if at = 'notify' then
          au := null; begin au := (prm->>'user_id')::uuid; exception when others then au := null; end;
          if au is not null then perform public.app_notif_send(au, coalesce(prm->>'title','Правило'), coalesce(prm->>'body', p_context::text), prm->>'link');
          else
            roles := null; begin roles := array(select jsonb_array_elements_text(prm->'roles')); exception when others then roles := null; end;
            if roles is not null then perform public.app_notif_roles_t(ten, roles, coalesce(prm->>'title','Правило'), coalesce(prm->>'body', p_context::text), prm->>'link'); end if;
          end if;
        elsif at = 'audit' then
          perform public.app_audit_write(p_token, coalesce(prm->>'module','rules'), coalesce(prm->>'action','trigger'), p_context->>'entity_type', nullif(p_context->>'entity_id','')::uuid, p_context);
        elsif at = 'start_process' then
          defid := null; begin defid := (prm->>'process_id')::uuid; exception when others then defid := null; end;
          if defid is not null then perform public.app_process_start(p_token, defid, p_context->>'entity_type', nullif(p_context->>'entity_id','')::uuid, p_context->>'entity_title', p_context); end if;
        end if;
      end loop;
      update public.app_rules set run_count = run_count + 1, last_run = now() where id = r.id;
      cnt := cnt + 1; msg := msg || case when msg='' then '' else '; ' end || r.name;
    end if;
  end loop;
  return query select cnt, case when cnt=0 then 'Правила не сработали' else 'Сработали: ' || msg end;
end $$;

-- ================= Демо =================
insert into public.app_process_defs (tenant_id, name, code, doc_type, entity_type, steps, active, created_login)
select 'aaaaaaaa-0000-0000-0000-000000000001', 'Согласование заявки (workflow)', 'order_approve', 'order', 'order',
       '[{"ord":1,"name":"Начальник цеха","role":"chief","sla_hours":24},{"ord":2,"name":"Директор","role":"director","sla_hours":48}]'::jsonb, true, 'owner'
where not exists (select 1 from public.app_process_defs where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and code='order_approve');

insert into public.app_rules (tenant_id, name, event, condition, actions, active, created_login)
select 'aaaaaaaa-0000-0000-0000-000000000001', 'Уведомлять снабжение о новых заявках на закупку', 'order_created',
       '{"field":"source","op":"contains","value":"снаб"}'::jsonb,
       '[{"type":"notify","params":{"roles":["supply"],"title":"Новая заявка (снабжение)","body":"Требуется обработка","link":"apps/orders/index.html"}},{"type":"audit","params":{"module":"rules","action":"order_created"}}]'::jsonb, true, 'owner'
where not exists (select 1 from public.app_rules where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and name='Уведомлять снабжение о новых заявках на закупку');

insert into public.app_form_defs (tenant_id, code, name, module, fields, created_login)
select 'aaaaaaaa-0000-0000-0000-000000000001', 'order_extra', 'Доп. поля заявки', 'orders',
       '[{"key":"reason","label":"Причина срочности","type":"text","required":false},{"key":"budget","label":"Бюджет, ₽","type":"number"}]'::jsonb, 'owner'
where not exists (select 1 from public.app_form_defs where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and code='order_extra');

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Платформа','Low-code workflow: процессы, правила, формы',
   'W15: конструктор процессов (app_process_defs со шагами-ролями/SLA; запуск app_process_start; задачи этапов app_process_tasks; «мои задачи» app_process_my; действия app_process_task_act approve/reject/complete; отмена app_process_cancel; история app_process_actions); правила/триггеры (app_rules: событие + условие + действия; движок app_rule_run — notify/audit/start_process); конструктор форм (app_form_defs — кастомные поля карточек). Модуль «Процессы и автоматизация» (apps/workflow).',
   'low-code workflow процесс этапы задачи правила триггеры роботы формы SLA автоматизация')
) as v(category,question,answer,tags)
where not exists (
  select 1 from public.app_knowledge
   where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001' and question = 'Low-code workflow: процессы, правила, формы'
);

-- ---------- Права ----------
grant execute on function public.app_form_defs_list(uuid) to anon, authenticated;
grant execute on function public.app_form_def_save(uuid,uuid,text,text,text,jsonb) to anon, authenticated;
grant execute on function public.app_form_def_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_process_defs_list(uuid) to anon, authenticated;
grant execute on function public.app_process_def_save(uuid,uuid,text,text,text,text,jsonb,boolean) to anon, authenticated;
grant execute on function public.app_process_def_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_process_start(uuid,uuid,text,uuid,text,jsonb) to anon, authenticated;
grant execute on function public.app_process_my(uuid) to anon, authenticated;
grant execute on function public.app_process_instances_list(uuid,text) to anon, authenticated;
grant execute on function public.app_process_task_act(uuid,uuid,text,text,jsonb) to anon, authenticated;
grant execute on function public.app_process_cancel(uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_rules_list(uuid) to anon, authenticated;
grant execute on function public.app_rule_save(uuid,uuid,text,text,jsonb,jsonb,boolean) to anon, authenticated;
grant execute on function public.app_rule_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_rule_run(uuid,text,jsonb) to anon, authenticated;
