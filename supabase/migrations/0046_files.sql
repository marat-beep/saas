-- ============================================================
-- 3DMP Service · 0046_files.sql  (v28.0 — боевой режим: вложения/файлы)
-- Единое хранилище вложений к сущностям (заявка/документ/ОТК/паспорт/наряд/закупка).
-- Файлы в БД (bytea), доступ через RPC с tenant-изоляцией. База знаний.
-- Зависит от 0001..0045.
-- ============================================================

create table if not exists public.app_attachments (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid references public.tenants (id),
  entity_type text not null,      -- order | document | qc | passport | naryad | tender
  entity_id   uuid,
  name        text not null,
  mime        text,
  size        integer,
  data        bytea,
  uploaded_by text,
  created_at  timestamptz not null default now()
);
create index if not exists app_attachments_entity_idx on public.app_attachments (entity_type, entity_id);
create index if not exists app_attachments_tenant_idx on public.app_attachments (tenant_id, created_at desc);
alter table public.app_attachments enable row level security;

-- ---------- Загрузить вложение (base64) ----------
create or replace function public.app_attachment_add(p_token uuid, p_entity_type text, p_entity_id uuid,
  p_name text, p_mime text, p_data text)
returns table (id uuid, name text)
language plpgsql security definer set search_path = public
as $$
declare ulogin text; ten uuid; aid uuid; bytes bytea; allowed text[] := array['order','document','qc','passport','naryad','tender'];
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.ulogin into ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if not (p_entity_type = any(allowed)) then raise exception 'Неизвестный тип сущности'; end if;
  if coalesce(trim(p_name),'') = '' then raise exception 'Укажите имя файла'; end if;
  begin
    bytes := decode(p_data, 'base64');
  exception when others then raise exception 'Некорректные данные файла'; end;
  if octet_length(bytes) > 8388608 then raise exception 'Файл больше 8 МБ'; end if;

  insert into public.app_attachments (tenant_id, entity_type, entity_id, name, mime, size, data, uploaded_by)
  values (ten, p_entity_type, p_entity_id, trim(p_name), nullif(trim(p_mime),''), octet_length(bytes), bytes, ulogin)
  returning app_attachments.id into aid;
  return query select aid, trim(p_name);
end $$;

-- ---------- Список вложений (метаданные) ----------
create or replace function public.app_attachment_list(p_token uuid, p_entity_type text, p_entity_id uuid)
returns table (id uuid, name text, mime text, size integer, uploaded_by text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select a.id, a.name, a.mime, a.size, a.uploaded_by, a.created_at
    from public.app_attachments a
    where a.entity_type = p_entity_type and a.entity_id = p_entity_id and (urole='admin' or a.tenant_id = ten)
    order by a.created_at desc;
end $$;

-- ---------- Получить вложение (base64) ----------
create or replace function public.app_attachment_get(p_token uuid, p_id uuid)
returns table (id uuid, name text, mime text, size integer, data text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select a.id, a.name, a.mime, a.size, encode(a.data, 'base64')
    from public.app_attachments a
    where a.id = p_id and (urole='admin' or a.tenant_id = ten);
end $$;

-- ---------- Удалить вложение ----------
create or replace function public.app_attachment_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  delete from public.app_attachments where id = p_id and (urole='admin' or tenant_id = ten);
  return query select true,'Файл удалён';
end $$;

grant execute on function public.app_attachment_add(uuid,text,uuid,text,text,text) to anon, authenticated;
grant execute on function public.app_attachment_list(uuid,text,uuid) to anon, authenticated;
grant execute on function public.app_attachment_get(uuid,uuid) to anon, authenticated;
grant execute on function public.app_attachment_delete(uuid,uuid) to anon, authenticated;

-- ---------- База знаний: файлы ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Файлы','Как прикрепить файл к заявке/документу/ОТК?',
   'В карточке заявки, документа, чек-листа ОТК, паспорта, наряда или закупки есть блок «Файлы»: нажмите «Прикрепить», выберите файл (чертёж, КП, PDF, фото) — до 8 МБ. Скачивание и удаление — там же. Файлы изолированы по организации.',
   'файлы вложения чертежи КП PDF фото заявка документ ОТК')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and category='Файлы');
