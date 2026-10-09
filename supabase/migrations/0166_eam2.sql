-- ============================================================
-- 3DMP Service · 0166_eam2.sql  (W14 — CMMS/EAM 2.0)
-- Вибродиагностика (+авто-наряд), энергоменеджмент, простои/дисциплина,
-- версии УП (сверка), 3D-карта цеха. Идемпотентно. Зависит от 0001..0165.
-- ============================================================

create table if not exists public.app_vibro_limits (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid references public.tenants (id),
  equipment_id uuid references public.app_equipment (id) on delete cascade,
  warn         numeric not null default 4.5,
  alarm        numeric not null default 7.1,
  created_at   timestamptz not null default now()
);
alter table public.app_vibro_limits enable row level security;

create table if not exists public.app_vibro_readings (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid references public.tenants (id),
  equipment_id uuid references public.app_equipment (id) on delete set null,
  value        numeric not null default 0,
  unit         text default 'мм/с',
  result       text not null default 'ok',   -- ok|warn|alarm
  ts           timestamptz not null default now()
);
create index if not exists app_vibro_idx on public.app_vibro_readings (tenant_id, equipment_id, ts desc);
alter table public.app_vibro_readings enable row level security;

create table if not exists public.app_energy_readings (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid references public.tenants (id),
  resource     text not null default 'el',   -- el|gas|water|air
  value        numeric not null default 0,
  unit         text,
  cost         numeric not null default 0,
  period_date  date not null default current_date,
  note         text,
  created_at   timestamptz not null default now()
);
create index if not exists app_energy_idx on public.app_energy_readings (tenant_id, resource, period_date desc);
alter table public.app_energy_readings enable row level security;

create table if not exists public.app_downtime_reasons (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid references public.tenants (id),
  code       text,
  name       text not null,
  created_at timestamptz not null default now()
);
alter table public.app_downtime_reasons enable row level security;

create table if not exists public.app_operator_log (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid references public.tenants (id),
  login      text,
  machine    text,
  event      text not null default 'in',   -- in|out
  reason_id  uuid references public.app_downtime_reasons (id) on delete set null,
  ts         timestamptz not null default now()
);
create index if not exists app_operator_log_idx on public.app_operator_log (tenant_id, login, ts desc);
alter table public.app_operator_log enable row level security;

create table if not exists public.app_nc_versions (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  program       text not null,
  machine       text,
  version       integer not null default 1,
  hash          text,
  kind          text not null default 'base',   -- base|actual
  note          text,
  created_login text,
  created_at    timestamptz not null default now()
);
create index if not exists app_nc_versions_idx on public.app_nc_versions (tenant_id, program, kind, created_at desc);
alter table public.app_nc_versions enable row level security;

create table if not exists public.app_layouts (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid references public.tenants (id),
  machine    text not null,
  x          numeric not null default 0,
  y          numeric not null default 0,
  w          numeric not null default 8,
  h          numeric not null default 6,
  status     text default 'idle',
  created_at timestamptz not null default now()
);
alter table public.app_layouts enable row level security;

