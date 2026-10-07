-- ============================================================
-- 3DMP Service · 0154_mes_aps_iiot.sql  (W9 — MES/APS/IIoT боевой)
-- APS-автопланирование (слоты↔загрузка↔сроки), IIoT-коннекторы и приём телеметрии,
-- OEE онлайн, авто-контроль стойкости инструмента по наработке.
-- Идемпотентно. Зависит от 0001..0153.
-- ============================================================

-- ---------- IIoT-коннекторы (OPC UA / MTConnect / Modbus / manual) ----------
create table if not exists public.app_iiot_connectors (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid references public.tenants (id),
  name         text not null,
  kind         text not null default 'manual',   -- opcua|mtconnect|modbus|manual
  endpoint     text,
  settings     jsonb not null default '{}'::jsonb,
  active       boolean not null default true,
  last_run     timestamptz,
  last_status  text,
  created_by   uuid references public.app_users (id) on delete set null,
  created_login text,
  created_at   timestamptz not null default now()
);
create index if not exists app_iiot_connectors_idx on public.app_iiot_connectors (tenant_id, active);
alter table public.app_iiot_connectors enable row level security;

create or replace function public.app_iiot_connectors_list(p_token uuid)
returns table (id uuid, name text, kind text, endpoint text, active boolean, last_run timestamptz, last_status text, settings jsonb)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token);
  ten := public.app_my_tenant(p_token);
  return query select c.id, c.name, c.kind, c.endpoint, c.active, c.last_run, c.last_status, c.settings
    from public.app_iiot_connectors c where adm or c.tenant_id = ten order by c.created_at desc;
end $$;

create or replace function public.app_iiot_connector_save(p_token uuid, p_id uuid, p_name text, p_kind text,
  p_endpoint text, p_settings jsonb, p_active boolean)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; uname text; newid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid; return; end if;
  select u.tenant_id, s.ulogin into ten, uname from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  if coalesce(trim(p_name),'') = '' then return query select false,'Укажите название', null::uuid; return; end if;
  if coalesce(trim(p_kind),'manual') not in ('opcua','mtconnect','modbus','manual') then
    return query select false,'Недопустимый тип коннектора', null::uuid; return;
  end if;
  if p_id is null then
    insert into public.app_iiot_connectors (tenant_id,name,kind,endpoint,settings,active,created_by,created_login)
    values (ten, left(trim(p_name),120), coalesce(nullif(trim(p_kind),''),'manual'), nullif(trim(p_endpoint),''),
            coalesce(p_settings,'{}'::jsonb), coalesce(p_active,true),
            (select s.uid from public.app_session_user(p_token) s), uname)
    returning app_iiot_connectors.id into newid;
    return query select true,'Коннектор создан', newid;
  else
    update public.app_iiot_connectors c
       set name = left(trim(p_name),120), kind = coalesce(nullif(trim(p_kind),''),c.kind),
           endpoint = nullif(trim(p_endpoint),''), settings = coalesce(p_settings,c.settings), active = coalesce(p_active,c.active)
     where c.id = p_id and (public.app_is_platform_admin(p_token) or c.tenant_id = ten)
     returning c.id into newid;
    if newid is null then return query select false,'Коннектор не найден', null::uuid; return; end if;
    return query select true,'Коннектор обновлён', newid;
  end if;
end $$;

create or replace function public.app_iiot_connector_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; n integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten := public.app_my_tenant(p_token);
  delete from public.app_iiot_connectors c where c.id = p_id and (public.app_is_platform_admin(p_token) or c.tenant_id = ten);
  get diagnostics n = row_count;
  if n = 0 then return query select false,'Коннектор не найден'; return; end if;
  return query select true,'Коннектор удалён';
end $$;

