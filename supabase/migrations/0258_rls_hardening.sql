-- ============================================================
-- 3DMP Service · 0258_rls_hardening.sql  (PROP-03 — харденинг RLS и прав)
-- Порталу закупок достаточно ЧТЕНИЯ public.tenders; запись — только через RPC
-- (SECURITY DEFINER, владелец обходит RLS). Прямая запись anon/authenticated
-- закрыта на уровне прав таблицы + ограничительных политик (defense-in-depth).
-- Прочие таблицы (app_*) — default-deny (политик нет). Идемпотентно.
-- ============================================================

alter table public.tenders enable row level security;
alter table public.profiles enable row level security;

-- Права таблиц: только чтение для клиента (запись — через RPC).
revoke insert, update, delete on public.tenders from anon, authenticated;
revoke insert, update, delete on public.profiles from anon, authenticated;
grant select on public.tenders to anon, authenticated;

-- Записи через клиент — запрещены явно (defense-in-depth на случай ослабления прав).
drop policy if exists tenders_insert on public.tenders;
create policy tenders_insert on public.tenders for insert to authenticated with check (false);
drop policy if exists tenders_update_own on public.tenders;
create policy tenders_update_own on public.tenders for update to authenticated using (false);
drop policy if exists profiles_self_insert on public.profiles;
create policy profiles_self_insert on public.profiles for insert to authenticated with check (false);
drop policy if exists profiles_self_update on public.profiles;
create policy profiles_self_update on public.profiles for update to authenticated using (false);

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select null, v.category, v.question, v.answer, v.tags
from (values
  ('Безопасность','Запись в закупки и профили — только через RPC',
   'Таблицы tenders и profiles: клиенту (anon/authenticated) доступно только чтение (открытые закупки/свой профиль). Любые записи идут через RPC (SECURITY DEFINER) с проверкой прав и тенанта; прямая запись запрещена правами таблицы и ограничительными политиками. Таблицы app_* доступны только через RPC (default-deny: политик нет).',
   'безопасность RLS tenders profiles grant default-deny закупки портал')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge k where k.question=v.question);