-- ---------- RPC: вибрация ----------
create or replace function public.app_vibro_limits_list(p_token uuid)
returns table (id uuid, equipment text, equipment_id uuid, warn numeric, alarm numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query select l.id, e.name, l.equipment_id, l.warn, l.alarm
    from public.app_vibro_limits l left join public.app_equipment e on e.id = l.equipment_id
   where adm or l.tenant_id = ten order by e.name;
end $$;

create or replace function public.app_vibro_limit_save(p_token uuid, p_id uuid, p_equipment_id uuid, p_warn numeric, p_alarm numeric)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; newid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid; return; end if;
  select u.tenant_id into ten from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  if p_id is null then
    insert into public.app_vibro_limits (tenant_id, equipment_id, warn, alarm) values (ten, p_equipment_id, coalesce(p_warn,4.5), coalesce(p_alarm,7.1))
    returning app_vibro_limits.id into newid;
    return query select true,'Порог задан', newid;
  else
    update public.app_vibro_limits l set equipment_id = coalesce(p_equipment_id, l.equipment_id), warn = coalesce(p_warn, l.warn), alarm = coalesce(p_alarm, l.alarm)
     where l.id = p_id and (public.app_is_platform_admin(p_token) or l.tenant_id = ten) returning l.id into newid;
    if newid is null then return query select false,'Порог не найден', null::uuid; return; end if;
    return query select true,'Порог сохранён', newid;
  end if;
end $$;

create or replace function public.app_vibro_add(p_token uuid, p_equipment_id uuid, p_value numeric, p_unit text)
returns table (ok boolean, message text, result text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; warn numeric; alarm numeric; res text; ename text; newtask uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::text; return; end if;
  ten := public.app_my_tenant(p_token);
  select l.warn, l.alarm into warn, alarm from public.app_vibro_limits l where l.equipment_id = p_equipment_id and (public.app_is_platform_admin(p_token) or l.tenant_id = ten) limit 1;
  warn := coalesce(warn,4.5); alarm := coalesce(alarm,7.1);
  res := case when p_value >= alarm then 'alarm' when p_value >= warn then 'warn' else 'ok' end;
  insert into public.app_vibro_readings (tenant_id, equipment_id, value, unit, result) values (ten, p_equipment_id, coalesce(p_value,0), nullif(trim(p_unit),''), res);
  if res = 'alarm' then
    select name into ename from public.app_equipment where id = p_equipment_id;
    insert into public.app_tasks (tenant_id, title, status, priority, entity_type, entity_id, created_login)
    values (ten, 'ТОиР: вибрация «' || coalesce(ename,'оборудование') || '» ' || p_value || ' мм/с', 'todo', 'high', 'equipment', p_equipment_id, 'vibro')
    returning id into newtask;
    perform public.app_notif_roles_t(ten, array['master','chief'], 'Аварийная вибрация', coalesce(ename,'') || ' — ' || p_value, 'apps/eam/index.html');
  end if;
  return query select true, 'Показание: ' || res, res;
end $$;

create or replace function public.app_vibro_board(p_token uuid)
returns table (equipment text, value numeric, result text, ts timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query
    select e.name, r.value, r.result, r.ts
      from (select distinct on (equipment_id) equipment_id, value, result, ts from public.app_vibro_readings where adm or tenant_id=ten order by equipment_id, ts desc) r
      join public.app_equipment e on e.id = r.equipment_id
     order by (case r.result when 'alarm' then 0 when 'warn' then 1 else 2 end), e.name;
end $$;

-- ---------- RPC: энергия ----------
create or replace function public.app_energy_add(p_token uuid, p_resource text, p_value numeric, p_unit text, p_cost numeric, p_period date)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; r text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten := public.app_my_tenant(p_token);
  r := coalesce(nullif(trim(p_resource),''),'el');
  if r not in ('el','gas','water','air') then return query select false,'Ресурс: el/gas/water/air'; return; end if;
  insert into public.app_energy_readings (tenant_id, resource, value, unit, cost, period_date) values (ten, r, coalesce(p_value,0), nullif(trim(p_unit),''), coalesce(p_cost,0), coalesce(p_period, current_date));
  return query select true,'Показание энергии добавлено';
end $$;

create or replace function public.app_energy_kpi(p_token uuid, p_from date default null, p_to date default null)
returns table (resource text, amount numeric, cost numeric, unit text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean; d1 date; d2 date;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  d1 := coalesce(p_from, (date_trunc('month', current_date))::date); d2 := coalesce(p_to, current_date);
  return query
    select er.resource, sum(er.value), sum(er.cost), max(er.unit)
      from public.app_energy_readings er
     where (adm or er.tenant_id = ten) and er.period_date between d1 and d2
     group by er.resource order by er.resource;
end $$;

-- ---------- RPC: простои/дисциплина ----------
create or replace function public.app_downtime_reasons_list(p_token uuid)
returns table (id uuid, code text, name text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query select r.id, r.code, r.name from public.app_downtime_reasons r where adm or r.tenant_id = ten order by r.code;
end $$;

create or replace function public.app_downtime_reason_save(p_token uuid, p_id uuid, p_code text, p_name text)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; newid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid; return; end if;
  select u.tenant_id into ten from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  if coalesce(trim(p_name),'') = '' then return query select false,'Укажите название причины', null::uuid; return; end if;
  if p_id is null then
    insert into public.app_downtime_reasons (tenant_id, code, name) values (ten, nullif(trim(p_code),''), left(trim(p_name),160)) returning id into newid;
    return query select true,'Причина добавлена', newid;
  else
    update public.app_downtime_reasons r set code = nullif(trim(p_code),''), name = left(trim(p_name),160)
     where r.id = p_id and (public.app_is_platform_admin(p_token) or r.tenant_id = ten) returning r.id into newid;
    if newid is null then return query select false,'Причина не найдена', null::uuid; return; end if;
    return query select true,'Причина сохранена', newid;
  end if;
end $$;

create or replace function public.app_operator_log_add(p_token uuid, p_login text, p_machine text, p_event text, p_reason_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; ev text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten := public.app_my_tenant(p_token);
  ev := lower(trim(coalesce(p_event,'')));
  if ev not in ('in','out') then return query select false,'Событие: in/out'; return; end if;
  if coalesce(trim(p_login),'') = '' then return query select false,'Укажите сотрудника'; return; end if;
  insert into public.app_operator_log (tenant_id, login, machine, event, reason_id) values (ten, trim(p_login), nullif(trim(p_machine),''), ev, p_reason_id);
  return query select true,'Событие зафиксировано';
end $$;

create or replace function public.app_operator_log_list(p_token uuid, p_login text default null, p_limit integer default 100)
returns table (id uuid, login text, machine text, event text, reason text, ts timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query
    select l.id, l.login, l.machine, l.event, r.name, l.ts
      from public.app_operator_log l left join public.app_downtime_reasons r on r.id = l.reason_id
     where (adm or l.tenant_id = ten) and (p_login is null or p_login='' or l.login = p_login)
     order by l.ts desc limit greatest(coalesce(p_limit,100),1);
end $$;

-- ---------- RPC: версии УП ----------
create or replace function public.app_nc_version_add(p_token uuid, p_program text, p_machine text, p_hash text, p_kind text, p_note text)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; uname text; newid uuid; k text; v integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid; return; end if;
  select u.tenant_id, s.ulogin into ten, uname from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  if coalesce(trim(p_program),'') = '' then return query select false,'Укажите программу', null::uuid; return; end if;
  k := coalesce(nullif(trim(p_kind),''),'base');
  if k not in ('base','actual') then return query select false,'Вид: base/actual', null::uuid; return; end if;
  select coalesce(max(v.version),0)+1 into v from public.app_nc_versions v where v.tenant_id = ten and lower(v.program)=lower(trim(p_program)) and v.kind = k;
  insert into public.app_nc_versions (tenant_id, program, machine, version, hash, kind, note, created_login)
  values (ten, left(trim(p_program),160), nullif(trim(p_machine),''), v, nullif(trim(p_hash),''), k, nullif(trim(p_note),''), uname)
  returning app_nc_versions.id into newid;
  return query select true, 'Версия ' || k || ' v' || v || ' сохранена', newid;
end $$;

create or replace function public.app_nc_versions_compare(p_token uuid)
returns table (program text, base_version integer, actual_version integer, match boolean, base_hash text, actual_hash text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query
    select p.program,
           (select v.version from public.app_nc_versions v where lower(v.program)=lower(p.program) and v.kind='base' and (adm or v.tenant_id=ten) order by v.version desc limit 1),
           (select v.version from public.app_nc_versions v where lower(v.program)=lower(p.program) and v.kind='actual' and (adm or v.tenant_id=ten) order by v.version desc limit 1),
           (select v.hash from public.app_nc_versions v where lower(v.program)=lower(p.program) and v.kind='base' and (adm or v.tenant_id=ten) order by v.version desc limit 1)
             is not distinct from
             (select v.hash from public.app_nc_versions v where lower(v.program)=lower(p.program) and v.kind='actual' and (adm or v.tenant_id=ten) order by v.version desc limit 1),
           (select v.hash from public.app_nc_versions v where lower(v.program)=lower(p.program) and v.kind='base' and (adm or v.tenant_id=ten) order by v.version desc limit 1),
           (select v.hash from public.app_nc_versions v where lower(v.program)=lower(p.program) and v.kind='actual' and (adm or v.tenant_id=ten) order by v.version desc limit 1)
      from (select distinct program from public.app_nc_versions v where adm or v.tenant_id=ten) p
     order by p.program;
end $$;

-- ---------- RPC: 3D-карта ----------
create or replace function public.app_layout_list(p_token uuid)
returns table (id uuid, machine text, x numeric, y numeric, w numeric, h numeric, status text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query select a.id, a.machine, a.x, a.y, a.w, a.h, a.status from public.app_layouts a where adm or a.tenant_id = ten order by a.machine;
end $$;

create or replace function public.app_layout_save(p_token uuid, p_id uuid, p_machine text, p_x numeric, p_y numeric, p_w numeric, p_h numeric, p_status text)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; newid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid; return; end if;
  select u.tenant_id into ten from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  if coalesce(trim(p_machine),'') = '' then return query select false,'Укажите станок', null::uuid; return; end if;
  if p_id is null then
    insert into public.app_layouts (tenant_id, machine, x, y, w, h, status) values (ten, left(trim(p_machine),120), coalesce(p_x,0), coalesce(p_y,0), coalesce(p_w,8), coalesce(p_h,6), coalesce(p_status,'idle'))
    returning id into newid;
    return query select true,'Машина размещена', newid;
  else
    update public.app_layouts a set machine = left(trim(p_machine),120), x = coalesce(p_x,a.x), y = coalesce(p_y,a.y), w = coalesce(p_w,a.w), h = coalesce(p_h,a.h), status = coalesce(p_status,a.status)
     where a.id = p_id and (public.app_is_platform_admin(p_token) or a.tenant_id = ten) returning a.id into newid;
    if newid is null then return query select false,'Машина не найдена', null::uuid; return; end if;
    return query select true,'Машина сохранена', newid;
  end if;
end $$;

create or replace function public.app_eam_kpi(p_token uuid)
returns table (vibro_alarms bigint, energy_month numeric, energy_cost_month numeric, shifts_open bigint, nc_mismatch bigint, machines bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query select
    (select count(*) from (select distinct on (equipment_id) equipment_id, result from public.app_vibro_readings where (adm or tenant_id=ten) order by equipment_id, ts desc) r where r.result='alarm'),
    (select coalesce(sum(value),0) from public.app_energy_readings er where (adm or er.tenant_id=ten) and er.period_date >= date_trunc('month', current_date)::date),
    (select coalesce(sum(cost),0) from public.app_energy_readings er where (adm or er.tenant_id=ten) and er.period_date >= date_trunc('month', current_date)::date),
    (select count(*) from public.app_operator_log l where (adm or l.tenant_id=ten) and l.event='in' and l.ts::date = current_date
       and not exists (select 1 from public.app_operator_log o where o.tenant_id = l.tenant_id and o.login = l.login and o.event='out' and o.ts > l.ts)),
    (select count(*) from public.app_nc_versions_compare(p_token) c where not c.match),
    (select count(*) from public.app_layouts a where adm or a.tenant_id=ten);
end $$;

-- ================= Демо =================
insert into public.app_layouts (tenant_id, machine, x, y, w, h, status)
select 'aaaaaaaa-0000-0000-0000-000000000001', e.name, (row_number() over (order by e.name) - 1) * 12, 0, 10, 8, 'idle'
from public.app_equipment e
where e.tenant_id='aaaaaaaa-0000-0000-0000-000000000001'
  and not exists (select 1 from public.app_layouts where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and machine = e.name);

insert into public.app_downtime_reasons (tenant_id, code, name)
select 'aaaaaaaa-0000-0000-0000-000000000001', 'NO_MAT', 'Ожидание материала'
where not exists (select 1 from public.app_downtime_reasons where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and code='NO_MAT');

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags, section)
select 'aaaaaaaa-0000-0000-0000-000000000001', 'Производство', 'CMMS/EAM 2.0: вибрация, энергия, простои, версии УП, карта цеха',
       'W14: вибродиагностика (app_vibro_limits/app_vibro_readings; app_vibro_add при alarm создаёт наряд ТОиР и уведомляет master/chief; board), энергоменеджмент (app_energy_readings, app_energy_kpi), простои/дисциплина (app_downtime_reasons, app_operator_log in/out), версии УП (app_nc_versions base/actual + сверка app_nc_versions_compare), 3D-карта цеха (app_layouts), KPI (app_eam_kpi). Модуль «EAM 2.0» (apps/eam).',
       'CMMS EAM вибрация энергия простои дисциплина версии УП карта цеха', 'Производство'
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='CMMS/EAM 2.0: вибрация, энергия, простои, версии УП, карта цеха');

-- ---------- Права ----------
grant execute on function public.app_vibro_limits_list(uuid) to anon, authenticated;
grant execute on function public.app_vibro_limit_save(uuid,uuid,uuid,numeric,numeric) to anon, authenticated;
grant execute on function public.app_vibro_add(uuid,uuid,numeric,text) to anon, authenticated;
grant execute on function public.app_vibro_board(uuid) to anon, authenticated;
grant execute on function public.app_energy_add(uuid,text,numeric,text,numeric,date) to anon, authenticated;
grant execute on function public.app_energy_kpi(uuid,date,date) to anon, authenticated;
grant execute on function public.app_downtime_reasons_list(uuid) to anon, authenticated;
grant execute on function public.app_downtime_reason_save(uuid,uuid,text,text) to anon, authenticated;
grant execute on function public.app_operator_log_add(uuid,text,text,text,uuid) to anon, authenticated;
grant execute on function public.app_operator_log_list(uuid,text,integer) to anon, authenticated;
grant execute on function public.app_nc_version_add(uuid,text,text,text,text,text) to anon, authenticated;
grant execute on function public.app_nc_versions_compare(uuid) to anon, authenticated;
grant execute on function public.app_layout_list(uuid) to anon, authenticated;
grant execute on function public.app_layout_save(uuid,uuid,text,numeric,numeric,numeric,numeric,text) to anon, authenticated;
grant execute on function public.app_eam_kpi(uuid) to anon, authenticated;