-- Проверка/запуск коннектора: реальный опрос выполняет внешний воркер (backend-example),
-- здесь фиксируется попытка запуска и, при наличии integration_id в settings, ставится в очередь обмена.
create or replace function public.app_iiot_connector_run(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; k text; iid uuid; s jsonb;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten := public.app_my_tenant(p_token);
  select c.kind, c.settings into k, s from public.app_iiot_connectors c
   where c.id = p_id and (public.app_is_platform_admin(p_token) or c.tenant_id = ten);
  if not found then return query select false,'Коннектор не найден'; return; end if;
  iid := null;
  begin iid := (s->>'integration_id')::uuid; exception when others then iid := null; end;
  if iid is not null then
    perform public.app_integration_enqueue(p_token, iid, 'out', jsonb_build_object('kind',k,'op','poll'));
  end if;
  update public.app_iiot_connectors c set last_run = now(), last_status = 'ok' where c.id = p_id;
  return query select true, 'Коннектор запущен' || (case when iid is not null then ' (поставлен в очередь обмена)' else ' (опрос выполнит воркер)' end);
end $$;

-- Приём телеметрии (endpoint для внешнего воркера/Edge).
-- ВАЖНО: заменяем старую 4-аргументную сигнатуру (0092), чтобы не было перегрузки.
drop function if exists public.app_iiot_ingest(uuid,text,text,numeric);
create or replace function public.app_iiot_ingest(p_token uuid, p_machine text, p_metric text, p_value numeric, p_source text default null)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; m text; upd integer := 0;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  perform public.app_guard(p_token, 'production', 'edit');
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_machine),'') = '' or coalesce(trim(p_metric),'') = '' then
    return query select false,'Укажите станок и метрику'; return;
  end if;
  insert into public.app_iiot_readings (tenant_id, machine, metric, value, source, ts)
  values (ten, left(trim(p_machine),120), left(trim(p_metric),60), p_value, nullif(trim(coalesce(p_source,'')),''), now());

  -- Авто-контроль стойкости инструмента по наработке.
  if lower(trim(p_metric)) in ('runtime_min','runtime','наработка','wear_min') and p_value is not null then
    update public.app_tool_life t
       set used_min = coalesce(t.used_min,0) + p_value,
           status = case
             when coalesce(t.max_wears,0) > 0 and coalesce(t.wears,0) >= t.max_wears then 'worn'
             when coalesce(t.resource_min,0) > 0 and coalesce(t.used_min,0) + p_value >= t.resource_min then 'worn'
             else 'ok' end
     where t.tenant_id = ten
       and t.equipment_id in (select e.id from public.app_equipment e where e.tenant_id = ten and (e.name = p_machine or e.code = p_machine));
    get diagnostics upd = row_count;
  end if;
  return query select true, 'Принято: ' || trim(p_machine) || ' / ' || trim(p_metric) || (case when upd > 0 then ' (обновлён износ инструмента: ' || upd || ')' else '' end);
end $$;

create or replace function public.app_iiot_readings_recent(p_token uuid, p_limit integer default 50)
returns table (machine text, metric text, value numeric, source text, ts timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token);
  ten := public.app_my_tenant(p_token);
  return query select r.machine, r.metric, r.value, r.source, r.ts
    from public.app_iiot_readings r where (adm or r.tenant_id = ten) order by r.ts desc limit greatest(coalesce(p_limit,50),1);
end $$;

-- ---------- APS: автопланирование ----------
create or replace function public.app_aps_build(p_token uuid, p_from date, p_days integer)
returns table (number text, title text, priority text, remaining numeric, plan_start date, plan_end date,
               days integer, due_date date, risk text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare
  ten uuid; adm boolean; v_from date; v_days int; i int; v_take numeric; rem numeric; v_cap numeric;
  cap numeric[]; used numeric[]; rec record; v_start date; v_end date;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token);
  ten := public.app_my_tenant(p_token);
  v_from := coalesce(p_from, current_date);
  v_days := greatest(least(coalesce(p_days,14),60),1);
  cap := array_fill(0::numeric, array[v_days]);
  used := array_fill(0::numeric, array[v_days]);
  for i in 1..v_days loop
    v_cap := 0;
    select coalesce(sum(greatest(capacity_hours - least(used_hours, capacity_hours),0)),0) into v_cap
      from public.app_work_slots w
     where (adm or w.tenant_id = ten) and w.slot_date = v_from + (i-1);
    cap[i] := coalesce(v_cap, 0);
    if cap[i] = 0 then cap[i] := 8; end if;
  end loop;

  for rec in
    select n.number, n.title, n.priority, coalesce(n.plan_hours,0) as plan_hours, coalesce(n.fact_hours,0) as fact_hours,
           n.due_date, n.created_at
      from public.app_naryads n
     where (adm or n.tenant_id = ten) and n.status in ('open','in_progress','paused','queue')
     order by case lower(coalesce(n.priority,'normal')) when 'critical' then 0 when 'high' then 1 when 'normal' then 2 when 'low' then 3 else 4 end,
              n.due_date nulls last, n.created_at
  loop
    rem := greatest(rec.plan_hours - rec.fact_hours, 0);
    if rem <= 0 then
      return query select rec.number, rec.title, rec.priority, rem, null::date, null::date, null::int, rec.due_date, 'норма'::text;
      continue;
    end if;
    v_start := null; v_end := null; i := 1;
    while rem > 0 and i <= v_days loop
      if used[i] < cap[i] then
        if v_start is null then v_start := v_from + (i-1); end if;
        v_take := least(rem, cap[i] - used[i]);
        used[i] := used[i] + v_take; rem := rem - v_take; v_end := v_from + (i-1);
      end if;
      i := i + 1;
    end loop;
    return query select rec.number, rec.title, rec.priority,
      greatest(rec.plan_hours - rec.fact_hours, 0), v_start, v_end,
      (case when v_start is null then null else (v_end - v_start + 1) end)::int, rec.due_date,
      case when rec.due_date is null then '—'
           when v_end is not null and v_end > rec.due_date then 'риск'
           else 'норма' end;
  end loop;
