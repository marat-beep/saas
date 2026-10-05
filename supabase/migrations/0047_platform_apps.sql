-- ============================================================
-- 3DMP Service · 0047_platform_apps.sql  (v29.0 — платформенные модули)
-- admin_list_users: + организация и последний вход. База знаний (API/Платформа/Админ).
-- Зависит от 0001..0046.
-- ============================================================

drop function if exists public.admin_list_users(uuid);
create or replace function public.admin_list_users(p_token uuid)
returns table (id uuid, login text, full_name text, role text, active boolean,
               tenant_name text, last_login_at timestamptz, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
begin
  if not public.is_admin(p_token) then raise exception 'Доступ запрещён'; end if;
  return query
    select u.id, u.login, u.full_name, u.role, u.active, t.name, u.last_login_at, u.created_at
    from public.app_users u left join public.tenants t on t.id = u.tenant_id
    order by u.created_at;
end $$;

grant execute on function public.admin_list_users(uuid) to anon, authenticated;

-- ---------- База знаний: платформа ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Платформа','Как работает Public API и вебхуки?',
   'В модуле «API и интеграции» владелец создаёт API-ключи организации. По ключу внешние системы читают данные через публичные функции: api_orders (заявки), api_tenders (закупки), api_stock (склад) — POST на /rest/v1/rpc/<функция> с параметром p_key. Вебхуки регистрируют URL, куда сервис шлёт события (заявка создана, новое КП, наряд закрыт).',
   'API ключи вебхуки интеграция 1С api_orders api_stock'),
  ('Платформа','Что делает администратор платформы?',
   'Администратор платформы: создаёт и ведёт организации (тариф, статус), управляет всеми пользователями и ролями сервиса, смотрит журнал действий. Клиенты администрируют свою организацию сами в «Админ-панели клиента» (сотрудники/роли/модули/бренд).',
   'платформа админ организации тенанты журнал роли SaaS')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and category='Платформа');
