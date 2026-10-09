-- ============================================================
-- 3DMP Service · 0185_offline2.sql  (план v4, W43 «Офлайн 2.0»)
-- Вложения (фото/скан/файл) к сущностям модулей для мобильного офлайна:
-- app_attachments + RPC add/list. Идемпотентно. Зависит от 0001..0184.
-- ============================================================

create table if not exists public.app_attachments (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid,
  entity_type   text not null,
  entity_id     uuid,
  kind          text not null default 'photo',   -- photo|scan|file
  data_url      text,
  note          text,
  created_by    uuid,
  created_login text,
  created_at    timestamptz not null default now()
);
-- дополняем существующую таблицу вложений полями W43 (idempotent)
alter table public.app_attachments
  add column if not exists kind text not null default 'photo',
  add column if not exists note text,
  add column if not exists data_url text,
  add column if not exists created_by uuid,
  add column if not exists created_login text;
create index if not exists app_attachments_entity_idx on public.app_attachments (entity_type, entity_id, created_at desc);
alter table public.app_attachments enable row level security;

create or replace function public.app_attach_add(p_token uuid, p_entity_type text, p_entity_id uuid, p_kind text, p_data_url text, p_note text)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ulogin text; ten uuid; nid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён',null::uuid; return; end if;
  if coalesce(trim(p_entity_type),'')='' then return query select false,'Не указан тип сущности',null::uuid; return; end if;
  if p_data_url is not null and length(p_data_url) > 4000000 then return query select false,'Файл слишком большой (>4 МБ)',null::uuid; return; end if;
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  insert into public.app_attachments (tenant_id, entity_type, entity_id, name, kind, data_url, note, created_by, created_login)
  values (ten, trim(p_entity_type), p_entity_id, coalesce(nullif(trim(p_note),''), trim(p_entity_type) || ' ' || coalesce(nullif(trim(p_kind),''),'photo')), coalesce(nullif(trim(p_kind),''),'photo'), p_data_url, nullif(trim(p_note),''), uid, ulogin)
  returning app_attachments.id into nid;
  perform public.app_log_event(p_token, 'Вложение добавлено', trim(p_entity_type) || ' (' || coalesce(nullif(trim(p_kind),''),'photo') || ')');
  return query select true, 'Вложение добавлено', nid;
end $$;

create or replace function public.app_attach_list(p_token uuid, p_entity_type text, p_entity_id uuid)
returns table (id uuid, kind text, note text, created_login text, created_at timestamptz, data_url text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token);
  return query
    select a.id, a.kind, a.note, a.created_login, a.created_at, a.data_url
      from public.app_attachments a
     where a.entity_type = trim(p_entity_type) and (p_entity_id is null or a.entity_id = p_entity_id)
       and (a.tenant_id is null or a.tenant_id = ten)
     order by a.created_at desc limit 200;
end $$;

grant execute on function public.app_attach_add(uuid,text,uuid,text,text,text) to anon, authenticated;
grant execute on function public.app_attach_list(uuid,text,uuid) to anon, authenticated;

insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001','Платформа','Офлайн 2.0: фото и скан к сущностям модулей',
 'W43: с телефона можно приложить фото/скан к сущности модуля (например, к паспорту, ОТК-проверке, позиции склада). Функции: app_attach_add(entity_type, entity_id, kind, data_url, note) и app_attach_list. Вложения хранятся в app_attachments; сбор — AppScan.photo (capture) и AppScan.scan (QR/ШК). Надёжность офлайна: идемпотентная очередь (AppOffline, ключ idem) и кэш чтения (AppOfflineCache). В мобильной панели модулей — действия «Фото»/«Скан ШК».',
 'офлайн фото скан вложение app_attach_add app_attachments камера паспорт отк склад idem кэш'
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Офлайн 2.0: фото и скан к сущностям модулей');
