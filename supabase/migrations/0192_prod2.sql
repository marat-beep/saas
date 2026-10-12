-- ============================================================
-- 3DMP Service · 0192_prod2.sql  (X10 — Производство 2.0)
-- Таймеры операций (started_at/finished_at), брак/переделки (app_defects + поля),
-- сменно-суточные задания (app_daily_jobs), маршрутная карта (app_route_card).
-- Идемпотентно. Зависит от 0001..0191.
-- ============================================================

alter table public.app_naryad_ops add column if not exists started_at  timestamptz;
alter table public.app_naryad_ops add column if not exists finished_at timestamptz;

alter table public.app_defects add column if not exists naryad_op_id uuid references public.app_naryad_ops (id) on delete set null;
alter table public.app_defects add column if not exists cause        text;
alter table public.app_defects add column if not exists culprit_login text;
alter table public.app_defects add column if not exists cost        numeric;

create table if not exists public.app_daily_jobs (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  job_date      date not null,
  wc_id         uuid,
  naryad_id     uuid references public.app_naryads (id) on delete cascade,
  op_id         uuid references public.app_naryad_ops (id) on delete cascade,
  title         text,
  plan_hours    numeric default 0,
  assignee      text,
  status        text not null default 'planned',  -- planned|in_work|done
  note          text,
  created_login text,
  created_at    timestamptz not null default now()
);
create index if not exists app_daily_jobs_idx on public.app_daily_jobs (tenant_id, job_date);
alter table public.app_daily_jobs enable row level security;

