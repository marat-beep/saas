-- ============================================================
-- 3DMP Service · 0208_setup_config.sql
-- Настройки модулей (app_tenant_settings), доступность модуля,
-- экспорт/импорт конфигурации организации. Идемпотентно. 0001..0207.
-- ============================================================

create table if not exists public.app_tenant_settings (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid not null references public.tenants (id) on delete cascade,
  module     text not null,
  settings   jsonb not null default '{}'::jsonb,
  by_login   text,
  updated_at timestamptz not null default now(),
  unique (tenant_id, module)
);
alter table public.app_tenant_settings enable row level security;
create index if not exists app_tenant_settings_idx on public.app_tenant_settings (tenant_id);

-- ================= RPC: настройки модулей =================
create or replace function public.app_tenant_settings_get(p_token uuid, p_module text default null)
returns table (module text, settings jsonb, updated_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query select s.module, s.settings, s.updated_at
    from public.app_tenant_settings s
   where (adm or s.tenant_id = ten) and (p_module is null or s.module = p_module)
   order by s.module;
end $$;

create or replace function public.app_tenant_settings_set(p_token uuid, p_module text, p_settings jsonb)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; uname text; mod text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  if not (public.app_is_owner(p_token) or public.app_is_platform_admin(p_token) or public.app_can_edit(p_token,'onboarding')) then
    return query select false,'Нет прав'; return;
  end if;
  select u.tenant_id, s.ulogin into ten, uname from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  mod := lower(trim(coalesce(p_module,'')));
  if mod = '' then return query select false,'Укажите модуль'; return; end if;
  insert into public.app_tenant_settings (tenant_id, module, settings, by_login, updated_at)
  values (ten, mod, coalesce(p_settings,'{}'::jsonb), uname, now())
  on conflict (tenant_id, module) do update set settings = excluded.settings, by_login = excluded.by_login, updated_at = now();
  return query select true,'Настройки модуля сохранены: ' || mod;
end $$;

-- Доступность модуля (гейтинг): нет записи → включён
create or replace function public.app_module_enabled(p_token uuid, p_module text)
returns boolean
language plpgsql stable security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid; en boolean;
begin
  if not public.app_production_allowed(p_token) then return true; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  select m.enabled into en from public.app_tenant_modules m
   where (adm or m.tenant_id = ten) and m.module = lower(trim(coalesce(p_module,''))) limit 1;
  return coalesce(en, true);
end $$;

-- ================= RPC: экспорт/импорт конфигурации =================
create or replace function public.app_config_export(p_token uuid)
returns table (config jsonb)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid; mods jsonb; sets jsonb; stps jsonb;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  select coalesce(jsonb_agg(jsonb_build_object('module', m.module, 'enabled', m.enabled) order by m.module), '[]'::jsonb)
    into mods from public.app_tenant_modules m where (adm or m.tenant_id = ten);
  select coalesce(jsonb_object_agg(s.module, s.settings), '{}'::jsonb)
    into sets from public.app_tenant_settings s where (adm or s.tenant_id = ten);
  select coalesce(jsonb_agg(jsonb_build_object('key', t.step_key, 'status', t.status, 'note', t.note) order by t.step_key), '[]'::jsonb)
    into stps from public.app_setup_steps t where (adm or t.tenant_id = ten);
  return query select jsonb_build_object(
    'format', '3dmp-config', 'version', 1, 'exported_at', now(),
    'modules', mods, 'settings', sets, 'steps', stps);
end $$;

create or replace function public.app_config_import(p_token uuid, p_config jsonb)
returns table (ok boolean, message text, modules integer, settings integer, steps integer)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; uname text; mc integer := 0; sc integer := 0; tc integer := 0; rec record; k text; v jsonb;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён',0,0,0; return; end if;
  if not (public.app_is_owner(p_token) or public.app_is_platform_admin(p_token) or public.app_can_edit(p_token,'onboarding')) then
    return query select false,'Нет прав (нужны владелец/администратор)',0,0,0; return;
  end if;
  if p_config is null or jsonb_typeof(p_config) <> 'object' or coalesce(p_config->>'format','') <> '3dmp-config' then
    return query select false,'Неверный формат файла конфигурации (ожидается 3dmp-config)',0,0,0; return;
  end if;
  select u.tenant_id, s.ulogin into ten, uname from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;

  if jsonb_typeof(coalesce(p_config->'modules','null')) = 'array' then
    for rec in select value as e from jsonb_array_elements(p_config->'modules') loop
      if coalesce(rec.e->>'module','') <> '' then
        insert into public.app_tenant_modules (tenant_id, module, enabled, enabled_at)
        values (ten, rec.e->>'module', coalesce((rec.e->>'enabled')::boolean,true), now())
        on conflict (tenant_id, module) do update set enabled = excluded.enabled, enabled_at = now();
        mc := mc + 1;
      end if;
    end loop;
  end if;

  if jsonb_typeof(coalesce(p_config->'settings','null')) = 'object' then
    for k, v in select key, value from jsonb_each(p_config->'settings') loop
      insert into public.app_tenant_settings (tenant_id, module, settings, by_login, updated_at)
      values (ten, k, v, uname, now())
      on conflict (tenant_id, module) do update set settings = excluded.settings, by_login = excluded.by_login, updated_at = now();
      sc := sc + 1;
    end loop;
  end if;

  if jsonb_typeof(coalesce(p_config->'steps','null')) = 'array' then
    for rec in select value as e from jsonb_array_elements(p_config->'steps') loop
      if coalesce(rec.e->>'key','') <> '' then
        insert into public.app_setup_steps (tenant_id, step_key, status, note, by_login, updated_at)
        values (ten, rec.e->>'key', coalesce(nullif(rec.e->>'status',''),'done'), rec.e->>'note', uname, now())
        on conflict (tenant_id, step_key) do update set status = excluded.status, note = excluded.note, by_login = excluded.by_login, updated_at = now();
        tc := tc + 1;
      end if;
    end loop;
  end if;

  return query select true, 'Конфигурация применена', mc, sc, tc;
end $$;

-- ================= База знаний =================
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Платформа','Настройки модулей и конфигурация организации (0208)',
   'Мастер настраивает все ВКЛЮЧЁННЫЕ модули (параметры с пояснениями) через app_tenant_settings (jsonb по модулю; get/set). Доступность модуля — app_module_enabled (нет записи = включён; отключённый модуль недоступен в навигации и по прямому URL). Экспорт/импорт конфигурации — app_config_export/config_import (формат 3dmp-config: modules/settings/steps; без секретов). Перенастройка конкретного модуля — запуск мастера с scope по модулю.',
   'настройки модулей конфигурация экспорт импорт onboarding мастер доступность модуля')
) as v(category,question,answer,tags)
where not exists (
  select 1 from public.app_knowledge
   where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001'
     and question = 'Настройки модулей и конфигурация организации (0208)'
);

-- ================= Права =================
grant execute on function public.app_tenant_settings_get(uuid,text) to anon, authenticated;
grant execute on function public.app_tenant_settings_set(uuid,text,jsonb) to anon, authenticated;
grant execute on function public.app_module_enabled(uuid,text) to anon, authenticated;
grant execute on function public.app_config_export(uuid) to anon, authenticated;
grant execute on function public.app_config_import(uuid,jsonb) to anon, authenticated;
