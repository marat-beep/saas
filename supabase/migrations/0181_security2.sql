-- ============================================================
-- 3DMP Service · 0181_security2.sql  (план v4, W39 «Безопасность/аудит 2.0»)
-- Политики безопасности, смена пароля, «мои устройства/сессии», журнал доступа.
-- 2FA/TOTP и login-guard уже есть (0112/0113). Идемпотентно. Зависит от 0001..0180.
-- ============================================================

-- ---------- Расширение учётных записей и сессий ----------
alter table public.app_users
  add column if not exists password_changed_at timestamptz,
  add column if not exists must_change_password boolean not null default false;

alter table public.app_sessions
  add column if not exists device text,
  add column if not exists ip text,
  add column if not exists ua text,
  add column if not exists last_seen timestamptz not null default now();

-- ---------- Политики безопасности (по тенанту) ----------
create table if not exists public.app_security_policies (
  tenant_id         uuid primary key,
  require_2fa_roles text[] not null default '{}',
  pwd_min_len       int not null default 8,
  pwd_expire_days   int not null default 0,
  session_ttl_min   int not null default 0,
  ip_allowlist      text,
  updated_at        timestamptz not null default now()
);
alter table public.app_security_policies enable row level security;

-- ---------- Политика: чтение ----------
create or replace function public.app_security_policy_get(p_token uuid)
returns table (require_2fa_roles text[], pwd_min_len int, pwd_expire_days int, session_ttl_min int, ip_allowlist text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token);
  return query
    select coalesce(p.require_2fa_roles, '{}'), coalesce(p.pwd_min_len, 8), coalesce(p.pwd_expire_days, 0),
           coalesce(p.session_ttl_min, 0), p.ip_allowlist
      from (select 1) x
      left join public.app_security_policies p on p.tenant_id = ten;
end $$;

