-- ============================================================
-- 3DMP Service · 0116_announcements.sql  (W1 — Объявления и плановые тех.работы)
-- Объявления платформы (tenant_id NULL) и организации: баннер на главной,
-- управление для admin/owner, рассылка уведомлений о плановых тех.работах.
-- Идемпотентно. Зависит от 0001..0115.
-- ============================================================

create table if not exists public.app_announcements (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id) on delete cascade,
  kind          text not null default 'info',           -- info | maintenance | release | critical
  title         text not null,
  body          text,
  url           text,
  starts_at     timestamptz not null default now(),
  ends_at       timestamptz,
  active        boolean not null default true,
  pinned        boolean not null default false,
  notified_at   timestamptz,
  created_by    uuid,
  created_login text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists app_announcements_active_idx on public.app_announcements (active, starts_at desc);

create table if not exists public.app_announcement_reads (
  id              uuid primary key default gen_random_uuid(),
  announcement_id uuid not null references public.app_announcements (id) on delete cascade,
  login           text not null,
  read_at         timestamptz not null default now(),
  unique (announcement_id, login)
);
create index if not exists app_announcement_reads_login_idx on public.app_announcement_reads (login);

alter table public.app_announcements      enable row level security;
alter table public.app_announcement_reads enable row level security;

-- ------------------------------------------------------------
-- Рассылка уведомлений о плановых тех.работах (kind=maintenance)
-- в окне p_hours до начала. Однократно (notified_at). Вызывается из active.
-- ------------------------------------------------------------
drop function if exists public.app_announcements_scan(uuid, integer);
create or replace function public.app_announcements_scan(p_token uuid, p_hours integer default 24)
returns integer
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ten uuid; r record; n integer := 0;
begin
  select s.uid into uid from public.app_session_user(p_token) s;
  if uid is null then return 0; end if;
  ten := public.app_my_tenant(p_token);
  for r in
    select a.id, a.tenant_id, a.title, a.body
      from public.app_announcements a
     where a.active and a.kind = 'maintenance' and a.notified_at is null
       and a.starts_at > now()
       and a.starts_at <= now() + make_interval(hours => greatest(1, least(coalesce(p_hours, 24), 168)))
       and (a.tenant_id is null or a.tenant_id = ten)
  loop
    perform public.app_notif_roles_t(r.tenant_id,
      array['admin','owner','manager','director','chief','master','technologist','operator','supply','qc','economist','support'],
      'Плановые тех.работы: ' || r.title,
      coalesce(nullif(r.body, ''), 'Плановые технические работы. Сохраните работу заранее.'),
      'index.html');
    update public.app_announcements set notified_at = now() where id = r.id;
    n := n + 1;
  end loop;
  return n;
end $$;

-- ------------------------------------------------------------
-- Активные объявления для текущего пользователя (баннер на главной).
-- ------------------------------------------------------------
drop function if exists public.app_announcements_active(uuid);
create or replace function public.app_announcements_active(p_token uuid)
returns table (id uuid, kind text, title text, body text, url text, starts_at timestamptz, ends_at timestamptz,
               pinned boolean, is_read boolean, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ulogin text; ten uuid;
begin
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token);
  perform public.app_announcements_scan(p_token);
  return query
    select a.id, a.kind, a.title, a.body, a.url, a.starts_at, a.ends_at, a.pinned,
           exists (select 1 from public.app_announcement_reads r
                    where r.announcement_id = a.id and r.login = ulogin) as is_read,
           a.created_at
      from public.app_announcements a
     where a.active
       and a.starts_at <= now()
       and (a.ends_at is null or a.ends_at >= now())
       and (a.tenant_id is null or a.tenant_id = ten)
     order by (a.kind = 'critical') desc, a.pinned desc, a.starts_at desc
     limit 20;
end $$;

