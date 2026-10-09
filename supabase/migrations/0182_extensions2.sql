-- ============================================================
-- 3DMP Service · 0182_extensions2.sql  (план v4, W40 «Расширения 2.0»)
-- Приватные расширения тенанта, зависимости/совместимость при установке,
-- расширенный манифест (detail) и редактор. Идемпотентно. Зависит от 0001..0181.
-- ============================================================

alter table public.app_extensions add column if not exists tenant_id uuid; -- null = публичное (глобальное)

-- ---------- Каталог: публичные + приватные своего тенанта ----------
drop function if exists public.app_ext_list(uuid);
create or replace function public.app_ext_list(p_token uuid)
returns table (id uuid, code text, name text, kind text, version text, vendor text, description text,
               deps text[], permissions text[], installed boolean, enabled boolean, private boolean)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token);
  return query
    select e.id, e.code, e.name, e.kind, e.version, e.vendor, e.description, e.deps, e.permissions,
           (i.id is not null) as installed, coalesce(i.enabled, false) as enabled, (e.tenant_id is not null) as private
      from public.app_extensions e
      left join public.app_extension_installs i on i.ext_id = e.id and i.tenant_id = ten
     where e.active and (e.tenant_id is null or e.tenant_id = ten)
     order by (i.id is not null) desc, e.kind, e.name;
end $$;
grant execute on function public.app_ext_list(uuid) to anon, authenticated;

-- ---------- Деталь расширения (для редактора) ----------
create or replace function public.app_ext_detail(p_token uuid, p_id uuid)
returns table (id uuid, code text, name text, kind text, version text, vendor text, description text,
               deps text[], permissions text[], manifest jsonb, active boolean, private boolean)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token);
  return query
    select e.id, e.code, e.name, e.kind, e.version, e.vendor, e.description, e.deps, e.permissions, e.manifest, e.active,
           (e.tenant_id is not null)
      from public.app_extensions e
     where e.id = p_id and (e.tenant_id is null or e.tenant_id = ten);
end $$;
grant execute on function public.app_ext_detail(uuid,uuid) to anon, authenticated;

-- ---------- Установка: проверка зависимостей ----------
create or replace function public.app_ext_install(p_token uuid, p_id uuid)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; uname text; e record; iid uuid; miss text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён',null::uuid; return; end if;
  select s.urole, s.ulogin into urole, uname from public.app_session_user(p_token) s;
  if urole not in ('admin','owner') then return query select false,'Установка доступна администратору/владельцу',null::uuid; return; end if;
  ten := public.app_my_tenant(p_token);
  select * into e from public.app_extensions where id = p_id and active and (tenant_id is null or tenant_id = ten);
  if e.id is null then return query select false,'Расширение не найдено',null::uuid; return; end if;
  -- зависимости: код должен быть установлен и включён у тенанта
  select string_agg(d, ', ') into miss from unnest(coalesce(e.deps,'{}')) d
   where not exists (select 1 from public.app_extension_installs i2
                       join public.app_extensions e2 on e2.id = i2.ext_id
                      where i2.tenant_id = ten and i2.enabled and e2.code = d);
  if miss is not null then
    return query select false, 'Не установлены/не включены зависимости: ' || miss, null::uuid; return;
  end if;
  insert into public.app_extension_installs (tenant_id, ext_id, version, enabled, installed_by)
  values (ten, e.id, e.version, false, uname)
  on conflict (tenant_id, ext_id) do update set version = e.version, updated_at = now()
  returning app_extension_installs.id into iid;
  perform public.app_log_event(p_token, 'Расширение установлено', e.name || ' v' || e.version);
  return query select true, 'Расширение «' || e.name || '» установлено (включите его)', iid;
end $$;

-- ---------- Сохранить манифест (админ платформы) с областью (публичное/приватное) ----------
drop function if exists public.app_ext_save(uuid,uuid,text,text,text,text,text,text,text[],text[],boolean);
create or replace function public.app_ext_save(p_token uuid, p_id uuid, p_code text, p_name text, p_kind text,
  p_version text, p_vendor text, p_description text, p_deps text[], p_permissions text[], p_active boolean, p_tenant_id uuid)
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
    insert into public.app_extensions (code, name, kind, version, vendor, description, deps, permissions, active, tenant_id)
    values (trim(p_code), trim(p_name), coalesce(nullif(trim(p_kind),''),'connector'), coalesce(nullif(trim(p_version),''),'1.0.0'),
            nullif(trim(p_vendor),''), nullif(trim(p_description),''), coalesce(p_deps,'{}'), coalesce(p_permissions,'{}'),
            coalesce(p_active,true), p_tenant_id)
    returning app_extensions.id into nid;
  else
    update public.app_extensions set code = trim(p_code), name = trim(p_name), kind = coalesce(nullif(trim(p_kind),''),kind),
           version = coalesce(nullif(trim(p_version),''),version), vendor = nullif(trim(p_vendor),''),
           description = nullif(trim(p_description),''), deps = coalesce(p_deps,deps),
           permissions = coalesce(p_permissions,permissions), active = coalesce(p_active,active), tenant_id = p_tenant_id
     where id = p_id returning app_extensions.id into nid;
    if nid is null then return query select false,'Расширение не найдено',null::uuid; return; end if;
  end if;
  return query select true, 'Манифест сохранён', nid;
end $$;
grant execute on function public.app_ext_save(uuid,uuid,text,text,text,text,text,text,text[],text[],boolean,uuid) to anon, authenticated;

create or replace function public.app_my_tenant_id(p_token uuid)
returns uuid language sql security definer set search_path = public
as $$ select public.app_my_tenant(p_token); $$;
grant execute on function public.app_my_tenant_id(uuid) to anon, authenticated;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001','Администрирование','Расширения 2.0: приватные, зависимости и редактор манифеста',
 'W40: расширения бывают публичными (tenant_id = null) и приватными для организации (tenant_id задан). Установка проверяет зависимости (deps): код зависимости должен быть установлен и включён у тенанта. Каталог — app_ext_list (публичные + приватные), деталь — app_ext_detail, редактор манифеста — app_ext_save (администратор платформы; поле области: публичное/приватное). UI — «Маркетплейс» → «Расширения» (редактор доступен администратору платформы).',
 'расширения приватные зависимости deps манифест редактор app_ext_save app_ext_detail'
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Расширения 2.0: приватные, зависимости и редактор манифеста');
