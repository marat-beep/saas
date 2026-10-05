-- ============================================================
-- 3DMP Service · 0041_org_ref.sql  (v23.0 — переработка «Организация»)
-- Инфо об организации (+ бренд, статус), чтение бренда, роли предприятия в пользователях.
-- База знаний. Зависит от 0001..0040.
-- ============================================================

-- ---------- Инфо об организации (расширенное) ----------
drop function if exists public.app_tenant_info(uuid);
create or replace function public.app_tenant_info(p_token uuid)
returns table (id uuid, name text, plan text, plan_name text, max_users integer,
               users_count bigint, features jsonb, brand jsonb, status text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare ten uuid;
begin
  select u.tenant_id into ten from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  if ten is null then return; end if;
  return query
    select t.id, t.name, t.plan, p.name, p.max_users,
           (select count(*) from public.app_users u2 where u2.tenant_id = t.id),
           t.features, t.brand, t.status, t.created_at
    from public.tenants t
    left join public.app_plans p on p.code = t.plan
    where t.id = ten;
end $$;

-- ---------- Бренд организации ----------
create or replace function public.app_tenant_brand(p_token uuid)
returns jsonb language plpgsql security definer set search_path = public
as $$
declare ten uuid; b jsonb;
begin
  select u.tenant_id into ten from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  select t.brand into b from public.tenants t where t.id = ten;
  return coalesce(b, '{}'::jsonb);
end $$;

-- ---------- Сводка по модулям (вкл/выкл) ----------
create or replace function public.app_tenant_modules(p_token uuid, p_modules text[])
returns table (module_id text, enabled boolean)
language plpgsql security definer set search_path = public
as $$
declare ten uuid; f jsonb;
begin
  select u.tenant_id into ten from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  select t.features into f from public.tenants t where t.id = ten;
  f := coalesce(f, '{}'::jsonb);
  return query select m.module_id, coalesce((f->>m.module_id)::boolean, true) from unnest(p_modules) as m(module_id);
end $$;

grant execute on function public.app_tenant_info(uuid) to anon, authenticated;
grant execute on function public.app_tenant_brand(uuid) to anon, authenticated;
grant execute on function public.app_tenant_modules(uuid,text[]) to anon, authenticated;

-- ---------- База знаний: организация ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Организация','Как управлять пользователями и ролями организации?',
   'В «Организации» (админ-панель клиента) на вкладке «Пользователи» владелец добавляет сотрудников (логин/пароль/роль), меняет роль, включает/выключает доступ и сбрасывает пароль. Доступны все роли предприятия: директор, начальник цеха, мастер, технолог, оператор ЧПУ, снабженец, ОТК, экономист (+ менеджер, поставщик). Точные права по модулям — в модуле «Роли и права».',
   'организация пользователи роли владелец доступ клиент'),
  ('Организация','Что такое модули (feature flags) и тариф?',
   'Вкладка «Модули» включает/выключает приложения для организации (кроме платформенных). Вкладка «Тариф» — план (Старт/Бизнес/Корпоративный) с ценой и лимитом пользователей. Вкладка «Бренд» — название, цвет и логотип для white-label. Всё изолировано по организации.',
   'модули feature flags тариф бренд white-label организация')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and category='Организация');