end $$;

create or replace function public.app_aps_plan(p_token uuid, p_from date default current_date, p_days integer default 14)
returns table (number text, title text, priority text, remaining numeric, plan_start date, plan_end date,
               days integer, due_date date, risk text)
language plpgsql security definer set search_path = public
as $$
begin
  return query select * from public.app_aps_build(p_token, p_from, p_days);
end $$;

create or replace function public.app_aps_apply(p_token uuid, p_from date default current_date, p_days integer default 14)
returns table (updated integer, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean; cnt integer := 0; rec record;
begin
  if not public.app_production_allowed(p_token) then return query select 0,'Доступ запрещён'; return; end if;
  adm := public.app_is_platform_admin(p_token);
  ten := public.app_my_tenant(p_token);
  for rec in select * from public.app_aps_build(p_token, p_from, p_days) loop
    if rec.plan_start is not null then
      update public.app_naryads n set plan_start = rec.plan_start, plan_end = rec.plan_end
       where n.number = rec.number and (adm or n.tenant_id = ten) and n.status in ('open','in_progress','paused','queue');
      cnt := cnt + 1;
    end if;
  end loop;
  return query select cnt, 'План применён: нарядов — ' || cnt;
end $$;

create or replace function public.app_aps_load(p_token uuid, p_from date default current_date, p_days integer default 14)
returns table (day date, capacity numeric, load numeric, load_pct numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare
  ten uuid; adm boolean; v_from date; v_days int; i int; v_cap numeric; v_take numeric; rem numeric;
  cap numeric[]; used numeric[]; rec record;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token);
  ten := public.app_my_tenant(p_token);
  v_from := coalesce(p_from, current_date);
  v_days := greatest(least(coalesce(p_days,14),60),1);
  cap := array_fill(0::numeric, array[v_days]);
  used := array_fill(0::numeric, array[v_days]);
  for i in 1..v_days loop
    v_cap := 0;
    select coalesce(sum(greatest(capacity_hours - least(used_hours,capacity_hours),0)),0) into v_cap
      from public.app_work_slots w where (adm or w.tenant_id=ten) and w.slot_date = v_from + (i-1);
    cap[i] := coalesce(v_cap,0);
    if cap[i] = 0 then cap[i] := 8; end if;
  end loop;
  for rec in
    select coalesce(n.plan_hours,0) as plan_hours, coalesce(n.fact_hours,0) as fact_hours
      from public.app_naryads n
     where (adm or n.tenant_id=ten) and n.status in ('open','in_progress','paused','queue')
     order by case lower(coalesce(n.priority,'normal')) when 'critical' then 0 when 'high' then 1 when 'normal' then 2 when 'low' then 3 else 4 end,
              n.due_date nulls last, n.created_at
  loop
    rem := greatest(rec.plan_hours - rec.fact_hours, 0);
    i := 1;
    while rem > 0 and i <= v_days loop
      if used[i] < cap[i] then
        v_take := least(rem, cap[i] - used[i]);
        used[i] := used[i] + v_take; rem := rem - v_take;
      end if;
      i := i + 1;
    end loop;
  end loop;
  for i in 1..v_days loop
    return query select (v_from + (i-1))::date, cap[i], used[i], round(used[i] / cap[i] * 100, 1);
  end loop;
end $$;

-- ---------- OEE онлайн ----------
create or replace function public.app_oee_online(p_token uuid)
returns table (equipment text, shift_date date, planned_min numeric, run_min numeric, downtime_min numeric,
               good_qty numeric, total_qty numeric, availability numeric, quality numeric, oee numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token);
  ten := public.app_my_tenant(p_token);
  return query
    select coalesce(e.name, 'Оборудование') as equipment, o.shift_date, o.planned_min, o.run_min, o.downtime_min,
           o.good_qty, o.total_qty,
           round(o.run_min / nullif(o.planned_min,0) * 100, 1),
           round(o.good_qty / nullif(o.total_qty,0) * 100, 1),
           round((o.run_min / nullif(o.planned_min,0)) * (o.good_qty / nullif(o.total_qty,0)) * 100, 1)
      from (select distinct on (equipment_id) * from public.app_oee_log l
             where (adm or l.tenant_id = ten) order by equipment_id, shift_date desc, created_at desc) o
      left join public.app_equipment e on e.id = o.equipment_id
     order by equipment;
end $$;

-- ---------- Контроль стойкости инструмента ----------
create or replace function public.app_tool_wear_scan(p_token uuid, p_limit integer default 100)
returns table (code text, name text, tool_type text, used_min numeric, resource_min numeric, wears integer,
               max_wears integer, pct numeric, status text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token);
  ten := public.app_my_tenant(p_token);
  return query
    select t.code, t.name, t.tool_type, coalesce(t.used_min,0), t.resource_min, t.wears, t.max_wears,
           case when coalesce(t.resource_min,0) > 0 then round(coalesce(t.used_min,0)/t.resource_min*100,1) else null end,
           case
             when coalesce(t.max_wears,0) > 0 and coalesce(t.wears,0) >= t.max_wears then 'worn'
             when coalesce(t.resource_min,0) > 0 and coalesce(t.used_min,0) >= t.resource_min then 'worn'
             when coalesce(t.resource_min,0) > 0 and coalesce(t.used_min,0) >= t.resource_min*0.85 then 'due'
             else coalesce(t.status,'ok') end
      from public.app_tool_life t
     where adm or t.tenant_id = ten
     order by (case when coalesce(t.resource_min,0) > 0 then coalesce(t.used_min,0)/t.resource_min else 0 end) desc
     limit greatest(coalesce(p_limit,100),1);
end $$;

-- ---------- Демо: коннектор ----------
insert into public.app_iiot_connectors (tenant_id, name, kind, endpoint, settings, active, created_login)
select 'aaaaaaaa-0000-0000-0000-000000000001', 'Станок DMU-50 (OPC UA)', 'opcua', 'opc.tcp://10.0.0.21:4840', '{"machine":"Станок-1","poll_sec":5}'::jsonb, true, 'owner'
where not exists (select 1 from public.app_iiot_connectors where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and name='Станок DMU-50 (OPC UA)');

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Производство','MES/APS/IIoT боевой: автоплан, коннекторы, OEE онлайн, стойкость',
   'W9: APS-автопланирование (app_aps_plan/apply/load) распределяет открытые наряды по слотам с учётом мощности и сроков (Спрос↔Загрузка↔Сроки, риск просрочки); IIoT-коннекторы (app_iiot_connectors: OPC UA/MTConnect/Modbus/manual) с приёмом телеметрии (app_iiot_ingest → app_iiot_readings; реальный опрос — внешний воркер backend-example); OEE онлайн (app_oee_online по последней смене на оборудование); контроль стойкости инструмента (app_iiot_ingest обновляет used_min → app_tool_wear_scan). Модули «Планирование», «IIoT», «OEE», «Инструмент».',
   'APS автопланирование слоты загрузка сроки IIoT OPC UA MTConnect OEE онлайн стойкость инструмент наработка')
) as v(category,question,answer,tags)
where not exists (
  select 1 from public.app_knowledge
   where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001' and question = 'MES/APS/IIoT боевой: автоплан, коннекторы, OEE онлайн, стойкость'
);

-- ---------- Права ----------
grant execute on function public.app_iiot_connectors_list(uuid) to anon, authenticated;
grant execute on function public.app_iiot_connector_save(uuid,uuid,text,text,text,jsonb,boolean) to anon, authenticated;
grant execute on function public.app_iiot_connector_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_iiot_connector_run(uuid,uuid) to anon, authenticated;
grant execute on function public.app_iiot_ingest(uuid,text,text,numeric,text) to anon, authenticated;
grant execute on function public.app_iiot_readings_recent(uuid,integer) to anon, authenticated;
grant execute on function public.app_aps_build(uuid,date,integer) to anon, authenticated;
grant execute on function public.app_aps_plan(uuid,date,integer) to anon, authenticated;
grant execute on function public.app_aps_apply(uuid,date,integer) to anon, authenticated;
grant execute on function public.app_aps_load(uuid,date,integer) to anon, authenticated;
grant execute on function public.app_oee_online(uuid) to anon, authenticated;
grant execute on function public.app_tool_wear_scan(uuid,integer) to anon, authenticated;
