-- ============================================================
-- 3DMP Service · 0213_import_feed.sql
-- Массовый импорт пользователей (CSV → jsonb) и лента активности организации.
-- Идемпотентно. Зависит от 0001..0212.
-- ============================================================

create or replace function public.app_tenant_users_import(p_token uuid, p_rows jsonb)
returns table (ok boolean, message text, created integer, failed integer, errors jsonb)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare rec record; okb boolean; msgb text; c integer := 0; f integer := 0; errs jsonb := '[]'::jsonb; lg text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён',0,0,'[]'::jsonb; return; end if;
  if not (public.app_is_owner(p_token) or public.app_is_platform_admin(p_token) or public.app_can_edit(p_token,'org')) then
    return query select false,'Нет прав (нужны владелец/администратор)',0,0,'[]'::jsonb; return;
  end if;
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then return query select false,'Ожидается массив строк',0,0,'[]'::jsonb; return; end if;
  for rec in select value as e from jsonb_array_elements(p_rows) loop
    lg := nullif(trim(coalesce(rec.e->>'login','')), '');
    if lg is null then errs := errs || to_jsonb('(пустой логин)'); f := f + 1; continue; end if;
    select x.ok, x.message into okb, msgb
      from public.app_tenant_user_create(p_token, lg, coalesce(rec.e->>'password',''), nullif(trim(rec.e->>'full_name'),''), coalesce(nullif(trim(rec.e->>'role'),''),'manager')) x;
    if okb then c := c + 1; else f := f + 1; errs := errs || to_jsonb(lg || ': ' || coalesce(msgb,'')); end if;
  end loop;
  return query select (f = 0), 'Создано: ' || c || ', ошибок: ' || f, c, f, errs;
end $$;

create or replace function public.app_activity_feed(p_token uuid, p_limit integer default 30)
returns table (kind text, title text, subtitle text, link text, at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid; uid uuid; lim integer;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  select s.uid into uid from public.app_session_user(p_token) s;
  lim := greatest(least(coalesce(p_limit,30), 200), 1);
  return query
    select n.kind, n.title, n.subtitle, n.link, n.at from (
      select 'notif'::text as kind, x.title, x.body as subtitle, x.link, x.created_at as at
        from public.app_notifications x where x.user_id = uid
      union all
      select 'event'::text, e.action, e.detail, null::text, e.created_at
        from public.app_events e left join public.app_users u on u.id = e.user_id
       where (adm or u.tenant_id = ten)
    ) n
    order by n.at desc
    limit lim;
end $$;

-- ================= База знаний =================
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Платформа','Импорт пользователей и лента активности (0213)',
   'Массовый импорт пользователей: app_tenant_users_import(token, [{login,password,full_name,role}]) — создаёт через app_tenant_user_create, возвращает created/failed/errors. Лента активности: app_activity_feed(token, limit) — объединяет уведомления пользователя и события организации (app_events по пользователям тенанта).',
   'импорт пользователей CSV лента активности feed события уведомления')
) as v(category,question,answer,tags)
where not exists (
  select 1 from public.app_knowledge
   where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001'
     and question = 'Импорт пользователей и лента активности (0213)'
);

-- ================= Права =================
grant execute on function public.app_tenant_users_import(uuid,jsonb) to anon, authenticated;
grant execute on function public.app_activity_feed(uuid,integer) to anon, authenticated;
