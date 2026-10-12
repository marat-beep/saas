-- ============================================================
-- 3DMP Service · 0200_staff2.sql  (X3 — CRM сотрудников 2.0)
-- Онбординг чек-лист (app_onboarding_tasks), оценки 360 (app_reviews),
-- текучесть по периодам. Идемпотентно. Зависит от 0001..0199.
-- ============================================================

create table if not exists public.app_onboarding_tasks (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  staff_id      uuid not null references public.app_staff_crm (id) on delete cascade,
  step          text not null,
  assignee      text,
  due_date      date,
  status        text not null default 'planned',  -- planned|done|skipped
  note          text,
  task_id       uuid references public.app_tasks (id) on delete set null,
  created_login text,
  created_at    timestamptz not null default now()
);
create index if not exists app_onboarding_tasks_idx on public.app_onboarding_tasks (tenant_id, staff_id, status);
alter table public.app_onboarding_tasks enable row level security;

create table if not exists public.app_reviews (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  staff_id      uuid references public.app_staff_crm (id) on delete cascade,
  period        text,
  scores        jsonb not null default '[]'::jsonb,   -- [{"criterion":"...","score":4}]
  total         numeric,
  reviewer      text,
  note          text,
  created_login text,
  created_at    timestamptz not null default now()
);
create index if not exists app_reviews_idx on public.app_reviews (tenant_id, staff_id, created_at desc);
alter table public.app_reviews enable row level security;

alter table public.app_staff_crm add column if not exists fired_at date;

