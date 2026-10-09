-- ============================================================
-- 3DMP Service · 0179_marketplace_ext.sql  (план v3, W35 «Маркетплейс-расширения»)
-- Реестр расширений/шаблонов с декларативной установкой по тенанту:
-- app_extensions (манифест), app_extension_installs (установка/включение).
-- Декларативно, без произвольного JS. Идемпотентно. Зависит от 0001..0178.
-- ============================================================

-- ---------- Реестр расширений (глобальный манифест) ----------
create table if not exists public.app_extensions (
  id          uuid primary key default gen_random_uuid(),
  code        text not null unique,
  name        text not null,
  kind        text not null default 'connector',   -- connector|template|report|dataset|kb|widget
  version     text not null default '1.0.0',
  vendor      text,
  description text,
  deps        text[] not null default '{}',
  permissions text[] not null default '{}',
  manifest    jsonb not null default '{}'::jsonb,
  active      boolean not null default true,
  created_at  timestamptz not null default now()
);
create index if not exists app_extensions_kind_idx on public.app_extensions (kind, name);
alter table public.app_extensions enable row level security;

-- ---------- Установки по тенантам ----------
create table if not exists public.app_extension_installs (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid not null,
  ext_id       uuid not null references public.app_extensions(id) on delete cascade,
  version      text not null default '1.0.0',
  enabled      boolean not null default false,
  settings     jsonb not null default '{}'::jsonb,
  installed_by text,
  installed_at timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (tenant_id, ext_id)
);
create index if not exists app_ext_installs_tenant_idx on public.app_extension_installs (tenant_id, enabled);
alter table public.app_extension_installs enable row level security;

-- ---------- RPC: каталог расширений (с признаком установки) ----------
create or replace function public.app_ext_list(p_token uuid)
returns table (id uuid, code text, name text, kind text, version text, vendor text, description text,
               deps text[], permissions text[], installed boolean, enabled boolean)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token);
  return query
    select e.id, e.code, e.name, e.kind, e.version, e.vendor, e.description, e.deps, e.permissions,
           (i.id is not null) as installed, coalesce(i.enabled, false) as enabled
      from public.app_extensions e
      left join public.app_extension_installs i on i.ext_id = e.id and i.tenant_id = ten
     where e.active
     order by (i.id is not null) desc, e.kind, e.name;
end $$;

-- ---------- RPC: мои установленные расширения ----------
create or replace function public.app_ext_installs_list(p_token uuid)
returns table (id uuid, ext_id uuid, code text, name text, kind text, version text, enabled boolean, installed_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token);
  return query
    select i.id, e.id, e.code, e.name, e.kind, i.version, i.enabled, i.installed_at
      from public.app_extension_installs i join public.app_extensions e on e.id = i.ext_id
     where i.tenant_id = ten
     order by e.name;
end $$;

-- ---------- RPC: установить (для тенанта; декларативно) ----------
create or replace function public.app_ext_install(p_token uuid, p_id uuid)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; uname text; e record; iid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён',null::uuid; return; end if;
  select s.urole, s.ulogin into urole, uname from public.app_session_user(p_token) s;
  if urole not in ('admin','owner') then return query select false,'Установка доступна администратору/владельцу',null::uuid; return; end if;
  ten := public.app_my_tenant(p_token);
  select * into e from public.app_extensions where id = p_id and active;
  if e.id is null then return query select false,'Расширение не найдено',null::uuid; return; end if;
  insert into public.app_extension_installs (tenant_id, ext_id, version, enabled, installed_by)
  values (ten, e.id, e.version, false, uname)
  on conflict (tenant_id, ext_id) do update set version = e.version, updated_at = now()
  returning app_extension_installs.id into iid;
  perform public.app_log_event(p_token, 'Расширение установлено', e.name || ' v' || e.version);
  return query select true, 'Расширение «' || e.name || '» установлено (включите его)', iid;
end $$;

-- ---------- RPC: включить/выключить (включение подтягивает интеграции) ----------
create or replace function public.app_ext_toggle(p_token uuid, p_id uuid, p_enabled boolean)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; uname text; iid uuid; e record; en boolean;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole, s.ulogin into urole, uname from public.app_session_user(p_token) s;
  if urole not in ('admin','owner') then return query select false,'Действие доступно администратору/владельцу'; return; end if;
  ten := public.app_my_tenant(p_token);
  select i.id into iid from public.app_extension_installs i where i.tenant_id = ten and i.ext_id = p_id;
  if iid is null then return query select false,'Сначала установите расширение'; return; end if;
  en := coalesce(p_enabled, false);
  update public.app_extension_installs set enabled = en, updated_at = now() where id = iid;

  select * into e from public.app_extensions where id = p_id;
  if en and e.kind = 'connector' then
    -- подтягиваем точку интеграции (если её ещё нет)
    if not exists (select 1 from public.app_integrations g where g.tenant_id = ten and g.name = e.name) then
      insert into public.app_integrations (tenant_id, name, kind, direction, endpoint, settings, active, created_login)
      values (ten, e.name, coalesce(e.manifest->>'kind','connector'), coalesce(e.manifest->>'direction','in'),
              e.manifest->>'endpoint', coalesce(e.manifest->'settings','{}'::jsonb), true, uname);
    end if;
  end if;
  perform public.app_log_event(p_token, case when en then 'Расширение включено' else 'Расширение выключено' end, e.name);
  return query select true, case when en then 'Расширение включено' else 'Расширение выключено' end;
