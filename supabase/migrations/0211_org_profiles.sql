-- ============================================================
-- 3DMP Service · 0211_org_profiles.sql
-- Профили организации (автонабор модулей) и массовые операции:
-- app_org_profiles_list, app_org_profile_apply, app_modules_set_bulk.
-- Идемпотентно. Зависит от 0001..0210.
-- ============================================================

create table if not exists public.app_org_profiles (
  id          uuid primary key default gen_random_uuid(),
  code        text not null unique,
  name        text not null,
  description text,
  modules     jsonb not null default '[]'::jsonb,   -- ["orders","production",...]
  sort        integer default 0
);
alter table public.app_org_profiles enable row level security;

-- ---------- Демо-профили ----------
insert into public.app_org_profiles (code, name, description, modules, sort) values
 ('workshop','Малая мастерская','Базовый набор: заявки, документы, производство, склад, качество, оборудование.', '["panel","dashboard","onboarding","orders","crm","docs","templates","warehouse","production","qc","equipment","maintenance","tasks","calendar","files","org","roles"]'::jsonb, 1),
 ('plant','Средний завод','Добавляет планирование, MES, закупки, экономику, кадры, КЭДО, сервис, ТОиР, компетенции, ОТ.', '["panel","dashboard","onboarding","orders","crm","docs","templates","warehouse","production","qc","equipment","maintenance","tasks","calendar","files","org","roles","planning","mes","tooling","oee","procurement","suppliers","supplier","economics","finance","hr","kedo","staff","service","competences","safety","edo"]'::jsonb, 2),
 ('holding','Крупное предприятие / холдинг','Полный контур: проекты, MES/APS, ТОиР/EAM, финансы, холдинг, интеграции, BI.', '["panel","dashboard","onboarding","orders","crm","docs","templates","warehouse","production","qc","equipment","maintenance","tasks","calendar","files","org","roles","planning","mes","tooling","oee","procurement","suppliers","supplier","economics","finance","hr","kedo","staff","service","competences","safety","edo","holding","industry","projbudget","pmo","itsm","tms","accounting","mdm","plm","bi","eam","forecast","escrow","marketplace","partners","dealer","integrations","api","platform","billing","usage","adoption","guide","modules","reports","analytics","ai","assistant","support","issues","claims","quality","passport","registry","norms","nc","labels","logistics","reverse","lean","setup","slots","scale","dicts"]'::jsonb, 3)
on conflict (code) do update set name = excluded.name, description = excluded.description, modules = excluded.modules, sort = excluded.sort;

-- ================= RPC: профили =================
create or replace function public.app_org_profiles_list(p_token uuid)
returns table (code text, name text, description text, modules jsonb)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  return query select p.code, p.name, p.description, p.modules from public.app_org_profiles p order by p.sort, p.name;
end $$;

create or replace function public.app_modules_set_bulk(p_token uuid, p_modules jsonb, p_enabled boolean)
returns table (ok boolean, message text, changed integer)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; uname text; cnt integer := 0; rec record;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён',0; return; end if;
  if not (public.app_is_owner(p_token) or public.app_is_platform_admin(p_token) or public.app_can_edit(p_token,'onboarding')) then
    return query select false,'Нет прав',0; return;
  end if;
  if p_modules is null or jsonb_typeof(p_modules) <> 'array' then return query select false,'Ожидается массив модулей',0; return; end if;
  select u.tenant_id, s.ulogin into ten, uname from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  for rec in select value as m from jsonb_array_elements_text(p_modules) loop
    if coalesce(trim(rec.m),'') = '' then continue; end if;
    insert into public.app_tenant_modules (tenant_id, module, enabled, enabled_at)
    values (ten, trim(rec.m), coalesce(p_enabled,true), now())
    on conflict (tenant_id, module) do update set enabled = coalesce(p_enabled,true), enabled_at = now();
    cnt := cnt + 1;
  end loop;
  return query select true, 'Изменено модулей: ' || cnt, cnt;
end $$;

create or replace function public.app_org_profile_apply(p_token uuid, p_code text, p_all jsonb default null)
returns table (ok boolean, message text, enabled integer, disabled integer)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; uname text; profs jsonb; rec record; en integer := 0; dis integer := 0;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён',0,0; return; end if;
  if not (public.app_is_owner(p_token) or public.app_is_platform_admin(p_token) or public.app_can_edit(p_token,'onboarding')) then
    return query select false,'Нет прав (нужны владелец/администратор)',0,0; return;
  end if;
  select p.modules into profs from public.app_org_profiles p where p.code = lower(trim(coalesce(p_code,'')));
  if profs is null then return query select false,'Профиль не найден',0,0; return; end if;
  select u.tenant_id, s.ulogin into ten, uname from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;

  -- включить модули профиля
  for rec in select value as m from jsonb_array_elements_text(profs) loop
    insert into public.app_tenant_modules (tenant_id, module, enabled, enabled_at)
    values (ten, trim(rec.m), true, now())
    on conflict (tenant_id, module) do update set enabled = true, enabled_at = now();
    en := en + 1;
  end loop;
  -- режим «набор»: выключить всё, чего нет в профиле (если передан полный список)
  if p_all is not null and jsonb_typeof(p_all) = 'array' then
    for rec in select value as m from jsonb_array_elements_text(p_all) loop
      if not (profs ? trim(rec.m)) then
        insert into public.app_tenant_modules (tenant_id, module, enabled, enabled_at)
        values (ten, trim(rec.m), false, now())
        on conflict (tenant_id, module) do update set enabled = false, enabled_at = now();
        dis := dis + 1;
      end if;
    end loop;
  end if;
  return query select true, 'Профиль применён', en, dis;
end $$;

-- ================= База знаний =================
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Платформа','Профили организации и массовое включение модулей (0211)',
   'Профили организации (app_org_profiles: workshop/plant/holding) — автонабор модулей. app_org_profile_apply(token, code, p_all) включает модули профиля; при передаче полного списка (p_all) отключает остальные («набор»). Массовое включение/отключение — app_modules_set_bulk(token, [modules], enabled). Используется в «Мастере настройки».',
   'профиль организации автонабор модулей workshop plant holding массовое включение')
) as v(category,question,answer,tags)
where not exists (
  select 1 from public.app_knowledge
   where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001'
     and question = 'Профили организации и массовое включение модулей (0211)'
);

-- ================= Права =================
grant execute on function public.app_org_profiles_list(uuid) to anon, authenticated;
grant execute on function public.app_modules_set_bulk(uuid,jsonb,boolean) to anon, authenticated;
grant execute on function public.app_org_profile_apply(uuid,text,jsonb) to anon, authenticated;