-- ================= RPC: онбординг =================
create or replace function public.app_onboard_list(p_token uuid, p_staff_id uuid default null)
returns table (id uuid, staff_id uuid, staff_name text, step text, assignee text, due_date date, status text, task_id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query
    select o.id, o.staff_id, s.name, o.step, o.assignee, o.due_date, o.status, o.task_id
      from public.app_onboarding_tasks o left join public.app_staff_crm s on s.id = o.staff_id
     where (adm or o.tenant_id = ten) and (p_staff_id is null or o.staff_id = p_staff_id)
     order by o.staff_id, o.due_date nulls last, o.step;
end $$;

create or replace function public.app_onboard_start(p_token uuid, p_staff_id uuid)
returns table (ok boolean, message text, created integer)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid; uname text; rec record; cnt integer := 0; sname text; tid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', 0; return; end if;
  if not public.app_can_edit(p_token, 'staff') then return query select false,'Нет прав', 0; return; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  select s.ulogin into uname from public.app_session_user(p_token) s;
  select name into sname from public.app_staff_crm where id = p_staff_id and (adm or tenant_id = ten);
  if sname is null then return query select false,'Сотрудник не найден', 0; return; end if;
  if exists (select 1 from public.app_onboarding_tasks where staff_id = p_staff_id) then
    return query select false,'Онбординг уже запущен', 0; return;
  end if;
  for rec in
    select * from (values
      ('Оформление документов', 'hr', 0),
      ('Инструктаж по ТБ', 'hr', 1),
      ('Знакомство с командой', 'manager', 2),
      ('Доступы и оборудование', 'support', 3),
      ('Цели на испытательный срок', 'manager', 7)
    ) as t(step, assignee, days)
  loop
    insert into public.app_tasks (tenant_id, title, description, status, priority, assignee_login, due_date, entity_type, entity_id, pos, created_login)
    values (ten, 'Онбординг: ' || rec.step, 'Шаг адаптации ' || sname, 'todo', 'normal', rec.assignee, current_date + rec.days, 'onboarding', p_staff_id, rec.days, uname)
    returning app_tasks.id into tid;
    insert into public.app_onboarding_tasks (tenant_id, staff_id, step, assignee, due_date, task_id, created_login)
    values (ten, p_staff_id, rec.step, rec.assignee, current_date + rec.days, tid, uname);
    cnt := cnt + 1;
  end loop;
  return query select true, 'Онбординг запущен: шагов ' || cnt, cnt;
end $$;

create or replace function public.app_onboard_item_set_status(p_token uuid, p_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; st text; n integer; tid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten := public.app_my_tenant(p_token);
  st := lower(trim(coalesce(p_status,'')));
  if st not in ('planned','done','skipped') then return query select false,'Недопустимый статус'; return; end if;
  update public.app_onboarding_tasks o set status = st where o.id = p_id and (public.app_is_platform_admin(p_token) or o.tenant_id = ten)
   returning o.task_id into tid;
  get diagnostics n = row_count;
  if n = 0 then return query select false,'Шаг не найден'; return; end if;
  if tid is not null then
    update public.app_tasks set status = case when st='done' then 'done' when st='skipped' then 'cancelled' else 'todo' end where id = tid;
  end if;
  return query select true,'Шаг: ' || st;
end $$;

create or replace function public.app_onboard_scan(p_token uuid)
returns table (notified integer, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid; cnt integer := 0; rec record;
begin
  if not public.app_production_allowed(p_token) then return query select 0,'Доступ запрещён'; return; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  for rec in
    select o.step, o.due_date, s.name
      from public.app_onboarding_tasks o join public.app_staff_crm s on s.id = o.staff_id
     where (adm or o.tenant_id = ten) and o.status = 'planned' and o.due_date is not null and o.due_date < current_date
  loop
    perform public.app_notif_roles_t(ten, array['admin','owner','manager','hr'], 'Онбординг просрочен: ' || rec.name,
      rec.step || ' — до ' || to_char(rec.due_date,'DD.MM'), 'apps/staff/index.html');
    cnt := cnt + 1;
  end loop;
  return query select cnt, 'Просроченных шагов онбординга: ' || cnt;
end $$;

-- ================= RPC: оценки 360 =================
create or replace function public.app_review_list(p_token uuid, p_staff_id uuid default null)
returns table (id uuid, staff_id uuid, staff_name text, period text, total numeric, reviewer text, scores jsonb, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query
    select r.id, r.staff_id, s.name, r.period, r.total, r.reviewer, r.scores, r.created_at
      from public.app_reviews r left join public.app_staff_crm s on s.id = r.staff_id
     where (adm or r.tenant_id = ten) and (p_staff_id is null or r.staff_id = p_staff_id)
     order by r.created_at desc;
end $$;

create or replace function public.app_review_save(p_token uuid, p_id uuid, p_staff_id uuid, p_period text, p_scores jsonb, p_total numeric, p_reviewer text, p_note text)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; uname text; newid uuid; sc jsonb; calc numeric;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid; return; end if;
  if not public.app_can_edit(p_token, 'staff') then return query select false,'Нет прав', null::uuid; return; end if;
  select u.tenant_id, s.ulogin into ten, uname from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  if p_staff_id is null then return query select false,'Укажите сотрудника', null::uuid; return; end if;
  sc := case when p_scores is null or jsonb_typeof(p_scores) <> 'array' then '[]'::jsonb else p_scores end;
  calc := coalesce(p_total, round((select avg((x->>'score')::numeric) from jsonb_array_elements(sc) x), 2));
  if p_id is null then
    insert into public.app_reviews (tenant_id, staff_id, period, scores, total, reviewer, note, created_login)
    values (ten, p_staff_id, nullif(trim(p_period),''), sc, calc, nullif(trim(p_reviewer),''), nullif(trim(p_note),''), uname)
    returning app_reviews.id into newid;
    update public.app_staff_crm set rating = calc where id = p_staff_id;
    return query select true,'Оценка сохранена', newid;
  else
    update public.app_reviews r set staff_id = p_staff_id, period = nullif(trim(p_period),''), scores = sc, total = calc,
           reviewer = nullif(trim(p_reviewer),''), note = nullif(trim(p_note),'')
     where r.id = p_id and (public.app_is_platform_admin(p_token) or r.tenant_id = ten)
     returning r.id into newid;
    if newid is null then return query select false,'Оценка не найдена', null::uuid; return; end if;
    return query select true,'Оценка сохранена', newid;
  end if;
end $$;

create or replace function public.app_review_kpi(p_token uuid)
returns table (reviews bigint, avg_total numeric, top bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query select
    (select count(*) from public.app_reviews r where adm or r.tenant_id=ten),
    (select round(avg(r.total),2) from public.app_reviews r where (adm or r.tenant_id=ten) and r.total is not null),
    (select count(*) from public.app_reviews r where (adm or r.tenant_id=ten) and r.total >= 4);
end $$;

-- ================= RPC: текучесть =================
create or replace function public.app_staff_turnover(p_token uuid, p_months integer default 12)
returns table (month date, hired bigint, fired bigint, headcount bigint, turnover_pct numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid; v_months int; i int; m date; h bigint; f bigint; hc bigint;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  v_months := greatest(least(coalesce(p_months,12),36),1);
  for i in reverse (v_months - 1) .. 0 loop
    m := date_trunc('month', current_date - (i || ' month')::interval)::date;
    select count(*) into h from public.app_staff_crm s where (adm or s.tenant_id=ten) and date_trunc('month', s.hired_at) = m;
    select count(*) into f from public.app_staff_crm s where (adm or s.tenant_id=ten) and s.fired_at is not null and date_trunc('month', s.fired_at) = m;
    select count(*) into hc from public.app_staff_crm s
      where (adm or s.tenant_id=ten) and s.hired_at <= (m + interval '1 month - 1 day')::date
        and (s.fired_at is null or s.fired_at > (m + interval '1 month - 1 day')::date);
    month := m; hired := h; fired := f; headcount := hc;
    turnover_pct := round(100.0 * f / greatest(hc, 1), 1);
    return next;
  end loop;
end $$;

-- ================= База знаний =================
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Персонал','CRM сотрудников 2.0: онбординг, оценка 360, текучесть (X3)',
   'CRM сотрудников 2.0: онбординг (app_onboarding_tasks + app_onboard_start — чек-лист из шаблона, создаёт задачи в app_tasks; app_onboard_list/item_set_status/scan), оценка 360 (app_reviews + app_review_save/list и авто-итог; app_review_kpi), текучесть по месяцам (app_staff_turnover — найм/увольнение/численность/%). Поле app_staff_crm.fired_at. Связи: tasks, hr, kedo.',
   'персонал CRM сотрудников онбординг адаптация оценка 360 текучесть увольнение')
) as v(category,question,answer,tags)
where not exists (
  select 1 from public.app_knowledge
   where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001'
     and question = 'CRM сотрудников 2.0: онбординг, оценка 360, текучесть (X3)'
);

-- ================= Права =================
grant execute on function public.app_onboard_list(uuid,uuid) to anon, authenticated;
grant execute on function public.app_onboard_start(uuid,uuid) to anon, authenticated;
grant execute on function public.app_onboard_item_set_status(uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_onboard_scan(uuid) to anon, authenticated;
grant execute on function public.app_review_list(uuid,uuid) to anon, authenticated;
grant execute on function public.app_review_save(uuid,uuid,uuid,text,jsonb,numeric,text,text) to anon, authenticated;
grant execute on function public.app_review_kpi(uuid) to anon, authenticated;
grant execute on function public.app_staff_turnover(uuid,integer) to anon, authenticated;