end $$;

-- ---------- RPC: удалить установку ----------
create or replace function public.app_ext_uninstall(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  if urole not in ('admin','owner') then return query select false,'Действие доступно администратору/владельцу'; return; end if;
  ten := public.app_my_tenant(p_token);
  delete from public.app_extension_installs where tenant_id = ten and ext_id = p_id;
  if not found then return query select false,'Установка не найдена'; return; end if;
  return query select true, 'Расширение удалено';
end $$;

-- ---------- RPC: сохранить манифест (админ платформы) ----------
create or replace function public.app_ext_save(p_token uuid, p_id uuid, p_code text, p_name text, p_kind text,
  p_version text, p_vendor text, p_description text, p_deps text[], p_permissions text[], p_active boolean)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare nid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён',null::uuid; return; end if;
  if not public.app_is_platform_admin(p_token) then return query select false,'Только администратор платформы',null::uuid; return; end if;
  if coalesce(trim(p_code),'') = '' or coalesce(trim(p_name),'') = '' then
    return query select false,'Укажите код и название',null::uuid; return;
  end if;
  if p_id is null then
    insert into public.app_extensions (code, name, kind, version, vendor, description, deps, permissions, active)
    values (trim(p_code), trim(p_name), coalesce(nullif(trim(p_kind),''),'connector'), coalesce(nullif(trim(p_version),''),'1.0.0'),
            nullif(trim(p_vendor),''), nullif(trim(p_description),''), coalesce(p_deps,'{}'), coalesce(p_permissions,'{}'), coalesce(p_active,true))
    returning app_extensions.id into nid;
  else
    update public.app_extensions set code = trim(p_code), name = trim(p_name), kind = coalesce(nullif(trim(p_kind),''),kind),
           version = coalesce(nullif(trim(p_version),''),version), vendor = nullif(trim(p_vendor),''),
           description = nullif(trim(p_description),''), deps = coalesce(p_deps,deps),
           permissions = coalesce(p_permissions,permissions), active = coalesce(p_active,active)
     where id = p_id returning app_extensions.id into nid;
    if nid is null then return query select false,'Расширение не найдено',null::uuid; return; end if;
  end if;
  return query select true, 'Манифест сохранён', nid;
end $$;

-- ---------- Демо-расширения ----------
insert into public.app_extensions (code, name, kind, version, vendor, description, deps, permissions, manifest)
values
  ('conn-1c-erp', 'Коннектор 1С:ERP', 'connector', '1.2.0', '3DMP', 'Обмен заказами и НСИ с 1С:ERP (очередь интеграций).', '{}', '{integrations.write}', '{"kind":"erp","direction":"in","endpoint":null}'),
  ('rep-oee', 'Отчёт: эффективность оборудования', 'report', '1.0.0', '3DMP', 'Готовый отчёт OEE по центрам/станкам.', '{oee}', '{reports.read}', '{}'),
  ('ds-production', 'Набор данных: производство', 'dataset', '1.0.0', '3DMP', 'Набор для конструктора отчётов (наряды/MES).', '{reports}', '{reports.read}', '{}'),
  ('kb-norms', 'БЗ: нормирование труда', 'kb', '1.0.0', '3DMP', 'Статьи по нормированию и расчёту трудоёмкости.', '{}', '{kb.read}', '{}'),
  ('tpl-meeting', 'Шаблон: протокол совещания', 'template', '1.0.0', '3DMP', 'Шаблон документа для ЭДО.', '{edo}', '{edo.write}', '{}'),
  ('wid-shopkpi', 'Виджет: KPI цеха', 'widget', '1.0.0', '3DMP', 'Виджет показателей цеха для пульта.', '{}', '{dashboard.read}', '{}')
on conflict (code) do nothing;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001','Платформа','Маркетплейс расширений: каталог, установка и включение по тенанту',
 'Маркетплейс расширений (W35): реестр манифестов app_extensions (тип connector/template/report/dataset/kb/widget, версия, зависимости deps, права permissions, manifest) и установки по тенанту app_extension_installs (версия, enabled, settings). Каталог — app_ext_list (с признаком установки для организации), мои установки — app_ext_installs_list. Установка (app_ext_install) и включение/выключение (app_ext_toggle), удаление (app_ext_uninstall) — администратор/владелец тенанта; создание/правка манифеста (app_ext_save) — администратор платформы. Включение коннектора подтягивает точку интеграции в app_integrations; все действия пишутся в журнал (app_log_event). Установка декларативна — без произвольного JS. UI — модуль «Маркетплейс», вкладка «Расширения».',
 'маркетплейс расширения extensions установка connector template report dataset kb widget манифест интеграции тенант'
where not exists (
  select 1 from public.app_knowledge
   where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001'
     and question = 'Маркетплейс расширений: каталог, установка и включение по тенанту'
);

-- ---------- Права ----------
grant execute on function public.app_ext_list(uuid) to anon, authenticated;
grant execute on function public.app_ext_installs_list(uuid) to anon, authenticated;
grant execute on function public.app_ext_install(uuid,uuid) to anon, authenticated;
grant execute on function public.app_ext_toggle(uuid,uuid,boolean) to anon, authenticated;
grant execute on function public.app_ext_uninstall(uuid,uuid) to anon, authenticated;
grant execute on function public.app_ext_save(uuid,uuid,text,text,text,text,text,text,text[],text[],boolean) to anon, authenticated;
