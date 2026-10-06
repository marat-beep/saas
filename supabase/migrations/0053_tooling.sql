-- ============================================================
-- 3DMP Service · 0053_tooling.sql  (v33.0 — прототипы B13/B19 → «Инструмент и стойкость»)
-- Учёт режущего инструмента: ресурс/наработка, заточки, износ, связь с оборудованием.
-- База знаний. Зависит от 0001..0052.
-- ============================================================

create table if not exists public.app_tool_life (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  code          text,
  name          text not null,
  tool_type     text,
  material      text,
  coating       text,
  diameter      numeric,
  equipment_id  uuid references public.app_equipment (id) on delete set null,
  resource_min  numeric default 0,     -- ресурс (стойкость), минут
  used_min      numeric default 0,      -- текущая наработка
  wears         integer default 0,      -- число заточек
  max_wears     integer default 3,      -- допустимое число заточек
  status        text not null default 'ok', -- ok|worn|scrapped
  location      text,
  note          text,
  created_at    timestamptz not null default now()
);
create index if not exists app_tool_life_idx on public.app_tool_life (tenant_id, status);
alter table public.app_tool_life enable row level security;

-- ---------- KPI ----------
create or replace function public.app_tool_kpi(p_token uuid)
returns table (tools_total bigint, worn bigint, scrapped bigint, avg_life numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select
    (select count(*) from public.app_tool_life t where (urole='admin' or t.tenant_id=ten) and t.status<>'scrapped'),
    (select count(*) from public.app_tool_life t where (urole='admin' or t.tenant_id=ten) and t.status='worn'),
    (select count(*) from public.app_tool_life t where (urole='admin' or t.tenant_id=ten) and t.status='scrapped'),
    (select coalesce(round(avg(case when t.resource_min>0 then t.used_min/t.resource_min*100 else 0 end),1),0)
       from public.app_tool_life t where (urole='admin' or t.tenant_id=ten) and t.status<>'scrapped');
end $$;

-- ---------- Список ----------
create or replace function public.app_tool_life_list(p_token uuid, p_q text default null)
returns table (id uuid, code text, name text, tool_type text, material text, coating text, diameter numeric,
               equipment text, resource_min numeric, used_min numeric, wears integer, max_wears integer,
               life_pct numeric, status text, location text, note text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query select t.id, t.code, t.name, t.tool_type, t.material, t.coating, t.diameter, e.name,
    t.resource_min, t.used_min, t.wears, t.max_wears,
    round(case when t.resource_min>0 then t.used_min/t.resource_min*100 else 0 end, 1),
    t.status, t.location, t.note
    from public.app_tool_life t left join public.app_equipment e on e.id = t.equipment_id
    where (urole='admin' or t.tenant_id = ten)
      and (qq='' or lower(t.name) like '%'||qq||'%' or lower(coalesce(t.code,'')) like '%'||qq||'%' or lower(coalesce(t.tool_type,'')) like '%'||qq||'%' or lower(coalesce(e.name,'')) like '%'||qq||'%')
    order by (t.status='scrapped'), (t.status='worn') desc, t.name;
end $$;

-- ---------- Сохранить ----------
create or replace function public.app_tool_life_save(p_token uuid, p_id uuid, p_code text, p_name text, p_tool_type text,
  p_material text, p_coating text, p_diameter numeric, p_equipment_id uuid, p_resource_min numeric, p_max_wears integer,
  p_location text, p_note text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','master','chief','supply','technologist') then return query select false,'Недостаточно прав'; return; end if;
  if coalesce(trim(p_name),'') = '' then return query select false,'Укажите наименование'; return; end if;
  if p_id is null then
    insert into public.app_tool_life (tenant_id, code, name, tool_type, material, coating, diameter, equipment_id, resource_min, max_wears, location, note)
    values (ten, nullif(trim(p_code),''), trim(p_name), nullif(trim(p_tool_type),''), nullif(trim(p_material),''), nullif(trim(p_coating),''),
            p_diameter, p_equipment_id, coalesce(p_resource_min,0), coalesce(p_max_wears,3), nullif(trim(p_location),''), nullif(trim(p_note),''));
  else
    update public.app_tool_life set code=nullif(trim(p_code),''), name=trim(p_name), tool_type=nullif(trim(p_tool_type),''),
      material=nullif(trim(p_material),''), coating=nullif(trim(p_coating),''), diameter=p_diameter, equipment_id=p_equipment_id,
      resource_min=coalesce(p_resource_min,0), max_wears=coalesce(p_max_wears,3), location=nullif(trim(p_location),''), note=nullif(trim(p_note),'')
     where id=p_id and (urole='admin' or tenant_id=ten);
  end if;
  return query select true,'Сохранено';
end $$;

-- ---------- Учёт наработки ----------
create or replace function public.app_tool_life_use(p_token uuid, p_id uuid, p_minutes numeric, p_note text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; t public.app_tool_life; newused numeric;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select * into t from public.app_tool_life where id=p_id and (urole='admin' or tenant_id=ten);
  if t.id is null then return query select false,'Инструмент не найден'; return; end if;
  if coalesce(p_minutes,0) <= 0 then return query select false,'Укажите наработку > 0'; return; end if;
  newused := t.used_min + p_minutes;
  update public.app_tool_life set used_min = newused,
    status = case when t.resource_min>0 and newused >= t.resource_min then 'worn' else t.status end
   where id = p_id;
  if t.resource_min>0 and newused >= t.resource_min then
    perform public.app_notif_roles_t(ten, array['admin','owner','manager','master','chief'], 'Инструмент изношен: '||t.name,
      'Наработка '||round(newused)||' из '||round(t.resource_min)||' мин — требуется заточка/замена', 'apps/tooling/index.html');
  end if;
  return query select true,'Наработка учтена';
end $$;

-- ---------- Заточка ----------
create or replace function public.app_tool_life_resharpen(p_token uuid, p_id uuid, p_note text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; t public.app_tool_life; nw integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select * into t from public.app_tool_life where id=p_id and (urole='admin' or tenant_id=ten);
  if t.id is null then return query select false,'Инструмент не найден'; return; end if;
  nw := t.wears + 1;
  update public.app_tool_life set wears = nw, used_min = 0,
    status = case when nw >= t.max_wears then 'scrapped' else 'ok' end
   where id = p_id;
  if nw >= t.max_wears then
    perform public.app_notif_roles_t(ten, array['admin','owner','manager','master','chief','supply'], 'Инструмент списан: '||t.name,
      'Ресурс заточек исчерпан ('||nw||'/'||t.max_wears||')', 'apps/tooling/index.html');
    return query select true,'Заточка учтена, ресурс заточек исчерпан — инструмент списан';
  end if;
  return query select true,'Заточка учтена, наработка обнулена';
end $$;

grant execute on function public.app_tool_kpi(uuid) to anon, authenticated;
grant execute on function public.app_tool_life_list(uuid,text) to anon, authenticated;
grant execute on function public.app_tool_life_save(uuid,uuid,text,text,text,text,text,numeric,uuid,numeric,integer,text,text) to anon, authenticated;
grant execute on function public.app_tool_life_use(uuid,uuid,numeric,text) to anon, authenticated;
grant execute on function public.app_tool_life_resharpen(uuid,uuid,text) to anon, authenticated;

-- ---------- Демо (тенант A) ----------
insert into public.app_tool_life (tenant_id, code, name, tool_type, material, coating, diameter, equipment_id, resource_min, used_min, max_wears, status, location)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.code, v.name, v.tt, v.mat, v.coat, v.dia,
       (select id from public.app_equipment where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and kind=v.eqkind order by name limit 1),
       v.res, v.used, 3, v.st, v.loc
from (values
  ('T-001','Фреза концевая Ø10','Концевая фреза','твердосплав','TIAIN',10,'frezerny',600,180,'ok','инструментальная'),
  ('T-002','Фреза концевая Ø6','Концевая фреза','твердосплав','ALCRN',6,'frezerny',400,360,'ok','инструментальная'),
  ('T-003','Сверло Ø8.5','Сверло','HSS-Co','—',8.5,'sverlilny',240,250,'worn','инструментальная'),
  ('T-004','Метчик М10','Метчик','HSS','—',10,'sverlilny',200,40,'ok','инструментальная'),
  ('T-005','Резец CNMG 120408','Резец','твердосплав','CVD',null,'tokarny',480,120,'ok','инструментальная'),
  ('T-006','Проволока ЭЭО Ø0.25','Проволока','латунь','—',0.25,'edm',3000,3000,'worn','ЭЭО')
) as v(code, name, tt, mat, coat, dia, eqkind, res, used, st, loc)
where not exists (select 1 from public.app_tool_life where tenant_id='aaaaaaaa-0000-0000-0000-000000000001');

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Инструмент','Как вести учёт стойкости инструмента?',
   'Модуль «Инструмент и стойкость»: карточка инструмента (тип, материал, покрытие, Ø, оборудование, ресурс в минутах, допустимое число заточек). Учитывайте наработку — при достижении ресурса инструмент помечается «изношен» и приходит уведомление; после заточки наработка обнуляется, а по исчерпании числа заточек инструмент списывается.',
   'инструмент стойкость наработка ресурс заточка списание'),
  ('Инструмент','Связь с MES и закупками',
   'Наработку инструмента учитывайте при закрытии операций на станке (MES/производство). Списанный инструмент — сигнал снабжению к закупке (реестр инструмента в Справочниках → вкладка «Техданные»).',
   'инструмент MES производство закупка снабжение')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Как вести учёт стойкости инструмента?');
