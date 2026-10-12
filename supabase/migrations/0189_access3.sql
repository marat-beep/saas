-- ============================================================
-- 3DMP Service · 0189_access3.sql  (X5 — Оргструктура и доступ 2.0)
-- Роль×модуль×ДЕЙСТВИЕ (view/edit/approve): app_can v3 + матрица.
-- Сквозной гейтинг по подразделению (app_dept_ok) — распространение на рабочие списки.
-- Идемпотентно. Зависит от 0001..0188.
-- ============================================================

alter table public.app_role_permissions add column if not exists can_approve boolean not null default false;

-- ---------- app_can v3: просмотр / правка / утверждение ----------
create or replace function public.app_can(p_token uuid, p_module text, p_action text)
returns boolean
language plpgsql stable security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; vw boolean; ed boolean; ap boolean; act text;
begin
  select s.urole into urole from public.app_session_user(p_token) s;
  if urole is null then return false; end if;
  if urole in ('admin','owner') then return true; end if;
  ten := public.app_my_tenant(p_token);
  select p.can_view, p.can_edit, coalesce(p.can_approve,false) into vw, ed, ap
    from public.app_role_permissions p
    where p.role = urole and p.module_id = p_module and (p.tenant_id = ten or p.tenant_id is null)
    limit 1;
  act := lower(coalesce(p_action,'view'));
  if found then
    if act = 'edit' then return ed;
    elsif act = 'approve' then return coalesce(ap,false) or coalesce(ed,false);
    else return vw; end if;
  end if;
  return act = 'view';   -- строки нет: просмотр разрешён, правка/утверждение — нет
end $$;

-- ---------- Матрица прав: получение/запись (роль×модуль×действие) ----------
create or replace function public.app_perms_matrix_get(p_token uuid)
returns table (role text, module_id text, can_view boolean, can_edit boolean, can_approve boolean)
language plpgsql stable security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid;
begin
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  if not (adm or public.app_is_owner(p_token) or public.app_can_view(p_token,'roles')) then
    raise exception 'Доступ запрещён';
  end if;
  return query
    select p.role, p.module_id, p.can_view, p.can_edit, coalesce(p.can_approve,false)
      from public.app_role_permissions p
     where (adm or p.tenant_id = ten or p.tenant_id is null)
     order by p.role, p.module_id;
end $$;

create or replace function public.app_perms_matrix_set(p_token uuid, p_role text, p_module text, p_view boolean, p_edit boolean, p_approve boolean)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; rl text; vid boolean; eid boolean; aid boolean; n integer;
begin
  if not (public.app_is_platform_admin(p_token) or public.app_is_owner(p_token)) then
    return query select false,'Только владелец/администратор'; return;
  end if;
  if coalesce(trim(p_role),'') = '' or coalesce(trim(p_module),'') = '' then
    return query select false,'Укажите роль и модуль'; return;
  end if;
  ten := public.app_my_tenant(p_token);
  rl := lower(trim(p_role));
  vid := coalesce(p_view,false); eid := coalesce(p_edit,false); aid := coalesce(p_approve,false);
  if eid and not vid then vid := true; end if;
  if aid and not vid then vid := true; end if;
  update public.app_role_permissions p set can_view = vid, can_edit = eid, can_approve = aid
   where p.role = rl and p.module_id = p_module and (p.tenant_id = ten or p.tenant_id is null);
  get diagnostics n = row_count;
  if n = 0 then
    insert into public.app_role_permissions (tenant_id, role, module_id, can_view, can_edit, can_approve)
    values (ten, rl, p_module, vid, eid, aid);
  end if;
  return query select true,'Сохранено (просмотр/правка/утверждение)';
end $$;

-- Действия по одной роли/модулю (для UI ролей и модуля «Доступ»)
create or replace function public.app_role_actions_get(p_token uuid, p_module text)
returns table (role text, can_view boolean, can_edit boolean, can_approve boolean)
language plpgsql stable security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid;
begin
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query
    select p.role, p.can_view, p.can_edit, coalesce(p.can_approve,false)
      from public.app_role_permissions p
     where (adm or p.tenant_id = ten or p.tenant_id is null) and p.module_id = p_module
     order by p.role;
end $$;

-- ---------- Гейтинг по подразделению: массовое включение ----------
create or replace function public.app_dept_scope_apply(p_token uuid, p_enabled boolean)
returns table (ok boolean, message text, enabled boolean)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare r record;
begin
  select * into r from public.app_dept_scope_set(p_token, p_enabled) x;
  return query select r.ok, r.message, r.enabled;
end $$;

-- ---------- Поля подразделения к рабочим таблицам (для сквозного гейтинга) ----------
alter table public.app_service_requests add column if not exists department_id uuid;
alter table public.app_tasks            add column if not exists department_id uuid;
alter table public.app_qc_checks        add column if not exists department_id uuid;
alter table public.app_documents        add column if not exists department_id uuid;
alter table public.app_deals            add column if not exists department_id uuid;

