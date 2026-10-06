-- ============================================================
-- 3DMP Service · 0017_docs.sql  (v2.4 — документооборот)
-- Документы (КП/договоры/техкарты/акты), версии. Изоляция по tenant.
-- Роли: admin/owner/manager. Зависит от 0001..0016.
-- ============================================================

create sequence if not exists public.app_doc_seq;

create table if not exists public.app_documents (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  doc_type      text not null default 'kp',     -- kp | contract | techcard | act | other
  number        text unique not null,
  title         text not null,
  order_id      uuid references public.app_orders (id) on delete set null,
  counterparty  text,
  amount        numeric,
  status        text not null default 'draft',  -- draft | active | archived
  version       integer not null default 1,
  content       text,
  created_by    uuid references public.app_users (id) on delete set null,
  created_login text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists app_documents_tenant_idx on public.app_documents (tenant_id, created_at desc);

create table if not exists public.app_document_versions (
  id          uuid primary key default gen_random_uuid(),
  document_id uuid not null references public.app_documents (id) on delete cascade,
  version     integer not null,
  title       text,
  content     text,
  by_login    text,
  created_at  timestamptz not null default now()
);
create index if not exists app_doc_versions_idx on public.app_document_versions (document_id, version desc);

alter table public.app_documents         enable row level security;
alter table public.app_document_versions enable row level security;

-- ---------- Список ----------
drop function if exists public.app_doc_list(uuid, text);
create or replace function public.app_doc_list(p_token uuid, p_type text)
returns table (id uuid, doc_type text, number text, title text, counterparty text, amount numeric, status text, version integer, order_number text, updated_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select d.id, d.doc_type, d.number, d.title, d.counterparty, d.amount, d.status, d.version, o.number, d.updated_at
    from public.app_documents d left join public.app_orders o on o.id = d.order_id
    where (urole='admin' or d.tenant_id = ten) and (p_type is null or p_type = '' or d.doc_type = p_type)
    order by d.updated_at desc;
end $$;

drop function if exists public.app_doc_get(uuid, uuid);
create or replace function public.app_doc_get(p_token uuid, p_id uuid)
returns table (id uuid, doc_type text, number text, title text, order_id uuid, counterparty text, amount numeric, status text, version integer, content text, created_login text, created_at timestamptz, updated_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select d.id, d.doc_type, d.number, d.title, d.order_id, d.counterparty, d.amount, d.status, d.version, d.content, d.created_login, d.created_at, d.updated_at
    from public.app_documents d where d.id = p_id and (urole='admin' or d.tenant_id = ten);
end $$;

-- ---------- Создание ----------
create or replace function public.app_doc_create(p_token uuid, p_doc_type text, p_title text, p_order_id uuid, p_counterparty text, p_amount numeric, p_content text)
returns table (id uuid, number text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ulogin text; ten uuid; did uuid; dnum text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_title),'') = '' then raise exception 'Укажите название документа'; end if;
  dnum := 'DOC-' || lpad(nextval('public.app_doc_seq')::text, 5, '0');
  insert into public.app_documents (tenant_id, doc_type, number, title, order_id, counterparty, amount, content, created_by, created_login)
  values (ten, coalesce(nullif(trim(p_doc_type),''),'kp'), dnum, trim(p_title), p_order_id, nullif(trim(p_counterparty),''), p_amount, p_content, uid, ulogin)
  returning app_documents.id into did;
  insert into public.app_document_versions (document_id, version, title, content, by_login)
  values (did, 1, trim(p_title), p_content, ulogin);
  return query select did, dnum;
end $$;

-- ---------- Обновление (новая версия) ----------
create or replace function public.app_doc_update(p_token uuid, p_id uuid, p_title text, p_counterparty text, p_amount numeric, p_content text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ulogin text; urole text; ten uuid; v integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.ulogin, s.urole into ulogin, urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select d.version into v from public.app_documents d where d.id = p_id and (urole='admin' or d.tenant_id = ten);
  if v is null then return query select false,'Документ не найден'; return; end if;
  v := v + 1;
  update public.app_documents set title = coalesce(nullif(trim(p_title),''), title), counterparty = coalesce(nullif(trim(p_counterparty),''), counterparty),
    amount = coalesce(p_amount, amount), content = coalesce(p_content, content), version = v, updated_at = now()
   where id = p_id;
  insert into public.app_document_versions (document_id, version, title, content, by_login)
  values (p_id, v, coalesce(nullif(trim(p_title),''),'—'), p_content, ulogin);
  return query select true,'Сохранено (версия ' || v || ')';
end $$;

create or replace function public.app_doc_set_status(p_token uuid, p_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  update public.app_documents set status = p_status, updated_at = now() where id = p_id and (urole='admin' or tenant_id = ten);
  return query select true,'Статус обновлён';
end $$;

create or replace function public.app_doc_versions(p_token uuid, p_id uuid)
returns table (version integer, title text, by_login text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select v.version, v.title, v.by_login, v.created_at
    from public.app_document_versions v join public.app_documents d on d.id = v.document_id
    where v.document_id = p_id and (urole='admin' or d.tenant_id = ten) order by v.version desc;
end $$;

grant execute on function public.app_doc_list(uuid,text) to anon, authenticated;
grant execute on function public.app_doc_get(uuid,uuid) to anon, authenticated;
grant execute on function public.app_doc_create(uuid,text,text,uuid,text,numeric,text) to anon, authenticated;
grant execute on function public.app_doc_update(uuid,uuid,text,text,numeric,text) to anon, authenticated;
grant execute on function public.app_doc_set_status(uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_doc_versions(uuid,uuid) to anon, authenticated;
