-- ============================================================
-- 3DMP Service · 0201_safety2.sql  (X6 — EHS/OHS 2.0, safety)
-- Сроки EHS (app_safety_scan), наряд-допуск → задача (app_permit_to_task),
-- выдача СИЗ со склада (app_ppe_issue), связь допуска с задачей/нарядом.
-- Идемпотентно. Зависит от 0001..0200.
-- ============================================================

alter table public.app_work_permits add column if not exists task_id   uuid references public.app_tasks (id) on delete set null;
alter table public.app_work_permits add column if not exists naryad_id uuid references public.app_naryads (id) on delete set null;

-- ================= RPC: сроки EHS =================
create or replace function public.app_safety_scan(p_token uuid, p_days integer default 30)
returns table (briefings integer, ppe integer, medical integer, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid; d integer; b integer; pp integer; md integer; rec record;
begin
  if not public.app_production_allowed(p_token) then return query select 0,0,0,'Доступ запрещён'; return; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  d := greatest(coalesce(p_days,30),1);
  select count(*) into b from public.app_safety_briefings x where (adm or x.tenant_id=ten) and x.next_date is not null and x.next_date <= current_date + d;
  select count(*) into pp from public.app_ppe x where (adm or x.tenant_id=ten) and x.status='issued' and x.due_at is not null and x.due_at <= current_date + d;
  select count(*) into md from public.app_medical_checks x where (adm or x.tenant_id=ten) and x.next_date is not null and x.next_date <= current_date + d;
  for rec in
    select 'Инструктаж' as kind, x.employee_login as who, x.next_date as dt from public.app_safety_briefings x
      where (adm or x.tenant_id=ten) and x.next_date is not null and x.next_date <= current_date + d
    union all
    select 'СИЗ', x.employee_login, x.due_at from public.app_ppe x
      where (adm or x.tenant_id=ten) and x.status='issued' and x.due_at is not null and x.due_at <= current_date + d
    union all
    select 'Медосмотр', x.employee_login, x.next_date from public.app_medical_checks x
      where (adm or x.tenant_id=ten) and x.next_date is not null and x.next_date <= current_date + d
  loop
    perform public.app_notif_roles_t(ten, array['admin','owner','manager','hr','chief'], 'EHS: срок ' || rec.kind,
      coalesce(rec.who,'') || ' — до ' || to_char(rec.dt,'DD.MM.YYYY'), 'apps/safety/index.html');
  end loop;
  return query select b, pp, md, 'Инструктажи: ' || b || ', СИЗ: ' || pp || ', медосмотры: ' || md;
end $$;

-- ================= RPC: наряд-допуск → задача =================
create or replace function public.app_permit_to_task(p_token uuid, p_permit_id uuid)
returns table (ok boolean, message text, task_id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid; uname text; p record; tid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid; return; end if;
  if not public.app_can_edit(p_token, 'safety') then return query select false,'Нет прав', null::uuid; return; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  select s.ulogin into uname from public.app_session_user(p_token) s;
  select * into p from public.app_work_permits where id = p_permit_id and (adm or tenant_id = ten);
  if p.id is null then return query select false,'Наряд-допуск не найден', null::uuid; return; end if;
  if p.task_id is not null then return query select false,'Задача уже создана', p.task_id; return; end if;
  insert into public.app_tasks (tenant_id, title, description, status, priority, assignee_login, due_date, entity_type, entity_id, pos, created_login)
  values (ten, 'Наряд-допуск ' || coalesce(p.number,'') || ' (' || coalesce(p.work_type,'') || ')',
          'Работы: ' || coalesce(p.location,'') || '. Работники: ' || coalesce(p.workers,''),
          'todo', 'high', p.responsible_login, p.valid_to, 'work_permit', p.id, 0, uname)
  returning app_tasks.id into tid;
  update public.app_work_permits set task_id = tid where id = p.id;
  return query select true,'Задача по наряду-допуску создана', tid;
end $$;

-- ================= RPC: выдача СИЗ со склада =================
create or replace function public.app_ppe_issue(p_token uuid, p_ppe_id uuid, p_material_code text, p_qty numeric)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid; mat uuid; r record;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  if not public.app_can_edit(p_token, 'safety') then return query select false,'Нет прав'; return; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  if p_ppe_id is not null then
    if not exists (select 1 from public.app_ppe where id = p_ppe_id and (adm or tenant_id = ten)) then
      return query select false,'Запись СИЗ не найдена'; return;
    end if;
  end if;
  select m.id into mat from public.app_materials m
   where (adm or m.tenant_id = ten) and (lower(m.code) = lower(trim(p_material_code)) or lower(m.name) = lower(trim(p_material_code))) limit 1;
  if mat is null then return query select false,'Материал по коду не найден: ' || coalesce(p_material_code,''); return; end if;
  select * into r from public.app_stock_move(p_token, mat, 'out', coalesce(p_qty,1), null, 'Выдача СИЗ', 'ppe') x;
  if not r.ok then return query select false, r.message; return; end if;
  if p_ppe_id is not null then update public.app_ppe set status = 'issued', issued_at = current_date where id = p_ppe_id; end if;
  return query select true, 'СИЗ выданы со склада: ' || coalesce(r.message,'');
end $$;

-- ================= База знаний =================
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Охрана труда','EHS 2.0: сроки (инструктаж/СИЗ/медосмотр), допуск→задача, выдача СИЗ (X6)',
   'EHS 2.0: дашборд сроков (app_safety_scan — просрочки инструктажей, СИЗ, медосмотров + уведомления), наряд-допуск → задача (app_permit_to_task — создаёт app_tasks, связь app_work_permits.task_id; поля task_id/naryad_id), выдача СИЗ со склада (app_ppe_issue — списание через app_stock_move). Связи: hr/competences (допуск при компетенции), warehouse (СИЗ), tasks/workflow.',
   'охрана труда EHS сроки инструктаж СИЗ медосмотр наряд-допуск задача склад')
) as v(category,question,answer,tags)
where not exists (
  select 1 from public.app_knowledge
   where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001'
     and question = 'EHS 2.0: сроки (инструктаж/СИЗ/медосмотр), допуск→задача, выдача СИЗ (X6)'
);

-- ================= Права =================
grant execute on function public.app_safety_scan(uuid,integer) to anon, authenticated;
grant execute on function public.app_permit_to_task(uuid,uuid) to anon, authenticated;
grant execute on function public.app_ppe_issue(uuid,uuid,text,numeric) to anon, authenticated;
