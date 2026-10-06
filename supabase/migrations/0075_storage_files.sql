-- ============================================================
-- 3DMP Service · 0075_storage_files.sql  (v53 — P14 Сессия E)
-- Хранилище файлов (Supabase Storage bucket saas-files) + реестр app_files
-- (чертежи/КД/фото), сводный журнал истории. База знаний. Зависит от 0001..0074.
-- ============================================================

-- ---------- Bucket (public) ----------
insert into storage.buckets (id, name, public)
values ('saas-files', 'saas-files', true)
on conflict (id) do nothing;

-- ---------- Политики Storage (идемпотентно) ----------
do $$
begin
  if not exists (select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='saas_files_read') then
    create policy saas_files_read on storage.objects for select using (bucket_id = 'saas-files');
  end if;
  if not exists (select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='saas_files_write') then
    create policy saas_files_write on storage.objects for insert with check (bucket_id = 'saas-files');
  end if;
  if not exists (select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='saas_files_delete') then
    create policy saas_files_delete on storage.objects for delete using (bucket_id = 'saas-files');
  end if;
end $$;

-- ---------- Реестр файлов ----------
create table if not exists public.app_files (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid references public.tenants (id),
  entity_type  text not null default 'other',   -- order|naryad|client|invoice|spec|norms|other
  entity_id    uuid,
  name         text not null,
  mime         text,
  size_bytes   bigint,
  path         text not null,
  uploaded_by  text,
  note         text,
  created_at   timestamptz not null default now()
);
create index if not exists app_files_idx on public.app_files (tenant_id, entity_type, entity_id, created_at desc);
alter table public.app_files enable row level security;

create or replace function public.app_file_url(p_path text) returns text
language sql immutable
as $$ select 'https://zfkbzzmtbrueaksfaqbf.supabase.co/storage/v1/object/public/saas-files/' || p_path $$;

create or replace function public.app_file_register(p_token uuid, p_entity_type text, p_entity_id uuid,
  p_name text, p_mime text, p_size bigint, p_path text, p_note text default null)
returns table (id uuid, url text, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; ulogin text; fid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_path),'')='' then raise exception 'Путь файла не задан'; return; end if;
  insert into public.app_files (tenant_id, entity_type, entity_id, name, mime, size_bytes, path, uploaded_by, note)
  values (ten, coalesce(nullif(trim(p_entity_type),''),'other'), p_entity_id, coalesce(nullif(trim(p_name),''),'файл'), nullif(trim(p_mime),''),
          p_size, trim(p_path), ulogin, nullif(trim(p_note),''))
  returning id into fid;
  return query select fid, public.app_file_url(trim(p_path)), 'Файл зарегистрирован';
end $$;

drop function if exists public.app_files_list(uuid,text,uuid);
create or replace function public.app_files_list(p_token uuid, p_entity_type text default null, p_entity_id uuid default null)
returns table (id uuid, entity_type text, entity_id uuid, name text, mime text, size_bytes bigint, path text, url text, uploaded_by text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select f.id, f.entity_type, f.entity_id, f.name, f.mime, f.size_bytes, f.path, public.app_file_url(f.path), f.uploaded_by, f.created_at
    from public.app_files f
    where (urole='admin' or f.tenant_id=ten)
      and (coalesce(p_entity_type,'')='' or f.entity_type=p_entity_type)
      and (p_entity_id is null or f.entity_id=p_entity_id)
    order by f.created_at desc;
end $$;

create or replace function public.app_file_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  delete from public.app_files where id=p_id and (urole='admin' or tenant_id=ten);
  return query select true,'Файл удалён';
end $$;

create or replace function public.app_files_kpi(p_token uuid)
returns table (total bigint, total_bytes bigint, orders_files bigint, drawings bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select count(*), coalesce(sum(size_bytes),0)::bigint,
    count(*) filter (where entity_type='order'),
    count(*) filter (where mime like '%dwg%' or mime like '%pdf%' or lower(name) similar to '%(dwg|dxf|stl|pdf)%')
    from public.app_files where (urole='admin' or tenant_id=ten);
end $$;

-- ---------- Сводный журнал ----------
create or replace function public.app_journal_list(p_token uuid, p_limit int default 50)
returns table (kind text, title text, detail text, who text, at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; ulogin text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select q.kind, q.title, q.detail, q.who, q.at from (
      select 'Расчёт'::text as kind, coalesce(c.title,'Расчёт') as title, c.kind as detail, coalesce(c.created_login,'') as who, c.created_at as at
        from public.app_calc_saves c
        where (urole='admin' or c.tenant_id=ten)
      union all
      select 'Файл'::text, f.name, f.entity_type, coalesce(f.uploaded_by,''), f.created_at
        from public.app_files f
        where (urole='admin' or f.tenant_id=ten)
      union all
      select 'Событие'::text, e.action, coalesce(e.detail,''), coalesce(e.login,''), e.created_at
        from public.app_events e
        where (urole='admin' or e.login=ulogin)
    ) q
    order by q.at desc
    limit greatest(1, least(coalesce(p_limit,50), 200));
end $$;

grant execute on function public.app_file_register(uuid,text,uuid,text,text,bigint,text,text) to anon, authenticated;
grant execute on function public.app_files_list(uuid,text,uuid) to anon, authenticated;
grant execute on function public.app_file_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_files_kpi(uuid) to anon, authenticated;
grant execute on function public.app_journal_list(uuid,int) to anon, authenticated;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Платформа','Хранилище файлов и сводный журнал (P14 Сессия E)',
   'Модуль «Файлы и журнал»: вложения (чертежи/КД/фото/PDF) в Supabase Storage (bucket saas-files, публичный), метаданные в app_files с привязкой к сущности (заявка/наряд/клиент/спецификация). Сводный журнал (app_journal_list) объединяет расчёты, файлы и события. Загрузка — через Supabase Storage, регистрация — через app_file_register.',
   'файлы вложения storage bucket чертежи журнал история P12')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Хранилище файлов и сводный журнал (P14 Сессия E)');
