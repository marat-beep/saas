-- ============================================================
-- 3DMP Service · 0003_seed_users.sql
-- Демо-пользователи и роли.
-- Применение: Supabase → SQL Editor → вставить целиком → Run.
-- Требует предварительно применённую 0001_init.sql (profiles/tenants/memberships).
-- Схемы gravirovka / norms_* не затрагивает.
--
-- Демо-аккаунты (пароль можно сменить в Authentication → Users):
--   owner@3dmp.ru    / Owner12345     — собственник (role: owner)
--   manager@3dmp.ru  / Manager12345   — менеджер закупок (role: manager)
--   supplier@3dmp.ru / Supplier12345  — поставщик (role: supplier)
-- ============================================================

-- ---------- 1. Роль в профиле ----------
alter table public.profiles add column if not exists role text not null default 'member';

-- ---------- 2. Пользователи (auth.users + auth.identities) ----------
create extension if not exists pgcrypto with schema extensions;

do $$
declare
  rec  record;
  uid  uuid;
begin
  for rec in
    select * from (values
      ('11111111-1111-1111-1111-111111111111'::uuid, 'owner@3dmp.ru',    'Owner12345',    'Собственник 3DMP',   'owner'),
      ('22222222-2222-2222-2222-222222222222'::uuid, 'manager@3dmp.ru',  'Manager12345',  'Менеджер закупок',   'manager'),
      ('33333333-3333-3333-3333-333333333333'::uuid, 'supplier@3dmp.ru', 'Supplier12345', 'Поставщик Демо',     'supplier')
    ) as t(id, email, pass, name, role)
  loop
    uid := rec.id;

    -- auth.users
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password,
      email_confirmed_at, created_at, updated_at,
      raw_app_meta_data, raw_user_meta_data,
      confirmation_token, recovery_token, email_change_token_new, email_change
    ) values (
      '00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated', rec.email,
      extensions.crypt(rec.pass, extensions.gen_salt('bf')),
      now(), now(), now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      jsonb_build_object('full_name', rec.name),
      '', '', '', ''
    )
    on conflict (id) do update
      set encrypted_password = excluded.encrypted_password,
          email_confirmed_at = now(),
          updated_at = now();

    -- auth.identities (email-провайдер)
    insert into auth.identities (
      id, user_id, provider_id, identity_data, provider,
      last_sign_in_at, created_at, updated_at
    ) values (
      gen_random_uuid(), uid, uid::text,
      jsonb_build_object('sub', uid::text, 'email', rec.email, 'email_verified', true),
      'email', now(), now(), now()
    )
    on conflict do nothing;

    -- профиль (создаётся триггером 0001; дополняем поля)
    update public.profiles
       set role = rec.role,
           full_name = rec.name,
           email = rec.email
     where id = uid;
  end loop;
end $$;

-- ---------- 3. Демо-организация и членство с ролями ----------
insert into public.tenants (id, name, slug, plan, status)
values ('aaaaaaaa-0000-0000-0000-000000000001', '3DMP Демо', '3dmp-demo', 'business', 'active')
on conflict (id) do nothing;

insert into public.memberships (tenant_id, user_id, role)
values
  ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'owner'),
  ('aaaaaaaa-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', 'admin')
on conflict (tenant_id, user_id) do update set role = excluded.role;

-- ---------- 4. Проверка ----------
select p.email, p.full_name, p.role,
       coalesce(string_agg(m.role, ', '), '—') as memberships
from public.profiles p
left join public.memberships m on m.user_id = p.id
where p.id in (
  '11111111-1111-1111-1111-111111111111',
  '22222222-2222-2222-2222-222222222222',
  '33333333-3333-3333-3333-333333333333'
)
group by p.email, p.full_name, p.role
order by p.email;
