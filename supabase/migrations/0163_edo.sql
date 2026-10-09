-- ============================================================
-- 3DMP Service · 0163_edo.sql  (W19 — ЭДО / СЭД)
-- Реестр документов (входящие/исходящие/внутренние/ОРД), регистрация, поручения,
-- связи с объектами, номенклатура дел/архив. Согласование — через W10/W15.
-- Идемпотентно. Зависит от 0001..0162.
-- ============================================================

create sequence if not exists public.app_doc_seq;

create table if not exists public.app_doc_flows (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  kind          text not null default 'in',      -- in|out|internal|ord
  doc_type      text,                            -- письмо|приказ|договор|акт|счёт|служебная|...
  title         text not null,
  reg_number    text,
  reg_date      date,
  correspondent text,
  summary       text,
  status        text not null default 'draft',   -- draft|registered|in_work|closed|cancelled
  responsible_login text,
  due_date      date,
  entity_type   text,
  entity_id     uuid,
  note          text,
  created_login text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists app_doc_flows_idx on public.app_doc_flows (tenant_id, kind, status);
create unique index if not exists app_doc_flows_reg_uq on public.app_doc_flows (tenant_id, reg_number) where reg_number is not null;
alter table public.app_doc_flows enable row level security;

create table if not exists public.app_doc_links (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid references public.tenants (id),
  doc_id      uuid not null references public.app_doc_flows (id) on delete cascade,
  entity_type text not null,
  entity_id   uuid,
  note        text,
  created_at  timestamptz not null default now()
);
create index if not exists app_doc_links_idx on public.app_doc_links (doc_id);
alter table public.app_doc_links enable row level security;

create table if not exists public.app_doc_resolutions (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid references public.tenants (id),
  doc_id         uuid not null references public.app_doc_flows (id) on delete cascade,
  text           text not null,
  author_login   text,
  assignee_login text,
  due_date       date,
  status         text not null default 'open',   -- open|done|cancelled
  done_at        timestamptz,
  created_at     timestamptz not null default now()
);
create index if not exists app_doc_resolutions_idx on public.app_doc_resolutions (doc_id, status);
alter table public.app_doc_resolutions enable row level security;

create table if not exists public.app_doc_nomenclature (
  id              uuid primary key default gen_random_uuid(),
  tenant_id       uuid references public.tenants (id),
  idx             text,                          -- индекс дела
  title           text not null,
  retention_years integer default 5,
  created_at      timestamptz not null default now()
);
alter table public.app_doc_nomenclature enable row level security;

alter table public.app_doc_flows add column if not exists nomenclature_id uuid references public.app_doc_nomenclature (id);

-- ---------- RPC: реестр ----------
create or replace function public.app_doc_list(p_token uuid, p_kind text default null, p_status text default null, p_q text default null)
returns table (id uuid, kind text, doc_type text, title text, reg_number text, reg_date date, correspondent text, status text,
               responsible_login text, due_date date, created_at timestamptz, links bigint, resolutions_open bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean; k text; st text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  k := nullif(trim(coalesce(p_kind,'')),''); st := nullif(trim(coalesce(p_status,'')),'');
  return query
    select d.id, d.kind, d.doc_type, d.title, d.reg_number, d.reg_date, d.correspondent, d.status, d.responsible_login, d.due_date, d.created_at,
           (select count(*) from public.app_doc_links l where l.doc_id = d.id),
           (select count(*) from public.app_doc_resolutions r where r.doc_id = d.id and r.status='open')
      from public.app_doc_flows d
     where (adm or d.tenant_id = ten)
       and (k is null or d.kind = k) and (st is null or d.status = st)
       and (p_q is null or p_q = '' or d.title ilike '%'||p_q||'%' or coalesce(d.reg_number,'') ilike '%'||p_q||'%' or coalesce(d.correspondent,'') ilike '%'||p_q||'%')
     order by d.created_at desc;
end $$;

create or replace function public.app_doc_save(p_token uuid, p_id uuid, p_kind text, p_doc_type text, p_title text, p_correspondent text, p_summary text, p_responsible text, p_due_date date, p_reg_date date)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; uname text; newid uuid; k text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid; return; end if;
  select u.tenant_id, s.ulogin into ten, uname from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  if coalesce(trim(p_title),'') = '' then return query select false,'Укажите заголовок документа', null::uuid; return; end if;
  k := coalesce(nullif(trim(p_kind),''),'in');
  if k not in ('in','out','internal','ord') then return query select false,'Недопустимый вид документа', null::uuid; return; end if;
  if p_id is null then
    insert into public.app_doc_flows (tenant_id, kind, doc_type, title, correspondent, summary, responsible_login, due_date, reg_date, created_login)
    values (ten, k, nullif(trim(p_doc_type),''), left(trim(p_title),200), nullif(trim(p_correspondent),''), nullif(trim(p_summary),''),
            coalesce(nullif(trim(p_responsible),''), uname), p_due_date, p_reg_date, uname)
    returning app_doc_flows.id into newid;
    return query select true,'Документ создан', newid;
  else
    update public.app_doc_flows d set kind = k, doc_type = nullif(trim(p_doc_type),''), title = left(trim(p_title),200),
           correspondent = nullif(trim(p_correspondent),''), summary = nullif(trim(p_summary),''),
           responsible_login = coalesce(nullif(trim(p_responsible),''), d.responsible_login), due_date = p_due_date,
           reg_date = coalesce(p_reg_date, d.reg_date), updated_at = now()
     where d.id = p_id and (public.app_is_platform_admin(p_token) or d.tenant_id = ten)
     returning d.id into newid;
    if newid is null then return query select false,'Документ не найден', null::uuid; return; end if;
    return query select true,'Документ сохранён', newid;
  end if;
end $$;

create or replace function public.app_doc_register(p_token uuid, p_id uuid)
returns table (ok boolean, message text, reg_number text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; num text; k text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::text; return; end if;
  ten := public.app_my_tenant(p_token);
  select kind into k from public.app_doc_flows where id = p_id and (public.app_is_platform_admin(p_token) or tenant_id = ten);
  if k is null then return query select false,'Документ не найден', null::text; return; end if;
  num := 'ЭДО-' || to_char(current_date,'YYYY') || '-' || lpad(nextval('public.app_doc_seq')::text, 5, '0');
  update public.app_doc_flows set reg_number = num, reg_date = coalesce(reg_date, current_date),
         status = case when status = 'draft' then 'registered' else status end, updated_at = now()
   where id = p_id;
  return query select true, 'Зарегистрирован: ' || num, num;
end $$;

create or replace function public.app_doc_set_status(p_token uuid, p_id uuid, p_status text, p_comment text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; st text; n integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten := public.app_my_tenant(p_token);
  st := lower(trim(coalesce(p_status,'')));
  if st not in ('draft','registered','in_work','closed','cancelled') then return query select false,'Недопустимый статус'; return; end if;
  update public.app_doc_flows d set status = st,
         note = case when p_comment is not null then coalesce(d.note,'') || ' [' || p_comment || ']' else d.note end,
         updated_at = now()
   where d.id = p_id and (public.app_is_platform_admin(p_token) or d.tenant_id = ten);
  get diagnostics n = row_count;
  if n = 0 then return query select false,'Документ не найден'; return; end if;
  return query select true,'Статус: ' || st;
end $$;

create or replace function public.app_doc_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; n integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten := public.app_my_tenant(p_token);
  delete from public.app_doc_flows d where d.id = p_id and d.status in ('draft','cancelled') and (public.app_is_platform_admin(p_token) or d.tenant_id = ten);
  get diagnostics n = row_count;
  if n = 0 then return query select false,'Документ не найден или зарегистрирован (нельзя удалить)'; return; end if;
  return query select true,'Документ удалён';
end $$;

-- ---------- Связи ----------
create or replace function public.app_doc_links_list(p_token uuid, p_doc_id uuid)
returns table (id uuid, entity_type text, entity_id uuid, note text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query select l.id, l.entity_type, l.entity_id, l.note from public.app_doc_links l
    where l.doc_id = p_doc_id and (adm or l.tenant_id = ten) order by l.created_at;
end $$;

create or replace function public.app_doc_link_save(p_token uuid, p_id uuid, p_doc_id uuid, p_entity_type text, p_entity_id uuid, p_note text)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; newid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid; return; end if;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_entity_type),'') = '' then return query select false,'Укажите тип связи', null::uuid; return; end if;
  if p_id is null then
    insert into public.app_doc_links (tenant_id, doc_id, entity_type, entity_id, note) values (ten, p_doc_id, lower(trim(p_entity_type)), p_entity_id, nullif(trim(p_note),''))
    returning app_doc_links.id into newid;
    return query select true,'Связь добавлена', newid;
  else
    update public.app_doc_links l set entity_type = lower(trim(p_entity_type)), entity_id = p_entity_id, note = nullif(trim(p_note),'')
     where l.id = p_id and (public.app_is_platform_admin(p_token) or l.tenant_id = ten)
     returning l.id into newid;
    if newid is null then return query select false,'Связь не найдена', null::uuid; return; end if;
    return query select true,'Связь сохранена', newid;
  end if;
end $$;

create or replace function public.app_doc_link_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; n integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten := public.app_my_tenant(p_token);
  delete from public.app_doc_links l where l.id = p_id and (public.app_is_platform_admin(p_token) or l.tenant_id = ten);
  get diagnostics n = row_count;
  if n = 0 then return query select false,'Связь не найдена'; return; end if;
  return query select true,'Связь удалена';
end $$;

-- ---------- Поручения ----------
create or replace function public.app_doc_resolutions_list(p_token uuid, p_doc_id uuid)
returns table (id uuid, body text, author_login text, assignee_login text, due_date date, status text, done_at timestamptz, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query select r.id, r.text, r.author_login, r.assignee_login, r.due_date, r.status, r.done_at, r.created_at
    from public.app_doc_resolutions r where r.doc_id = p_doc_id and (adm or r.tenant_id = ten) order by r.created_at desc;
end $$;

create or replace function public.app_doc_resolution_add(p_token uuid, p_doc_id uuid, p_text text, p_assignee text, p_due_date date)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; uname text; newid uuid; au uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid; return; end if;
  select u.tenant_id, s.ulogin into ten, uname from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  if coalesce(trim(p_text),'') = '' then return query select false,'Укажите текст поручения', null::uuid; return; end if;
  insert into public.app_doc_resolutions (tenant_id, doc_id, text, author_login, assignee_login, due_date)
  values (ten, p_doc_id, left(trim(p_text),500), uname, nullif(trim(p_assignee),''), p_due_date)
  returning app_doc_resolutions.id into newid;
  if coalesce(trim(p_assignee),'') <> '' then
    select u.id into au from public.app_users u where u.login = p_assignee and u.tenant_id = ten limit 1;
    if au is not null then perform public.app_notif_send(au, 'Поручение по документу', left(trim(p_text),200), 'apps/edo/index.html'); end if;
  end if;
  return query select true,'Поручение выдано', newid;
end $$;

create or replace function public.app_doc_resolution_set_status(p_token uuid, p_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; st text; n integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten := public.app_my_tenant(p_token);
  st := lower(trim(coalesce(p_status,'')));
  if st not in ('open','done','cancelled') then return query select false,'Недопустимый статус'; return; end if;
  update public.app_doc_resolutions r set status = st, done_at = case when st='done' then now() else done_at end
   where r.id = p_id and (public.app_is_platform_admin(p_token) or r.tenant_id = ten);
  get diagnostics n = row_count;
  if n = 0 then return query select false,'Поручение не найдено'; return; end if;
  return query select true,'Статус поручения: ' || st;
end $$;

-- ---------- Номенклатура дел / архив ----------
create or replace function public.app_doc_nomenclature_list(p_token uuid)
returns table (id uuid, idx text, title text, retention_years integer, docs bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query
    select n.id, n.idx, n.title, n.retention_years,
           (select count(*) from public.app_doc_flows d where d.nomenclature_id = n.id)
      from public.app_doc_nomenclature n where adm or n.tenant_id = ten order by n.idx;
end $$;

create or replace function public.app_doc_nomenclature_save(p_token uuid, p_id uuid, p_idx text, p_title text, p_retention integer)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; newid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid; return; end if;
  select u.tenant_id into ten from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  if coalesce(trim(p_title),'') = '' then return query select false,'Укажите название дела', null::uuid; return; end if;
  if p_id is null then
    insert into public.app_doc_nomenclature (tenant_id, idx, title, retention_years)
    values (ten, nullif(trim(p_idx),''), left(trim(p_title),200), coalesce(p_retention,5))
    returning app_doc_nomenclature.id into newid;
    return query select true,'Дело создано', newid;
  else
    update public.app_doc_nomenclature n set idx = nullif(trim(p_idx),''), title = left(trim(p_title),200), retention_years = coalesce(p_retention, n.retention_years)
     where n.id = p_id and (public.app_is_platform_admin(p_token) or n.tenant_id = ten)
     returning n.id into newid;
    if newid is null then return query select false,'Дело не найдено', null::uuid; return; end if;
    return query select true,'Дело сохранено', newid;
  end if;
end $$;

create or replace function public.app_doc_nomenclature_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; n integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten := public.app_my_tenant(p_token);
  delete from public.app_doc_nomenclature n where n.id = p_id and (public.app_is_platform_admin(p_token) or n.tenant_id = ten);
  get diagnostics n = row_count;
  if n = 0 then return query select false,'Дело не найдено'; return; end if;
  return query select true,'Дело удалено';
end $$;

create or replace function public.app_doc_archive(p_token uuid, p_doc_id uuid, p_nomenclature_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; n integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten := public.app_my_tenant(p_token);
  update public.app_doc_flows d set nomenclature_id = p_nomenclature_id, status = case when status='closed' then status else 'closed' end, updated_at = now()
   where d.id = p_doc_id and (public.app_is_platform_admin(p_token) or d.tenant_id = ten);
  get diagnostics n = row_count;
  if n = 0 then return query select false,'Документ не найден'; return; end if;
  return query select true,'Документ в деле';
end $$;

create or replace function public.app_edo_kpi(p_token uuid)
returns table (total bigint, incoming bigint, outgoing bigint, internal bigint, ord bigint, registered bigint, in_work bigint, closed bigint, overdue bigint, open_resolutions bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query select
    (select count(*) from public.app_doc_flows d where adm or d.tenant_id=ten),
    (select count(*) from public.app_doc_flows d where (adm or d.tenant_id=ten) and d.kind='in'),
    (select count(*) from public.app_doc_flows d where (adm or d.tenant_id=ten) and d.kind='out'),
    (select count(*) from public.app_doc_flows d where (adm or d.tenant_id=ten) and d.kind='internal'),
    (select count(*) from public.app_doc_flows d where (adm or d.tenant_id=ten) and d.kind='ord'),
    (select count(*) from public.app_doc_flows d where (adm or d.tenant_id=ten) and d.status='registered'),
    (select count(*) from public.app_doc_flows d where (adm or d.tenant_id=ten) and d.status='in_work'),
    (select count(*) from public.app_doc_flows d where (adm or d.tenant_id=ten) and d.status='closed'),
    (select count(*) from public.app_doc_flows d where (adm or d.tenant_id=ten) and d.due_date < current_date and d.status not in ('closed','cancelled')),
    (select count(*) from public.app_doc_resolutions r where (adm or r.tenant_id=ten) and r.status='open');
end $$;

-- ================= Демо =================
insert into public.app_doc_flows (tenant_id, kind, doc_type, title, correspondent, summary, status, responsible_login, reg_number, reg_date, created_login)
select 'aaaaaaaa-0000-0000-0000-000000000001', 'in', 'письмо', 'Входящее: запрос КП', 'ООО «Привод»', 'Запрос коммерческого предложения', 'registered', 'manager', 'ЭДО-2026-00001', current_date, 'owner'
where not exists (select 1 from public.app_doc_flows where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and reg_number='ЭДО-2026-00001');

insert into public.app_doc_flows (tenant_id, kind, doc_type, title, summary, status, responsible_login, created_login)
select 'aaaaaaaa-0000-0000-0000-000000000001', 'ord', 'приказ', 'Приказ: о запуске участка', 'Организационно-распорядительный документ', 'in_work', 'owner', 'owner'
where not exists (select 1 from public.app_doc_flows where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and title='Приказ: о запуске участка');

insert into public.app_doc_nomenclature (tenant_id, idx, title, retention_years)
select 'aaaaaaaa-0000-0000-0000-000000000001', '01-01', 'Входящая документация', 5
where not exists (select 1 from public.app_doc_nomenclature where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and idx='01-01');

select setval('public.app_doc_seq', greatest(coalesce((select max(split_part(reg_number,'-',3)::int) from public.app_doc_flows where reg_number like 'ЭДО-%'),0), 1), true);

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Платформа','ЭДО/СЭД: документы, регистрация, поручения, номенклатура дел',
   'W19: реестр документов (app_doc_flows: виды in/out/internal/ord, тип, корреспондент, статусы draft→registered→in_work→closed, ответственный, срок) с авто-регистрацией (номер ЭДО-ГГГГ-NNNNN); связи с объектами (app_doc_links: заявка/договор/счёт/контрагент); поручения (app_doc_resolutions с уведомлением исполнителя); номенклатура дел и архив (app_doc_nomenclature, app_doc_archive); KPI (app_edo_kpi). Согласование — через процессы W15/согласования W10. Модуль «Документооборот (ЭДО)» (apps/edo).',
   'ЭДО СЭД документооборот регистрация поручения номенклатура дел архив входящие исходящие ОРД')
) as v(category,question,answer,tags)
where not exists (
  select 1 from public.app_knowledge
   where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001' and question = 'ЭДО/СЭД: документы, регистрация, поручения, номенклатура дел'
);

-- ---------- Права ----------
grant execute on function public.app_doc_list(uuid,text,text,text) to anon, authenticated;
grant execute on function public.app_doc_save(uuid,uuid,text,text,text,text,text,text,date,date) to anon, authenticated;
grant execute on function public.app_doc_register(uuid,uuid) to anon, authenticated;
grant execute on function public.app_doc_set_status(uuid,uuid,text,text) to anon, authenticated;
grant execute on function public.app_doc_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_doc_links_list(uuid,uuid) to anon, authenticated;
grant execute on function public.app_doc_link_save(uuid,uuid,uuid,text,uuid,text) to anon, authenticated;
grant execute on function public.app_doc_link_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_doc_resolutions_list(uuid,uuid) to anon, authenticated;
grant execute on function public.app_doc_resolution_add(uuid,uuid,text,text,date) to anon, authenticated;
grant execute on function public.app_doc_resolution_set_status(uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_doc_nomenclature_list(uuid) to anon, authenticated;
grant execute on function public.app_doc_nomenclature_save(uuid,uuid,text,text,integer) to anon, authenticated;
grant execute on function public.app_doc_nomenclature_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_doc_archive(uuid,uuid,uuid) to anon, authenticated;
grant execute on function public.app_edo_kpi(uuid) to anon, authenticated;