-- ---------- Политика: запись (admin/owner) ----------
create or replace function public.app_security_policy_set(p_token uuid, p_require_2fa_roles text[], p_pwd_min_len int,
  p_pwd_expire_days int, p_session_ttl_min int, p_ip_allowlist text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  if urole not in ('admin','owner') then return query select false,'Доступно администратору/владельцу'; return; end if;
  ten := public.app_my_tenant(p_token);
  insert into public.app_security_policies (tenant_id, require_2fa_roles, pwd_min_len, pwd_expire_days, session_ttl_min, ip_allowlist, updated_at)
  values (ten, coalesce(p_require_2fa_roles,'{}'), greatest(coalesce(p_pwd_min_len,8),4), greatest(coalesce(p_pwd_expire_days,0),0),
          greatest(coalesce(p_session_ttl_min,0),0), nullif(trim(p_ip_allowlist),''), now())
  on conflict (tenant_id) do update set
    require_2fa_roles = excluded.require_2fa_roles, pwd_min_len = excluded.pwd_min_len,
    pwd_expire_days = excluded.pwd_expire_days, session_ttl_min = excluded.session_ttl_min,
    ip_allowlist = excluded.ip_allowlist, updated_at = now();
  perform public.app_log_event(p_token, 'Политика безопасности изменена', 'pwd_min_len=' || greatest(coalesce(p_pwd_min_len,8),4));
  return query select true, 'Политика безопасности сохранена';
end $$;

-- ---------- Моя безопасность ----------
create or replace function public.app_my_security(p_token uuid)
returns table (totp_enabled boolean, totp_configured boolean, must_change_password boolean, password_changed_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.uid into uid from public.app_session_user(p_token) s;
  return query select coalesce(u.totp_enabled,false), (u.totp_secret is not null),
                      coalesce(u.must_change_password,false), u.password_changed_at
    from public.app_users u where u.id = uid;
end $$;

-- ---------- Смена пароля ----------
create or replace function public.app_password_change(p_token uuid, p_old text, p_new text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public, extensions
as $$
#variable_conflict use_column
declare uid uuid; ulogin text; ten uuid; ph text; minlen int; nph text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  if uid is null then return query select false,'Сессия недействительна'; return; end if;
  select u.password_hash, u.tenant_id into ph, ten from public.app_users u where u.id = uid;
  if ph is null or ph <> extensions.crypt(p_old, ph) then return query select false,'Неверный текущий пароль'; return; end if;
  select coalesce(p.pwd_min_len, 8) into minlen from (select 1) x left join public.app_security_policies p on p.tenant_id = ten;
  minlen := greatest(coalesce(minlen,8), 4);
  if p_new is null or length(p_new) < minlen then return query select false, 'Пароль короче минимальной длины (' || minlen || ')'; return; end if;
  if p_new = p_old then return query select false,'Новый пароль совпадает с текущим'; return; end if;
  nph := extensions.crypt(p_new, extensions.gen_salt('bf', 10));
  update public.app_users set password_hash = nph, password_changed_at = now(), must_change_password = false,
         failed_attempts = 0, locked_until = null where id = uid;
  perform public.app_log_event(p_token, 'Смена пароля', 'пароль изменён пользователем');
  return query select true, 'Пароль изменён';
end $$;

-- ---------- Мои устройства/сессии ----------
create or replace function public.app_my_sessions(p_token uuid)
returns table (session_id uuid, device text, ip text, ua text, created_at timestamptz, last_seen timestamptz, expires_at timestamptz, current boolean)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.uid into uid from public.app_session_user(p_token) s;
  return query
    select se.token, se.device, se.ip, se.ua, se.created_at, se.last_seen, se.expires_at, (se.token = p_token)
      from public.app_sessions se where se.user_id = uid order by se.last_seen desc;
end $$;

create or replace function public.app_session_revoke(p_token uuid, p_session uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.uid into uid from public.app_session_user(p_token) s;
  delete from public.app_sessions where token = p_session and user_id = uid;
  if not found then return query select false,'Сессия не найдена'; return; end if;
  perform public.app_log_event(p_token, 'Завершение сессии', 'устройство отключено');
  return query select true,'Сессия завершена';
end $$;

create or replace function public.app_session_revoke_all(p_token uuid)
returns table (ok boolean, message text, cnt integer)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; n int;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён',0; return; end if;
  select s.uid into uid from public.app_session_user(p_token) s;
  with del as (delete from public.app_sessions where user_id = uid and token <> p_token returning 1)
  select count(*) into n from del;
  perform public.app_log_event(p_token, 'Завершение сессий', 'прочие устройства: ' || n);
  return query select true, 'Завершены прочие сессии', n;
end $$;

create or replace function public.app_session_touch(p_token uuid, p_device text, p_ua text)
returns void language sql security definer set search_path = public
as $$
  update public.app_sessions set last_seen = now(),
         device = coalesce(nullif(trim(p_device),''), device),
         ua = coalesce(nullif(trim(p_ua),''), ua)
   where token = p_token;
$$;

-- ---------- Журнал доступа ----------
create or replace function public.app_access_log_list(p_token uuid, p_limit integer default 100)
returns table (src text, login text, action text, detail text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ulogin text; lim int;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  if urole <> 'admin' then raise exception 'Доступно администратору платформы'; end if;
  lim := greatest(1, least(coalesce(p_limit,100), 500));
  return query
    (select 'вход'::text, a.login, case when a.success then 'Успех' else 'Отказ' end, null::text, a.created_at
       from public.app_login_attempts a order by a.created_at desc limit lim)
    union all
    (select 'действие'::text, e.login, e.action, e.detail, e.created_at
       from public.app_events e order by e.created_at desc limit lim)
    order by created_at desc limit lim;
end $$;

-- ---------- app_login: TTL сессии по политике + срок пароля ----------
drop function if exists public.app_login(text, text, text);
create or replace function public.app_login(p_login text, p_password text, p_code text default null)
returns table (token uuid, user_id uuid, login text, full_name text, role text, ok boolean, message text)
language plpgsql security definer set search_path = public, extensions
as $$
#variable_conflict use_column
declare u public.app_users; tk uuid; maxf constant int := 5; lockwin constant interval := interval '15 minutes';
        ttl int; exp_days int; must_ch boolean := false;
begin
  select * into u from public.app_users au where lower(au.login) = lower(trim(p_login)) and au.active limit 1;
  if u.id is null then
    insert into public.app_login_attempts (login, success) values (lower(trim(p_login)), false);
    return query select null::uuid, null::uuid, null::text, null::text, null::text, false, 'Неверный логин или пароль';
    return;
  end if;
  if u.locked_until is not null and u.locked_until > now() then
    insert into public.app_login_attempts (login, success) values (u.login, false);
    return query select null::uuid, u.id, u.login, u.full_name, u.role, false,
      'Вход временно заблокирован до ' || to_char(u.locked_until, 'DD.MM HH24:MI');
    return;
  end if;
  if u.password_hash <> extensions.crypt(p_password, u.password_hash) then
    update public.app_users
       set failed_attempts = u.failed_attempts + 1,
           locked_until = case when u.failed_attempts + 1 >= maxf then now() + lockwin else u.locked_until end
     where id = u.id;
    insert into public.app_login_attempts (login, success) values (u.login, false);
    if u.failed_attempts + 1 >= maxf then
      return query select null::uuid, u.id, u.login, u.full_name, u.role, false,
        'Превышено число попыток. Вход заблокирован на 15 минут.';
    else
      return query select null::uuid, u.id, u.login, u.full_name, u.role, false,
        'Неверный логин или пароль (попытка ' || (u.failed_attempts + 1)::text || ' из ' || maxf::text || ')';
    end if;
    return;
  end if;
  if u.totp_enabled then
    if p_code is null or trim(p_code) = '' then
      insert into public.app_login_attempts (login, success) values (u.login, false);
      return query select null::uuid, u.id, u.login, u.full_name, u.role, false, 'Требуется код двухфакторной аутентификации';
      return;
    end if;
    if not public.app_totp_verify(u.totp_secret, p_code) then
      insert into public.app_login_attempts (login, success) values (u.login, false);
      return query select null::uuid, u.id, u.login, u.full_name, u.role, false, 'Неверный код двухфакторной аутентификации';
      return;
    end if;
  end if;
  -- политика: TTL сессии и срок действия пароля
  select coalesce(p.session_ttl_min,0), coalesce(p.pwd_expire_days,0) into ttl, exp_days
    from (select 1) x left join public.app_security_policies p on p.tenant_id = u.tenant_id;
  if exp_days > 0 and (u.password_changed_at is null or u.password_changed_at < now() - (exp_days || ' days')::interval) then
    must_ch := true;
  end if;
  update public.app_users set last_login_at = now(), failed_attempts = 0, locked_until = null, must_change_password = must_ch where id = u.id;
  insert into public.app_login_attempts (login, success) values (u.login, true);
  insert into public.app_events (user_id, login, action, detail) values (u.id, u.login, 'Вход', 'успешный вход');
  insert into public.app_sessions (user_id, expires_at)
  values (u.id, case when ttl > 0 then now() + (ttl || ' minutes')::interval else now() + interval '30 days' end)
  returning app_sessions.token into tk;
  return query select tk, u.id, u.login, u.full_name, u.role, true, 'OK';
end $$;
grant execute on function public.app_login(text, text, text) to anon, authenticated;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Безопасность','Политики безопасности, смена пароля и мои устройства',
   'Админ-панель клиента → «Безопасность»: 2FA (настройка/включение/отключение), смена пароля (проверяется политика), список «Мои устройства/сессии» с завершением по одному или всех прочих. Администратор/владелец задаёт политику организации (app_security_policy_set): минимальная длина пароля, срок действия, TTL сессии, список IP. Журнал доступа (попытки входа и события) — app_access_log_list (администратор платформы). Функции: app_password_change, app_my_sessions, app_session_revoke(_all), app_session_touch, app_security_policy_get/set, app_access_log_list.',
   'безопасность политика пароль сессии устройства журнал доступ 2fa app_password_change app_my_sessions')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Политики безопасности, смена пароля и мои устройства');

-- ---------- Права ----------
grant execute on function public.app_security_policy_get(uuid) to anon, authenticated;
grant execute on function public.app_security_policy_set(uuid,text[],int,int,int,text) to anon, authenticated;
grant execute on function public.app_my_security(uuid) to anon, authenticated;
grant execute on function public.app_password_change(uuid,text,text) to anon, authenticated;
grant execute on function public.app_my_sessions(uuid) to anon, authenticated;
grant execute on function public.app_session_revoke(uuid,uuid) to anon, authenticated;
grant execute on function public.app_session_revoke_all(uuid) to anon, authenticated;
grant execute on function public.app_session_touch(uuid,text,text) to anon, authenticated;
grant execute on function public.app_access_log_list(uuid,integer) to anon, authenticated;