update public.app_service_requests r set department_id = e.department_id
  from public.app_employees e
 where e.user_login = r.assigned_login and e.tenant_id = r.tenant_id and r.department_id is null and e.department_id is not null;
update public.app_tasks t set department_id = e.department_id
  from public.app_employees e
 where e.user_login = t.assignee_login and e.tenant_id = t.tenant_id and t.department_id is null and e.department_id is not null;

-- ---------- Сквозной гейтинг в списках (service, tasks) ----------
create or replace function public.app_service_list(p_token uuid, p_q text default null)
returns table (id uuid, number text, customer text, equipment text, title text, kind text, status text, priority text,
               channel text, source text, is_warranty boolean, assigned_login text, engineer text,
               scheduled_date date, reported_at timestamptz, response_due timestamptz, resolve_due timestamptz,
               first_response_at timestamptz, resolved_at timestamptz, cost numeric, parts_cost numeric,
               sla_state text, warranty_license text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query
    select s.id, s.number, c.name, e.name, s.title, s.kind, s.status, s.priority,
           s.channel, s.source, s.is_warranty, s.assigned_login, s.engineer,
           s.scheduled_date, s.reported_at, s.response_due, s.resolve_due,
           s.first_response_at, s.resolved_at, s.cost, s.parts_cost,
           case when s.status = 'done' then 'closed'
                when s.resolve_due is not null and s.resolve_due < now() then 'overdue'
                when s.resolve_due is not null and s.resolve_due < now() + interval '2 hours' then 'warn'
                else 'ok' end,
           w.license_no, s.created_at
    from public.app_service_requests s
    left join public.app_customers c on c.id = s.customer_id
    left join public.app_equipment e on e.id = s.equipment_id
    left join public.app_warranties w on w.id = s.warranty_id
    where (urole='admin' or s.tenant_id = ten)
      and public.app_dept_ok(p_token, s.department_id)
      and (qq=''
        or lower(s.title) like '%'||qq||'%' or lower(coalesce(s.number,'')) like '%'||qq||'%'
        or lower(coalesce(c.name,'')) like '%'||qq||'%'
        or lower(coalesce(e.name,'')) like '%'||qq||'%' or lower(coalesce(e.code,'')) like '%'||qq||'%'
        or lower(coalesce(s.engineer,'')) like '%'||qq||'%' or lower(coalesce(s.assigned_login,'')) like '%'||qq||'%'
        or lower(coalesce(s.fault_code,'')) like '%'||qq||'%'
        or lower(coalesce(w.number,'')) like '%'||qq||'%' or lower(coalesce(w.license_no,'')) like '%'||qq||'%')
    order by (s.priority='critical') desc, s.created_at desc;
end $$;

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
       and public.app_dept_ok(p_token, t.department_id)
       and (p_project_id is null or t.project_id = p_project_id)
       and (st is null or t.status = st)
       and (p_assignee is null or p_assignee = '' or t.assignee_login = p_assignee)
     order by t.pos, t.created_at;
end $$;

-- ---------- Сидирование «утверждение» для контрольных ролей ----------
update public.app_role_permissions set can_approve = true
 where can_edit and role in ('manager','director','chief','hr');

-- ================= База знаний =================
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Роли','Доступ 2.0: роль × модуль × действие (просмотр/правка/утверждение)',
   'X5: матрица прав различает три действия — просмотр (can_view), правка (can_edit), утверждение (can_approve). Серверная проверка app_can(token, модуль, действие): admin/owner — всё; иначе по строке матрицы; если строки нет — только просмотр. Управление — в модуле «Роли» (app_perms_matrix_get/set, app_role_actions_get). Утверждение используется маршрутами согласований (W10) и операциями подтверждения.',
   'доступ права матрица роль модуль действие просмотр правка утверждение approve'),
  ('Платформа','Сквозной гейтинг по подразделению (R4/X5)',
   'Сквозной доступ по подразделению: переключатель app_dept_scope_set/app_dept_scope_apply (владелец/админ), состояние app_dept_scope_get, отдел пользователя app_my_department, предикат app_dept_ok. При включении рабочие списки фильтруются по подразделению записи: заявки и наряды (R4), кадры/график/отсутствия (X1), сервис и задачи (X5). admin/owner/manager и записи без подразделения не ограничиваются.',
   'доступ подразделение гейтинг department scope фильтр списки service tasks')
) as v(category,question,answer,tags)
where not exists (
  select 1 from public.app_knowledge
   where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001'
     and question = v.question
);

-- ================= Права =================
grant execute on function public.app_can(uuid,text,text) to anon, authenticated;
grant execute on function public.app_perms_matrix_get(uuid) to anon, authenticated;
grant execute on function public.app_perms_matrix_set(uuid,text,text,boolean,boolean,boolean) to anon, authenticated;
grant execute on function public.app_role_actions_get(uuid,text) to anon, authenticated;
grant execute on function public.app_dept_scope_apply(uuid,boolean) to anon, authenticated;
grant execute on function public.app_service_list(uuid,text) to anon, authenticated;
grant execute on function public.app_tasks_list(uuid,uuid,text,text) to anon, authenticated;
