-- ============================================================
-- 3DMP Service · 0072_scale.sql  (v50 — ЭПИК G: масштаб и эксплуатация)
-- Пагинация длинных списков, индексы, автотесты (смоук), журнал бэкапов,
-- статистика объёма БД. База знаний. Зависит от 0001..0071.
-- ============================================================

-- ---------- Индексы (производительность) ----------
create index if not exists app_orders_tenant_status_idx on public.app_orders (tenant_id, status, created_at desc);
create index if not exists app_naryads_tenant_status_idx on public.app_naryads (tenant_id, status);
create index if not exists app_stock_moves_tenant_idx on public.app_stock_moves (tenant_id, created_at desc);
create index if not exists app_notifications_unread_idx on public.app_notifications (user_id) where read_at is null;
create index if not exists app_documents_tenant_idx on public.app_documents (tenant_id, doc_type, created_at desc);
create index if not exists app_attachments_ref_idx on public.app_attachments (ref_type, ref_id);

-- ---------- Пагинация длинных списков ----------
create or replace function public.app_page_count(p_token uuid, p_kind text, p_q text default null)
returns bigint
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid; ulogin text; qq text; n bigint;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  if p_kind='orders' then
    select count(*) into n from public.app_orders o
      where (urole='admin' or o.tenant_id=ten) and (qq='' or lower(coalesce(o.number,'')||' '||coalesce(o.title,'')) like '%'||qq||'%');
  elsif p_kind='knowledge' then
    select count(*) into n from public.app_knowledge k
      where (k.tenant_id is null or urole='admin' or k.tenant_id=ten) and (qq='' or lower(k.question||' '||coalesce(k.tags,'')) like '%'||qq||'%');
  elsif p_kind='events' then
    select count(*) into n from public.app_events e
      where (urole='admin' or e.login=ulogin) and (qq='' or lower(coalesce(e.action,'')||' '||coalesce(e.detail,'')) like '%'||qq||'%');
  elsif p_kind='calc' then
    select count(*) into n from public.app_calc_saves c
      where (urole='admin' or c.tenant_id=ten) and (qq='' or lower(coalesce(c.title,'')||' '||coalesce(c.ref,'')) like '%'||qq||'%');
  else
    n := 0;
  end if;
  return n;
end $$;