-- ------------------------------------------------------------
-- Список всех объявлений для управления (admin — платформа+все, owner — свой тенант).
-- ------------------------------------------------------------
drop function if exists public.app_announcements_all(uuid);
create or replace function public.app_announcements_all(p_token uuid)
returns table (id uuid, tenant_id uuid, tenant_name text, scope text, kind text, title text, body text, url text,
               starts_at timestamptz, ends_at timestamptz, active boolean, pinned boolean,
               notified_at timestamptz, reads integer, reached boolean, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; urole text; ten uuid;
begin
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Сессия недействительна'; end if;
  if urole not in ('admin', 'owner') then raise exception 'Нет прав на управление объявлениями'; end if;
  ten := public.app_my_tenant(p_token);
  return query
    select a.id, a.tenant_id, t.name,
           case when a.tenant_id is null then 'platform' else 'tenant' end,
           a.kind, a.title, a.body, a.url, a.starts_at, a.ends_at, a.active, a.pinned, a.notified_at,
           (select count(*)::int from public.app_announcement_reads r where r.announcement_id = a.id),
           (a.active and a.starts_at <= now() and (a.ends_at is null or a.ends_at >= now())),
           a.created_at
      from public.app_announcements a
      left join public.tenants t on t.id = a.tenant_id
     where (urole = 'admin') or (a.tenant_id = ten)
     order by a.created_at desc;
end $$;

-- ------------------------------------------------------------
-- Сохранить объявление (создание/правка). admin — платформа и тенанты, owner — свой тенант.
-- ------------------------------------------------------------
drop function if exists public.app_announcement_save(uuid,uuid,text,text,text,text,timestamptz,timestamptz,boolean,boolean,uuid);
create or replace function public.app_announcement_save(
  p_token uuid, p_id uuid, p_kind text, p_title text, p_body text, p_url text,
  p_starts_at timestamptz, p_ends_at timestamptz, p_active boolean, p_pinned boolean,
  p_tenant_id uuid default null
) returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ulogin text; urole text; ten uuid; aid uuid; tgt uuid;
begin
  select s.uid, s.ulogin, s.urole into uid, ulogin, urole from public.app_session_user(p_token) s;
  if uid is null then return query select false, 'Сессия недействительна', null::uuid; return; end if;
  if urole not in ('admin', 'owner') then return query select false, 'Нет прав на управление объявлениями', null::uuid; return; end if;
  if coalesce(trim(p_title), '') = '' then return query select false, 'Укажите заголовок', null::uuid; return; end if;
  if p_kind is not null and p_kind not in ('info','maintenance','release','critical') then
    return query select false, 'Неизвестный тип объявления', null::uuid; return;
  end if;
  ten := public.app_my_tenant(p_token);
  if urole = 'admin' then tgt := p_tenant_id; else tgt := ten; end if;

  if p_id is null then
    insert into public.app_announcements
      (tenant_id, kind, title, body, url, starts_at, ends_at, active, pinned, created_by, created_login)
    values
      (tgt, coalesce(nullif(trim(p_kind), ''), 'info'), trim(p_title), nullif(trim(p_body), ''), nullif(trim(p_url), ''),
       coalesce(p_starts_at, now()), p_ends_at, coalesce(p_active, true), coalesce(p_pinned, false), uid, ulogin)
    returning app_announcements.id into aid;
    return query select true, 'Объявление опубликовано', aid;
  else
    update public.app_announcements a
       set kind = coalesce(nullif(trim(p_kind), ''), a.kind),
           title = trim(p_title),
           body = nullif(trim(p_body), ''),
           url = nullif(trim(p_url), ''),
           starts_at = coalesce(p_starts_at, a.starts_at),
           ends_at = p_ends_at,
           active = coalesce(p_active, a.active),
           pinned = coalesce(p_pinned, a.pinned),
           tenant_id = tgt,
           updated_at = now()
     where a.id = p_id and (urole = 'admin' or a.tenant_id = ten);
    if not found then return query select false, 'Объявление не найдено', null::uuid; return; end if;
    return query select true, 'Объявление сохранено', p_id;
  end if;
exception when others then
  return query select false, sqlerrm, null::uuid;
end $$;

-- ------------------------------------------------------------
-- Удалить объявление.
-- ------------------------------------------------------------
drop function if exists public.app_announcement_delete(uuid,uuid);
create or replace function public.app_announcement_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; urole text; ten uuid;
begin
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  if uid is null then return query select false, 'Сессия недействительна'; return; end if;
  if urole not in ('admin', 'owner') then return query select false, 'Нет прав на управление объявлениями'; return; end if;
  ten := public.app_my_tenant(p_token);
  delete from public.app_announcements a
   where a.id = p_id and (urole = 'admin' or a.tenant_id = ten);
  if not found then return query select false, 'Объявление не найдено'; return; end if;
  return query select true, 'Объявление удалено';
end $$;

-- ------------------------------------------------------------
-- Отметить объявление прочитанным для текущего пользователя.
-- ------------------------------------------------------------
drop function if exists public.app_announcement_read(uuid,uuid);
create or replace function public.app_announcement_read(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ulogin text; ten uuid; ok_vis boolean;
begin
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  if uid is null then return query select false, 'Сессия недействительна'; return; end if;
  ten := public.app_my_tenant(p_token);
  select true into ok_vis from public.app_announcements a
   where a.id = p_id and (a.tenant_id is null or a.tenant_id = ten);
  if ok_vis is null then return query select false, 'Объявление не найдено'; return; end if;
  insert into public.app_announcement_reads (announcement_id, login)
  values (p_id, ulogin)
  on conflict (announcement_id, login) do nothing;
  return query select true, 'Отмечено прочитанным';
end $$;

grant execute on function public.app_announcements_scan(uuid,integer)          to anon, authenticated;
grant execute on function public.app_announcements_active(uuid)                to anon, authenticated;
grant execute on function public.app_announcements_all(uuid)                   to anon, authenticated;
grant execute on function public.app_announcement_save(uuid,uuid,text,text,text,text,timestamptz,timestamptz,boolean,boolean,uuid) to anon, authenticated;
grant execute on function public.app_announcement_delete(uuid,uuid)            to anon, authenticated;
grant execute on function public.app_announcement_read(uuid,uuid)              to anon, authenticated;

-- ---------- Демо-данные (тенант A) ----------
insert into public.app_announcements (tenant_id, kind, title, body, url, starts_at, ends_at, active, pinned)
select 'aaaaaaaa-0000-0000-0000-000000000001', 'info', 'Добро пожаловать в 3DMP Service',
       'Объявления платформы и организации показываются в баннере на главной. Управление — в модуле «Объявления» (admin/owner).',
       'index.html', now() - interval '1 day', null, true, true
where not exists (
  select 1 from public.app_announcements
   where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001' and title = 'Добро пожаловать в 3DMP Service'
);

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Платформа','Объявления и плановые тех.работы',
   'Модуль «Объявления»: admin/owner публикуют объявления платформы (tenant_id NULL) или организации. Типы: info, maintenance (плановые тех.работы), release, critical. Активные объявления (starts_at <= сейчас <= ends_at) показываются в баннере на главной с приоритетом critical/pinned; прочтение фиксируется (app_announcement_read). Для плановых тех.работ (kind=maintenance) за 24 часа до начала автоматически рассылаются уведомления в колокольчик (app_announcements_scan, однократно). RPC: app_announcements_active/all/save/delete/read.',
   'объявления announcements баннер техработы maintenance уведомления колокольчик платформа')
) as v(category,question,answer,tags)
where not exists (
  select 1 from public.app_knowledge
   where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001' and question = 'Объявления и плановые тех.работы'
);
