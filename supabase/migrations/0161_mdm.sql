-- ============================================================
-- 3DMP Service · 0161_mdm.sql  (W18b — НСИ / MDM)
-- Единый справочник номенклатуры: реестр, версии, внешние коды (сопоставление),
-- поиск дублей и слияние, импорт. Идемпотентно. Зависит от 0001..0160.
-- ============================================================

create table if not exists public.app_master_items (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid references public.tenants (id),
  code        text,
  name        text not null,
  item_type   text not null default 'material',  -- material|product|service|equipment|tool|other
  unit        text,
  grp         text,
  attrs       jsonb not null default '{}'::jsonb,
  status      text not null default 'active',     -- active|archived
  source      text,
  note        text,
  created_login text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists app_master_items_idx on public.app_master_items (tenant_id, item_type, status);
create unique index if not exists app_master_items_code_uq on public.app_master_items (tenant_id, lower(code)) where code is not null;
alter table public.app_master_items enable row level security;

create table if not exists public.app_master_item_versions (
  id          uuid primary key default gen_random_uuid(),
  item_id     uuid not null references public.app_master_items (id) on delete cascade,
  version     integer not null,
  name        text,
  attrs       jsonb not null default '{}'::jsonb,
  created_login text,
  created_at  timestamptz not null default now()
);
create index if not exists app_master_item_versions_idx on public.app_master_item_versions (item_id, version desc);
alter table public.app_master_item_versions enable row level security;

create table if not exists public.app_mdm_links (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid references public.tenants (id),
  item_id     uuid not null references public.app_master_items (id) on delete cascade,
  system      text not null,     -- 1c|plm|erp|other
  ext_code    text not null,
  created_at  timestamptz not null default now()
);
create index if not exists app_mdm_links_idx on public.app_mdm_links (item_id, system);
alter table public.app_mdm_links enable row level security;

-- ---------- RPC: реестр ----------
create or replace function public.app_master_items_list(p_token uuid, p_q text default null, p_type text default null, p_group text default null)
returns table (id uuid, code text, name text, item_type text, unit text, grp text, status text, attrs jsonb, links bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query
    select m.id, m.code, m.name, m.item_type, m.unit, m.grp, m.status, m.attrs,
           (select count(*) from public.app_mdm_links l where l.item_id = m.id)
      from public.app_master_items m
     where (adm or m.tenant_id = ten)
       and (p_q is null or p_q = '' or m.name ilike '%'||p_q||'%' or coalesce(m.code,'') ilike '%'||p_q||'%')
       and (p_type is null or p_type = '' or m.item_type = p_type)
       and (p_group is null or p_group = '' or m.grp = p_group)
     order by m.item_type, m.name;
end $$;

create or replace function public.app_master_item_save(p_token uuid, p_id uuid, p_code text, p_name text, p_item_type text, p_unit text, p_group text, p_attrs jsonb, p_status text, p_note text)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; uname text; newid uuid; tp text; st text; v_next integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid; return; end if;
  select u.tenant_id, s.ulogin into ten, uname from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  if coalesce(trim(p_name),'') = '' then return query select false,'Укажите наименование', null::uuid; return; end if;
  tp := coalesce(nullif(trim(p_item_type),''),'material');
  if tp not in ('material','product','service','equipment','tool','other') then return query select false,'Недопустимый тип', null::uuid; return; end if;
  st := coalesce(nullif(trim(p_status),''),'active');
  if st not in ('active','archived') then return query select false,'Недопустимый статус', null::uuid; return; end if;

  if p_id is null then
    insert into public.app_master_items (tenant_id, code, name, item_type, unit, grp, attrs, status, source, note, created_login)
    values (ten, nullif(trim(p_code),''), left(trim(p_name),200), tp, nullif(trim(p_unit),''), nullif(trim(p_group),''),
            coalesce(p_attrs,'{}'::jsonb), st, 'manual', nullif(trim(p_note),''), uname)
    returning app_master_items.id into newid;
    insert into public.app_master_item_versions (item_id, version, name, attrs, created_login)
    values (newid, 1, left(trim(p_name),200), coalesce(p_attrs,'{}'::jsonb), uname);
    return query select true,'Позиция НСИ создана', newid;
  else
    select coalesce(max(v.version),0) + 1 into v_next from public.app_master_item_versions v where v.item_id = p_id;
    update public.app_master_items m set code = nullif(trim(p_code),''), name = left(trim(p_name),200), item_type = tp,
           unit = nullif(trim(p_unit),''), grp = nullif(trim(p_group),''), attrs = coalesce(p_attrs, m.attrs),
           status = st, note = nullif(trim(p_note),''), updated_at = now()
     where m.id = p_id and (public.app_is_platform_admin(p_token) or m.tenant_id = ten)
     returning m.id into newid;
    if newid is null then return query select false,'Позиция не найдена', null::uuid; return; end if;
    insert into public.app_master_item_versions (item_id, version, name, attrs, created_login)
    values (newid, v_next, left(trim(p_name),200), coalesce(p_attrs,'{}'::jsonb), uname);
    return query select true,'Позиция сохранена', newid;
  end if;
end $$;

create or replace function public.app_master_item_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; n integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten := public.app_my_tenant(p_token);
  delete from public.app_master_items m where m.id = p_id and (public.app_is_platform_admin(p_token) or m.tenant_id = ten);
  get diagnostics n = row_count;
  if n = 0 then return query select false,'Позиция не найдена'; return; end if;
  return query select true,'Позиция удалена';
end $$;

create or replace function public.app_master_item_versions_list(p_token uuid, p_item_id uuid)
returns table (version integer, name text, attrs jsonb, created_login text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query
    select v.version, v.name, v.attrs, v.created_login, v.created_at
      from public.app_master_item_versions v join public.app_master_items m on m.id = v.item_id
     where v.item_id = p_item_id and (adm or m.tenant_id = ten)
     order by v.version desc;
end $$;

-- ---------- RPC: сопоставление (внешние коды) ----------
create or replace function public.app_mdm_links_list(p_token uuid, p_item_id uuid)
returns table (id uuid, system text, ext_code text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query select l.id, l.system, l.ext_code from public.app_mdm_links l
    where l.item_id = p_item_id and (adm or l.tenant_id = ten) order by l.system;
end $$;

create or replace function public.app_mdm_link_save(p_token uuid, p_id uuid, p_item_id uuid, p_system text, p_ext_code text)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; newid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid; return; end if;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_system),'') = '' or coalesce(trim(p_ext_code),'') = '' then return query select false,'Укажите систему и код', null::uuid; return; end if;
  if not exists (select 1 from public.app_master_items m where m.id = p_item_id and (public.app_is_platform_admin(p_token) or m.tenant_id = ten)) then
    return query select false,'Позиция не найдена', null::uuid; return;
  end if;
  if p_id is null then
    insert into public.app_mdm_links (tenant_id, item_id, system, ext_code) values (ten, p_item_id, lower(trim(p_system)), trim(p_ext_code))
    returning app_mdm_links.id into newid;
    return query select true,'Сопоставление добавлено', newid;
  else
    update public.app_mdm_links l set system = lower(trim(p_system)), ext_code = trim(p_ext_code)
     where l.id = p_id and (public.app_is_platform_admin(p_token) or l.tenant_id = ten)
     returning l.id into newid;
    if newid is null then return query select false,'Сопоставление не найдено', null::uuid; return; end if;
    return query select true,'Сопоставление сохранено', newid;
  end if;
end $$;

create or replace function public.app_mdm_link_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; n integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten := public.app_my_tenant(p_token);
  delete from public.app_mdm_links l where l.id = p_id and (public.app_is_platform_admin(p_token) or l.tenant_id = ten);
  get diagnostics n = row_count;
  if n = 0 then return query select false,'Сопоставление не найдено'; return; end if;
  return query select true,'Сопоставление удалено';
end $$;

-- ---------- RPC: дубли и слияние ----------
create or replace function public.app_mdm_duplicates(p_token uuid, p_limit integer default 50)
returns table (name text, cnt bigint, codes text, ids text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query
    select lower(trim(m.name)), count(*), string_agg(coalesce(m.code,'—'), ', ' order by m.code), string_agg(m.id::text, ',')
      from public.app_master_items m
     where (adm or m.tenant_id = ten) and m.status = 'active'
     group by lower(trim(m.name))
    having count(*) > 1
     order by count(*) desc
     limit greatest(coalesce(p_limit,50),1);
end $$;

create or replace function public.app_mdm_merge(p_token uuid, p_keep uuid, p_dup uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; uname text; keep record; dup record; n integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select u.tenant_id, s.ulogin into ten, uname from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  if p_keep = p_dup then return query select false,'Выберите разные позиции'; return; end if;
  select * into keep from public.app_master_items where id = p_keep and (public.app_is_platform_admin(p_token) or tenant_id = ten);
  select * into dup from public.app_master_items where id = p_dup and (public.app_is_platform_admin(p_token) or tenant_id = ten);
  if keep.id is null or dup.id is null then return query select false,'Позиция не найдена'; return; end if;
  -- переносим внешние коды
  update public.app_mdm_links set item_id = p_keep, tenant_id = ten where item_id = p_dup;
  -- дополняем атрибуты основной
  update public.app_master_items m set attrs = coalesce(m.attrs,'{}'::jsonb) || coalesce(dup.attrs,'{}'::jsonb), updated_at = now()
   where m.id = p_keep;
  update public.app_master_items m set status = 'archived', note = coalesce(m.note,'') || ' [объединено в ' || coalesce(keep.code, keep.id::text) || ']', updated_at = now()
   where m.id = p_dup;
  get diagnostics n = row_count;
  return query select true,'Позиция ' || coalesce(dup.code, dup.name) || ' объединена в ' || coalesce(keep.code, keep.name);
end $$;

-- ---------- RPC: импорт и KPI ----------
create or replace function public.app_mdm_import(p_token uuid, p_items jsonb)
returns table (ok boolean, message text, created integer, updated integer)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; uname text; it jsonb; c text; nm text; tp text; un text; cnt_c integer := 0; cnt_u integer := 0; eid uuid; ext jsonb; k text; v text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён',0,0; return; end if;
  select u.tenant_id, s.ulogin into ten, uname from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  if p_items is null or jsonb_typeof(p_items) <> 'array' then return query select false,'Ожидается массив позиций',0,0; return; end if;
  for it in select * from jsonb_array_elements(p_items) loop
    c := nullif(trim(it->>'code'),''); nm := nullif(trim(it->>'name'),'');
    if nm is null then continue; end if;
    tp := coalesce(nullif(trim(it->>'item_type'),''),'material'); un := nullif(trim(it->>'unit'),'');
    eid := null;
    if c is not null then select id into eid from public.app_master_items where tenant_id = ten and lower(code) = lower(c) limit 1; end if;
    if eid is null then
      insert into public.app_master_items (tenant_id, code, name, item_type, unit, attrs, source, created_login)
      values (ten, c, left(nm,200), tp, un, coalesce(it->'attrs','{}'::jsonb), 'import', uname)
      returning app_master_items.id into eid;
      insert into public.app_master_item_versions (item_id, version, name, attrs, created_login) values (eid, 1, left(nm,200), coalesce(it->'attrs','{}'::jsonb), uname);
      cnt_c := cnt_c + 1;
    else
      update public.app_master_items set name = left(nm,200), item_type = tp, unit = un, attrs = coalesce(it->'attrs', attrs), updated_at = now() where id = eid;
      cnt_u := cnt_u + 1;
    end if;
    ext := it->'external';
    if ext is not null and jsonb_typeof(ext) = 'object' then
      for k, v in select key, value from jsonb_each_text(ext) loop
        if not exists (select 1 from public.app_mdm_links where item_id = eid and system = lower(k)) then
          insert into public.app_mdm_links (tenant_id, item_id, system, ext_code) values (ten, eid, lower(k), v);
        end if;
      end loop;
    end if;
  end loop;
  return query select true, 'Импорт: создано ' || cnt_c || ', обновлено ' || cnt_u, cnt_c, cnt_u;
end $$;

create or replace function public.app_mdm_kpi(p_token uuid)
returns table (total bigint, active bigint, archived bigint, materials bigint, products bigint, services bigint, linked bigint, duplicates bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query select
    (select count(*) from public.app_master_items m where adm or m.tenant_id=ten),
    (select count(*) from public.app_master_items m where (adm or m.tenant_id=ten) and m.status='active'),
    (select count(*) from public.app_master_items m where (adm or m.tenant_id=ten) and m.status='archived'),
    (select count(*) from public.app_master_items m where (adm or m.tenant_id=ten) and m.item_type='material'),
    (select count(*) from public.app_master_items m where (adm or m.tenant_id=ten) and m.item_type='product'),
    (select count(*) from public.app_master_items m where (adm or m.tenant_id=ten) and m.item_type='service'),
    (select count(distinct m.id) from public.app_master_items m where (adm or m.tenant_id=ten) and exists (select 1 from public.app_mdm_links l where l.item_id=m.id)),
    (select coalesce(count(*),0) from (select lower(trim(m.name)) from public.app_master_items m where (adm or m.tenant_id=ten) and m.status='active' group by lower(trim(m.name)) having count(*)>1) d);
end $$;

-- ---------- Демо ----------
insert into public.app_master_items (tenant_id, code, name, item_type, unit, grp, attrs, source, created_login)
select 'aaaaaaaa-0000-0000-0000-000000000001', 'MAT-ST45', 'Сталь 45, лист 10мм', 'material', 'кг', 'Металл', '{"grade":"45"}'::jsonb, 'demo', 'owner'
where not exists (select 1 from public.app_master_items where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and code='MAT-ST45');

insert into public.app_master_items (tenant_id, code, name, item_type, unit, grp, attrs, source, created_login)
select 'aaaaaaaa-0000-0000-0000-000000000001', 'SRV-CNC', 'Обработка на ЧПУ (час)', 'service', 'ч', 'Услуги', '{}'::jsonb, 'demo', 'owner'
where not exists (select 1 from public.app_master_items where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and code='SRV-CNC');

insert into public.app_mdm_links (tenant_id, item_id, system, ext_code)
select 'aaaaaaaa-0000-0000-0000-000000000001', m.id, '1c', '00-000123'
from public.app_master_items m
where m.tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and m.code='MAT-ST45'
  and not exists (select 1 from public.app_mdm_links l where l.item_id = m.id and l.system='1c');

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Платформа','НСИ / MDM: единый справочник, версии, сопоставление, дубли',
   'W18b: единый справочник номенклатуры (app_master_items: код, тип material/product/service/equipment/tool, ед., группа, атрибуты, статус) с версиями (app_master_item_versions); сопоставление с внешними системами (app_mdm_links: 1c/plm/erp) — list/save/delete; поиск дублей (app_mdm_duplicates по наименованию) и слияние (app_mdm_merge — перенос кодов/атрибутов, архивация); импорт (app_mdm_import по коду + external); KPI (app_mdm_kpi). Модуль «НСИ / Мастер-данные» (apps/mdm).',
   'НСИ MDM справочник номенклатура версии сопоставление дубли слияние импорт 1С')
) as v(category,question,answer,tags)
where not exists (
  select 1 from public.app_knowledge
   where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001' and question = 'НСИ / MDM: единый справочник, версии, сопоставление, дубли'
);

-- ---------- Права ----------
grant execute on function public.app_master_items_list(uuid,text,text,text) to anon, authenticated;
grant execute on function public.app_master_item_save(uuid,uuid,text,text,text,text,text,jsonb,text,text) to anon, authenticated;
grant execute on function public.app_master_item_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_master_item_versions_list(uuid,uuid) to anon, authenticated;
grant execute on function public.app_mdm_links_list(uuid,uuid) to anon, authenticated;
grant execute on function public.app_mdm_link_save(uuid,uuid,uuid,text,text) to anon, authenticated;
grant execute on function public.app_mdm_link_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_mdm_duplicates(uuid,integer) to anon, authenticated;
grant execute on function public.app_mdm_merge(uuid,uuid,uuid) to anon, authenticated;
grant execute on function public.app_mdm_import(uuid,jsonb) to anon, authenticated;
grant execute on function public.app_mdm_kpi(uuid) to anon, authenticated;