-- ================= RPC: таймер операции =================
create or replace function public.app_op_start(p_token uuid, p_op_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare n integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  update public.app_naryad_ops op set started_at = now(), finished_at = null where op.id = p_op_id and not op.done;
  get diagnostics n = row_count;
  if n = 0 then return query select false,'Операция не найдена или выполнена'; return; end if;
  return query select true,'Таймер запущен';
end $$;

create or replace function public.app_op_stop(p_token uuid, p_op_id uuid)
returns table (ok boolean, message text, hours numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare st timestamptz; hrs numeric;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::numeric; return; end if;
  select started_at into st from public.app_naryad_ops where id = p_op_id;
  if st is null then return query select false,'Таймер не запущен', null::numeric; return; end if;
  hrs := round((extract(epoch from (now() - st)) / 3600.0)::numeric, 3);
  update public.app_naryad_ops op set finished_at = now(), fact_hours = coalesce(op.fact_hours,0) + hrs where op.id = p_op_id;
  update public.app_naryads n set fact_hours = (select coalesce(sum(op.fact_hours),0) from public.app_naryad_ops op where op.naryad_id = n.id), updated_at = now()
   where n.id = (select op.naryad_id from public.app_naryad_ops op where op.id = p_op_id);
  return query select true,'Таймер остановлен (+' || hrs || ' ч)', hrs;
end $$;

-- ================= RPC: брак/переделки =================
create or replace function public.app_prod_defect_save(p_token uuid, p_id uuid, p_naryad_op_id uuid, p_qty numeric, p_cause text,
  p_culprit text, p_cost numeric, p_severity text, p_note text)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; uname text; newid uuid; opr record; sev text; ttl text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid; return; end if;
  select u.tenant_id, s.ulogin into ten, uname from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  select o.id, o.naryad_id, o.operation into opr from public.app_naryad_ops o where o.id = p_naryad_op_id;
  if opr.id is null then return query select false,'Операция не найдена', null::uuid; return; end if;
  if not exists (select 1 from public.app_naryads n where n.id = opr.naryad_id and (public.app_is_platform_admin(p_token) or n.tenant_id = ten)) then
    return query select false,'Наряд не найден', null::uuid; return;
  end if;
  sev := coalesce(nullif(trim(p_severity),''),'minor');
  ttl := coalesce(nullif(trim(p_cause),''), 'Брак: ' || opr.operation);
  if p_id is null then
    insert into public.app_defects (tenant_id, naryad_op_id, title, qty, severity, cause, culprit_login, cost, note, by_login)
    values (ten, p_naryad_op_id, left(ttl,200), coalesce(p_qty,1), sev, nullif(trim(p_cause),''), nullif(trim(p_culprit),''), p_cost, nullif(trim(p_note),''), uname)
    returning app_defects.id into newid;
  else
    update public.app_defects d set naryad_op_id = p_naryad_op_id, title = left(ttl,200), qty = coalesce(p_qty,d.qty), severity = sev,
           cause = nullif(trim(p_cause),''), culprit_login = nullif(trim(p_culprit),''), cost = p_cost, note = nullif(trim(p_note),'')
     where d.id = p_id and (public.app_is_platform_admin(p_token) or d.tenant_id = ten)
     returning d.id into newid;
    if newid is null then return query select false,'Запись брака не найдена', null::uuid; return; end if;
  end if;
  perform public.app_notif_roles_t(ten, array['admin','owner','manager','chief','master','qc'], 'Производство: брак', left(ttl,180), 'apps/production/index.html');
  return query select true,'Брак зафиксирован', newid;
end $$;

create or replace function public.app_prod_defect_list(p_token uuid, p_naryad_id uuid default null)
returns table (id uuid, naryad_number text, operation text, title text, qty numeric, severity text, cause text, culprit_login text, cost numeric, status text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query
    select d.id, n.number, op.operation, d.title, d.qty, d.severity, d.cause, d.culprit_login, d.cost, d.status, d.created_at
      from public.app_defects d
      left join public.app_naryad_ops op on op.id = d.naryad_op_id
      left join public.app_naryads n on n.id = op.naryad_id
     where (adm or d.tenant_id = ten) and d.naryad_op_id is not null
       and (p_naryad_id is null or op.naryad_id = p_naryad_id)
     order by d.created_at desc;
end $$;

create or replace function public.app_prod_defect_kpi(p_token uuid)
returns table (total bigint, qty numeric, cost numeric, critical bigint, open_count bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query select
    (select count(*) from public.app_defects d where (adm or d.tenant_id=ten) and d.naryad_op_id is not null),
    (select coalesce(sum(d.qty),0) from public.app_defects d where (adm or d.tenant_id=ten) and d.naryad_op_id is not null),
    (select coalesce(sum(d.cost),0) from public.app_defects d where (adm or d.tenant_id=ten) and d.naryad_op_id is not null),
    (select count(*) from public.app_defects d where (adm or d.tenant_id=ten) and d.naryad_op_id is not null and d.severity='critical'),
    (select count(*) from public.app_defects d where (adm or d.tenant_id=ten) and d.naryad_op_id is not null and d.status='open');
end $$;

-- ================= RPC: сменно-суточное задание =================
create or replace function public.app_daily_job_build(p_token uuid, p_date date)
returns table (ok boolean, message text, created integer)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; uname text; cnt integer := 0; d date; rec record;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', 0; return; end if;
  if not public.app_can_edit(p_token, 'production') then return query select false,'Нет прав на производство', 0; return; end if;
  select u.tenant_id, s.ulogin into ten, uname from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  d := coalesce(p_date, current_date);
  for rec in
    select n.id as naryad_id, n.number, n.wc_id, n.assignee, op.id as op_id, op.operation, op.plan_hours, op.seq
      from public.app_naryads n join public.app_naryad_ops op on op.naryad_id = n.id
     where (public.app_is_platform_admin(p_token) or n.tenant_id = ten)
       and n.status <> 'closed' and not op.done
       and not exists (select 1 from public.app_daily_jobs j where j.job_date = d and j.op_id = op.id)
     order by n.number, op.seq
  loop
    insert into public.app_daily_jobs (tenant_id, job_date, wc_id, naryad_id, op_id, title, plan_hours, assignee, created_login)
    values (ten, d, rec.wc_id, rec.naryad_id, rec.op_id, rec.number || ' · ' || rec.operation, coalesce(rec.plan_hours,0), rec.assignee, uname);
    cnt := cnt + 1;
  end loop;
  return query select true, 'ССЗ на ' || to_char(d,'DD.MM.YYYY') || ': создано позиций ' || cnt, cnt;
end $$;

create or replace function public.app_daily_job_list(p_token uuid, p_date date default null)
returns table (id uuid, job_date date, naryad_number text, operation text, wc_id uuid, plan_hours numeric, assignee text, status text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid; d date;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  d := coalesce(p_date, current_date);
  return query
    select j.id, j.job_date, n.number, op.operation, j.wc_id, j.plan_hours, j.assignee, j.status
      from public.app_daily_jobs j
      left join public.app_naryads n on n.id = j.naryad_id
      left join public.app_naryad_ops op on op.id = j.op_id
     where (adm or j.tenant_id = ten) and j.job_date = d
     order by n.number, op.seq;
end $$;

create or replace function public.app_daily_job_set_status(p_token uuid, p_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; st text; n integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten := public.app_my_tenant(p_token);
  st := lower(trim(coalesce(p_status,'')));
  if st not in ('planned','in_work','done') then return query select false,'Недопустимый статус'; return; end if;
  update public.app_daily_jobs j set status = st where j.id = p_id and (public.app_is_platform_admin(p_token) or j.tenant_id = ten);
  get diagnostics n = row_count;
  if n = 0 then return query select false,'Позиция не найдена'; return; end if;
  return query select true,'Статус: ' || st;
end $$;

-- ================= RPC: маршрутная карта =================
create or replace function public.app_route_card(p_token uuid, p_naryad_id uuid)
returns table (seq integer, operation text, worker text, plan_hours numeric, fact_hours numeric, done boolean, started_at timestamptz, finished_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query
    select op.seq, op.operation, op.worker, op.plan_hours, op.fact_hours, op.done, op.started_at, op.finished_at
      from public.app_naryad_ops op join public.app_naryads n on n.id = op.naryad_id
     where op.naryad_id = p_naryad_id and (adm or n.tenant_id = ten)
     order by op.seq;
end $$;

-- ================= База знаний =================
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Производство','Производство 2.0: таймеры операций, брак, ССЗ, маршрутная карта (X10)',
   'Производство 2.0: таймер операций — app_op_start/app_op_stop (started_at/finished_at, авторасчёт fact_hours по факту), учёт брака/переделок — app_prod_defect_save/list/kpi (по операции: причина, виновник, количество, стоимость; запись в app_defects, уведомление), сменно-суточное задание — app_daily_job_build/list/set_status (формируется из открытых операций нарядов, app_daily_jobs), маршрутная карта — app_route_card (для печати). Связи: MES/терминал (real-time), ОТК (брак), экономика (стоимость брака), OEE (простои).',
   'производство таймер операция брак переделки ССЗ сменно-суточное задание маршрутная карта')
) as v(category,question,answer,tags)
where not exists (
  select 1 from public.app_knowledge
   where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001'
     and question = 'Производство 2.0: таймеры операций, брак, ССЗ, маршрутная карта (X10)'
);

-- ================= Права =================
grant execute on function public.app_op_start(uuid,uuid) to anon, authenticated;
grant execute on function public.app_op_stop(uuid,uuid) to anon, authenticated;
grant execute on function public.app_prod_defect_save(uuid,uuid,uuid,numeric,text,text,numeric,text,text) to anon, authenticated;
grant execute on function public.app_prod_defect_list(uuid,uuid) to anon, authenticated;
grant execute on function public.app_prod_defect_kpi(uuid) to anon, authenticated;
grant execute on function public.app_daily_job_build(uuid,date) to anon, authenticated;
grant execute on function public.app_daily_job_list(uuid,date) to anon, authenticated;
grant execute on function public.app_daily_job_set_status(uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_route_card(uuid,uuid) to anon, authenticated;