create or replace function public.app_page_rows(p_token uuid, p_kind text, p_page int default 1, p_size int default 20, p_q text default null)
returns table (id uuid, title text, subtitle text, meta text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid; ulogin text; qq text; off int; lim int;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  lim := greatest(1, least(coalesce(p_size,20), 200));
  off := greatest(0, (greatest(coalesce(p_page,1),1)-1)*lim);
  return query
    select o.id, o.number, coalesce(o.title,''), o.status, o.created_at from public.app_orders o
      where p_kind='orders' and (urole='admin' or o.tenant_id=ten)
        and (qq='' or lower(coalesce(o.number,'')||' '||coalesce(o.title,'')) like '%'||qq||'%')
    union all
    select k.id, k.question, coalesce(k.category,''), left(coalesce(k.answer,''), 80), coalesce(k.created_at, now()) from public.app_knowledge k
      where p_kind='knowledge' and (k.tenant_id is null or urole='admin' or k.tenant_id=ten)
        and (qq='' or lower(k.question||' '||coalesce(k.tags,'')) like '%'||qq||'%')
    union all
    select e.id, e.action, coalesce(e.detail,''), coalesce(e.login,''), e.created_at from public.app_events e
      where p_kind='events' and (urole='admin' or e.login=ulogin)
        and (qq='' or lower(coalesce(e.action,'')||' '||coalesce(e.detail,'')) like '%'||qq||'%')
    union all
    select c.id, coalesce(c.title,'Расчёт'), c.kind, coalesce(c.ref,''), c.created_at from public.app_calc_saves c
      where p_kind='calc' and (urole='admin' or c.tenant_id=ten)
        and (qq='' or lower(coalesce(c.title,'')||' '||coalesce(c.ref,'')) like '%'||qq||'%')
    order by created_at desc
    limit lim offset off;
end $$;

-- ---------- Журнал бэкапов ----------
create table if not exists public.app_backup_log (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid references public.tenants (id),
  kind       text not null default 'manual', -- manual|auto|restore
  scope      text,
  note       text,
  by_login   text,
  created_at timestamptz not null default now()
);
create index if not exists app_backup_log_idx on public.app_backup_log (created_at desc);
alter table public.app_backup_log enable row level security;

create or replace function public.app_backup_note(p_token uuid, p_kind text, p_scope text, p_note text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid; urole text; ulogin text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  if urole <> 'admin' then return query select false,'Только администратор платформы'; return; end if;
  ten := public.app_my_tenant(p_token);
  insert into public.app_backup_log (tenant_id, kind, scope, note, by_login)
  values (ten, coalesce(nullif(trim(p_kind),''),'manual'), nullif(trim(p_scope),''), nullif(trim(p_note),''), ulogin);
  return query select true,'Запись о резервной копии добавлена';
end $$;

create or replace function public.app_backup_list(p_token uuid, p_limit int default 50)
returns table (id uuid, kind text, scope text, note text, by_login text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare urole text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  if urole <> 'admin' then raise exception 'Только администратор платформы'; end if;
  return query select b.id, b.kind, b.scope, b.note, b.by_login, b.created_at
    from public.app_backup_log b order by b.created_at desc limit greatest(1, least(coalesce(p_limit,50),200));
end $$;

-- ---------- Смоук-тест (автотесты) ----------
create or replace function public.app_smoke_test(p_token uuid)
returns table (name text, ok boolean, detail text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid; cnt bigint;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);

  name := 'Сессия и права'; ok := true; detail := 'роль='||coalesce(urole,'—')||', организация='||coalesce(ten::text,'—'); return next;

  begin
    execute 'select count(*) from public.app_users' into cnt;
    name := 'Таблица пользователей'; ok := cnt>0; detail := cnt||' пользователей'; return next;
  exception when others then name := 'Таблица пользователей'; ok := false; detail := sqlerrm; return next; end;

  begin
    execute 'select count(*) from public.app_orders where ($1 is null or tenant_id=$1)' into cnt using ten;
    name := 'Заявки'; ok := true; detail := cnt||' заявок'; return next;
  exception when others then name := 'Заявки'; ok := false; detail := sqlerrm; return next; end;

  begin
    execute 'select count(*) from public.app_naryads where ($1 is null or tenant_id=$1)' into cnt using ten;
    name := 'Наряды'; ok := true; detail := cnt||' нарядов'; return next;
  exception when others then name := 'Наряды'; ok := false; detail := sqlerrm; return next; end;

  begin
    execute 'select count(*) from public.app_materials where ($1 is null or tenant_id=$1)' into cnt using ten;
    name := 'Материалы'; ok := true; detail := cnt||' позиций'; return next;
  exception when others then name := 'Материалы'; ok := false; detail := sqlerrm; return next; end;

  begin
    execute 'select count(*) from public.app_knowledge where ($1 is null or tenant_id=$1 or tenant_id is null)' into cnt using ten;
    name := 'База знаний'; ok := cnt>0; detail := cnt||' статей'; return next;
  exception when others then name := 'База знаний'; ok := false; detail := sqlerrm; return next; end;

  begin
    execute 'select count(*) from public.app_calc_saves where ($1 is null or tenant_id=$1)' into cnt using ten;
    name := 'Мини-сервисы (0063)'; ok := true; detail := cnt||' расчётов'; return next;
  exception when others then name := 'Мини-сервисы (0063)'; ok := false; detail := 'миграция не применена: '||sqlerrm; return next; end;

  begin
    execute 'select count(*) from public.app_escrow_deals where ($1 is null or tenant_id=$1)' into cnt using ten;
    name := 'Эскроу (0067)'; ok := true; detail := cnt||' сделок'; return next;
  exception when others then name := 'Эскроу (0067)'; ok := false; detail := 'миграция не применена: '||sqlerrm; return next; end;

  begin
    execute 'select count(*) from public.app_entity_records' into cnt;
    name := 'App Builder (0066)'; ok := true; detail := cnt||' записей'; return next;
  exception when others then name := 'App Builder (0066)'; ok := false; detail := 'миграция не применена: '||sqlerrm; return next; end;

  begin
    execute 'select count(*) from public.app_market_listings' into cnt;
    name := 'Маркетплейс (0071)'; ok := true; detail := cnt||' объявлений'; return next;
  exception when others then name := 'Маркетплейс (0071)'; ok := false; detail := 'миграция не применена: '||sqlerrm; return next; end;
end $$;

-- ---------- Статистика объёма (админ) ----------
create or replace function public.app_scale_stats(p_token uuid)
returns table (tables bigint, functions bigint, users bigint, orders bigint, naryads bigint, notifications bigint, attachments bigint, attachments_bytes bigint)
language plpgsql security definer set search_path = public
as $$
declare urole text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  if urole <> 'admin' then raise exception 'Только администратор платформы'; end if;
  return query select
    (select count(*) from information_schema.tables where table_schema='public' and table_name like 'app\_%' escape '\'),
    (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'app\_%' escape '\'),
    (select count(*) from public.app_users),
    (select count(*) from public.app_orders),
    (select count(*) from public.app_naryads),
    (select count(*) from public.app_notifications),
    (select count(*) from public.app_attachments),
    (select coalesce(sum(length(content)),0) from public.app_attachments);
end $$;

grant execute on function public.app_page_count(uuid,text,text) to anon, authenticated;
grant execute on function public.app_page_rows(uuid,text,int,int,text) to anon, authenticated;
grant execute on function public.app_backup_note(uuid,text,text,text) to anon, authenticated;
grant execute on function public.app_backup_list(uuid,int) to anon, authenticated;
grant execute on function public.app_smoke_test(uuid) to anon, authenticated;
grant execute on function public.app_scale_stats(uuid) to anon, authenticated;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Эксплуатация','Масштаб, пагинация и автотесты',
   'Раздел «Масштаб и эксплуатация»: постраничный вывод длинных списков (заявки, база знаний, журнал, расчёты) — app_page_count/app_page_rows; самотестирование системы (смоук) — app_smoke_test проверяет доступность ключевых таблиц и миграций; журнал резервных копий (app_backup_*) для админа; статистика объёма БД (app_scale_stats). Добавлены индексы по частым фильтрам.',
   'масштаб пагинация индексы бэкап автотесты смоук эксплуатация производительность')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Масштаб, пагинация и автотесты');
