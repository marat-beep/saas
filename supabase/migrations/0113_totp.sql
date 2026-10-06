-- ============================================================
-- 3DMP Service · 0113_totp.sql  (v101 — Итерация 8: 2FA/TOTP)
-- Двухфакторная аутентификация (RFC 6238, SHA1, 6 цифр, 30 c) для админов/владельцев.
-- app_login требует код, если у учётной записи включена 2FA.
-- Идемпотентно. Зависит от 0001..0112.
-- ============================================================

alter table public.app_users
  add column if not exists totp_secret text,
  add column if not exists totp_enabled boolean not null default false;

-- ---------- Base32 ----------
create or replace function public.app_base32_decode(p_b32 text)
returns bytea
language plpgsql immutable
as $$
declare const text := 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
        s text; i int; c text; v int; buf bigint := 0; bits int := 0; out bytea := ''::bytea;
begin
  s := regexp_replace(upper(coalesce(p_b32,'')), '[^A-Z2-7]', '', 'g');
  for i in 1..length(s) loop
    c := substr(s, i, 1);
    v := position(c in const) - 1;
    if v < 0 then continue; end if;
    buf := (buf << 5) | v; bits := bits + 5;
    if bits >= 8 then bits := bits - 8; out := out || set_byte('\x00'::bytea, 0, ((buf >> bits) & 255)::int); end if;
  end loop;
  return out;
end $$;

create or replace function public.app_base32_encode(p bytea)
returns text
language plpgsql immutable
as $$
declare const text := 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
        out text := ''; buf bigint := 0; bits int := 0; i int; b int;
begin
  for i in 0..octet_length(p) - 1 loop
    b := get_byte(p, i); buf := (buf << 8) | b; bits := bits + 8;
    while bits >= 5 loop bits := bits - 5; out := out || substr(const, ((buf >> bits) & 31)::int + 1, 1); end loop;
  end loop;
  if bits > 0 then out := out || substr(const, ((buf << (5 - bits)) & 31)::int + 1, 1); end if;
  return out;
end $$;

-- ---------- TOTP ----------
create or replace function public.app_totp_code(p_secret text, p_step bigint)
returns text
language plpgsql immutable
as $$
declare key bytea; mac bytea; off int; bin bigint;
begin
  key := public.app_base32_decode(p_secret);
  mac := extensions.hmac(int8send(p_step), key, 'sha1');
  off := get_byte(mac, 19) & 15;
  bin := ((get_byte(mac, off) & 127)::bigint << 24) | (get_byte(mac, off + 1)::bigint << 16)
       | (get_byte(mac, off + 2)::bigint << 8) | get_byte(mac, off + 3)::bigint;
  return lpad((bin % 1000000)::text, 6, '0');
end $$;

create or replace function public.app_totp_verify(p_secret text, p_code text)
returns boolean
language plpgsql immutable
as $$
declare step bigint := floor(extract(epoch from now()) / 30)::bigint; i int;
begin
  if p_secret is null or p_code is null or length(trim(p_code)) <> 6 then return false; end if;
  for i in -1..1 loop
    if public.app_totp_code(p_secret, step + i) = trim(p_code) then return true; end if;
  end loop;
  return false;
end $$;

-- ---------- Управление 2FA ----------
create or replace function public.app_2fa_status(p_token uuid)
returns table (enabled boolean, configured boolean)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.uid into uid from public.app_session_user(p_token) s;
  return query select coalesce(u.totp_enabled,false), (u.totp_secret is not null) from public.app_users u where u.id = uid;
end $$;

create or replace function public.app_2fa_setup(p_token uuid)
returns table (secret text, uri text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ulogin text; sec text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  sec := public.app_base32_encode(extensions.gen_random_bytes(20));
  update public.app_users set totp_secret = sec, totp_enabled = false where id = uid;
  return query select sec, 'otpauth://totp/3DMP:' || coalesce(ulogin,'user') || '?secret=' || sec || '&issuer=3DMP&algorithm=SHA1&digits=6&period=30';
end $$;

create or replace function public.app_2fa_enable(p_token uuid, p_code text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; sec text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.uid into uid from public.app_session_user(p_token) s;
  select u.totp_secret into sec from public.app_users u where u.id = uid;
  if sec is null then return query select false,'Сначала создайте секрет (Настроить)'; return; end if;
  if not public.app_totp_verify(sec, p_code) then return query select false,'Неверный код'; return; end if;
  update public.app_users set totp_enabled = true where id = uid;
  return query select true,'Двухфакторная аутентификация включена';
end $$;

create or replace function public.app_2fa_disable(p_token uuid, p_code text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; sec text; en boolean;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.uid into uid from public.app_session_user(p_token) s;
  select u.totp_secret, u.totp_enabled into sec, en from public.app_users u where u.id = uid;
  if not en then return query select false,'2FA не включена'; return; end if;
  if not public.app_totp_verify(sec, p_code) then return query select false,'Неверный код'; return; end if;
  update public.app_users set totp_enabled = false, totp_secret = null where id = uid;
  return query select true,'Двухфакторная аутентификация отключена';
end $$;

grant execute on function public.app_2fa_status(uuid) to anon, authenticated;
grant execute on function public.app_2fa_setup(uuid) to anon, authenticated;
grant execute on function public.app_2fa_enable(uuid,text) to anon, authenticated;
grant execute on function public.app_2fa_disable(uuid,text) to anon, authenticated;

-- ---------- app_login с проверкой 2FA ----------
drop function if exists public.app_login(text, text);
create or replace function public.app_login(p_login text, p_password text, p_code text default null)
returns table (token uuid, user_id uuid, login text, full_name text, role text, ok boolean, message text)
language plpgsql security definer set search_path = public, extensions
as $$
#variable_conflict use_column
declare u public.app_users; tk uuid; maxf constant int := 5; lockwin constant interval := interval '15 minutes';
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
  update public.app_users set last_login_at = now(), failed_attempts = 0, locked_until = null where id = u.id;
  insert into public.app_login_attempts (login, success) values (u.login, true);
  insert into public.app_events (user_id, login, action, detail) values (u.id, u.login, 'Вход', 'успешный вход');
  insert into public.app_sessions (user_id) values (u.id) returning app_sessions.token into tk;
  return query select tk, u.id, u.login, u.full_name, u.role, true, 'OK';
end $$;
grant execute on function public.app_login(text, text, text) to anon, authenticated;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Безопасность','Двухфакторная аутентификация (2FA/TOTP)',
   'В кабинете включите 2FA: «Настроить» создаёт секрет и otpauth-ссылку для приложения-аутентификатора (Google Authenticator/Authy), затем введите 6-значный код — 2FA включится. При включённой 2FA вход требует код (поле «Код 2FA») помимо пароля. Отключение — по коду. Реализация: app_2fa_setup/enable/disable, проверка app_totp_verify (RFC 6238, SHA1, 30 c, ±1 окно).',
   'безопасность 2FA TOTP двухфакторная authenticator app_2fa_setup app_totp_verify')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Двухфакторная аутентификация (2FA/TOTP)');
