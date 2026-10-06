-- ============================================================
-- 3DMP Service · 0104_demo_support_user.sql  (v88 — демо-пользователь роли support)
-- Роль support (Support Desk) существовала в матрице прав, но без логина.
-- Добавляем демо-доступ support/support (тенант A). Идемпотентно. Зависит от 0001..0103.
-- ============================================================

insert into public.app_users (login, password_hash, full_name, role, tenant_id)
values ('support', extensions.crypt('support', extensions.gen_salt('bf')), 'Служба поддержки', 'support',
        'aaaaaaaa-0000-0000-0000-000000000001')
on conflict (login) do update
  set role = excluded.role, tenant_id = excluded.tenant_id, full_name = excluded.full_name;
