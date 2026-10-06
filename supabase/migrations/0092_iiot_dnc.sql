-- ============================================================
-- 3DMP Service · 0092_iiot_dnc.sql  (v70 — Пункт 3: IIoT-телеметрия и DNC)
-- Приём телеметрии станков (метрики во времени) и очередь DNC-заданий
-- (передача УП на станок). Зависит от 0001..0091.
-- ============================================================

create table if not exists public.app_iiot_readings (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid references public.tenants (id),
  machine    text not null,
  metric     text not null default 'state',   -- state|count|speed|temp|power|vibration|other
  value      numeric not null default 0,
  source     text,
  ts         timestamptz not null default now()
);
create index if not exists app_iiot_readings_idx on public.app_iiot_readings (tenant_id, machine, ts desc);
alter table public.app_iiot_readings enable row level security;

create table if not exists public.app_dnc_jobs (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  machine       text not null,
  program_name  text not null,
  nc_id         uuid,
  status        text not null default 'queued', -- queued|sent|running|done|failed
  note          text,
  created_login text,
  created_at    timestamptz not null default now()
);
create index if not exists app_dnc_jobs_idx on public.app_dnc_jobs (tenant_id, status, created_at desc);
alter table public.app_dnc_jobs enable row level security;

create or replace function public.app_iiot_ingest(p_token uuid, p_machine text, p_metric text, p_value numeric)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  perform public.app_guard(p_token, 'production', 'edit');
  if coalesce(trim(p_machine),'')='' then raise exception 'Укажите станок'; return; end if;
  return query
    insert into public.app_iiot_readings (tenant_id, machine, metric, value, source)
    values (public.app_my_tenant(p_token), trim(p_machine), coalesce(nullif(trim(p_metric),''),'state'), coalesce(p_value,0), 'api')
    returning app_iiot_readings.id, 'Показание принято';
end $$;

create or replace function public.app_iiot_readings_list(p_token uuid, p_machine text default null, p_limit int default 50)
returns table (id uuid, machine text, metric text, value numeric, source text, ts timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select r.id, r.machine, r.metric, r.value, r.source, r.ts
    from public.app_iiot_readings r
    where (urole='admin' or r.tenant_id=ten) and (coalesce(p_machine,'')='' or r.machine=p_machine)
    order by r.ts desc limit greatest(1, least(coalesce(p_limit,50),500));
end $$;

create or replace function public.app_iiot_kpi(p_token uuid)
returns table (readings_today bigint, machines bigint, last_ts timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select
    (select count(*) from public.app_iiot_readings where (urole='admin' or tenant_id=ten) and ts >= date_trunc('day', now())),
    (select count(distinct machine) from public.app_iiot_readings where (urole='admin' or tenant_id=ten)),
    (select max(ts) from public.app_iiot_readings where (urole='admin' or tenant_id=ten));
end $$;

create or replace function public.app_dnc_list(p_token uuid, p_q text default null)
returns table (id uuid, machine text, program_name text, status text, note text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query select d.id, d.machine, d.program_name, d.status, d.note, d.created_at
    from public.app_dnc_jobs d
    where (urole='admin' or d.tenant_id=ten)
      and (qq='' or lower(d.program_name) like '%'||qq||'%' or lower(d.machine) like '%'||qq||'%')
    order by (d.status='done'), d.created_at desc;
end $$;

create or replace function public.app_dnc_save(p_token uuid, p_id uuid, p_machine text, p_program_name text, p_note text)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; ulogin text; did uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  perform public.app_guard(p_token, 'production', 'edit');
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_machine),'')='' or coalesce(trim(p_program_name),'')='' then raise exception 'Укажите станок и программу'; return; end if;
  if p_id is null then
    insert into public.app_dnc_jobs (tenant_id, machine, program_name, note, created_login)
    values (ten, trim(p_machine), trim(p_program_name), nullif(trim(p_note),''), ulogin) returning id into did;
    return query select did, 'Задание в очереди';
  else
    update public.app_dnc_jobs set machine=trim(p_machine), program_name=trim(p_program_name), note=nullif(trim(p_note),'')
     where id=p_id and (urole='admin' or tenant_id=ten) returning id into did;
    return query select did, 'Задание обновлено';
  end if;
end $$;

create or replace function public.app_dnc_set_status(p_token uuid, p_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  if not public.app_can(p_token,'production','edit') then return query select false,'Недостаточно прав'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if p_status not in ('queued','sent','running','done','failed') then return query select false,'Неверный статус'; return; end if;
  update public.app_dnc_jobs set status=p_status where id=p_id and (urole='admin' or tenant_id=ten);
  return query select true,'Статус обновлён';
end $$;

grant execute on function public.app_iiot_ingest(uuid,text,text,numeric) to anon, authenticated;
grant execute on function public.app_iiot_readings_list(uuid,text,int) to anon, authenticated;
grant execute on function public.app_iiot_kpi(uuid) to anon, authenticated;
grant execute on function public.app_dnc_list(uuid,text) to anon, authenticated;
grant execute on function public.app_dnc_save(uuid,uuid,text,text,text) to anon, authenticated;
grant execute on function public.app_dnc_set_status(uuid,uuid,text) to anon, authenticated;

-- ---------- Демо ----------
insert into public.app_iiot_readings (tenant_id, machine, metric, value)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.m, v.met, v.val
from (values ('Feeler FTC-350Xl','state',1),('Feeler FTC-350Xl','speed',4200),('ЭЭО проволочная','power',3.2)) as v(m,met,val)
where not exists (select 1 from public.app_iiot_readings where tenant_id='aaaaaaaa-0000-0000-0000-000000000001');
insert into public.app_dnc_jobs (tenant_id, machine, program_name, status, created_login)
select 'aaaaaaaa-0000-0000-0000-000000000001','Feeler FTC-350Xl','O1234_MILL.NC','queued','master'
where not exists (select 1 from public.app_dnc_jobs where tenant_id='aaaaaaaa-0000-0000-0000-000000000001');

insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Производство','IIoT-телеметрия и DNC (B13/B18)',
   'Модуль «IIoT и DNC»: приём телеметрии станков (метрики: состояние, счётчик, обороты, мощность, температура, вибрация) во времени и очередь DNC-заданий (передача УП на станок) со статусами queued→sent→running→done/failed. Основа онлайн-мониторинга и безбумажной передачи программ.',
   'IIoT телеметрия станки DNC NC мониторинг онлайн B13 B18')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='IIoT-телеметрия и DNC (B13/B18)');
