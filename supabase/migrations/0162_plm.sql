-- ============================================================
-- 3DMP Service · 0162_plm.sql  (W18c — PDM / PLM)
-- Изделия и состав с версиями, документы (ЕСКД/ЕСТД), изменения (ECN) с решением.
-- Идемпотентно. Зависит от 0001..0161.
-- ============================================================

-- ---------- Изделия ----------
create table if not exists public.app_products (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  code          text,
  name          text not null,
  version       integer not null default 1,
  state         text not null default 'draft',   -- draft|released|obsolete
  item_id       uuid references public.app_master_items (id) on delete set null,
  attrs         jsonb not null default '{}'::jsonb,
  note          text,
  created_login text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists app_products_idx on public.app_products (tenant_id, state);
create unique index if not exists app_products_code_uq on public.app_products (tenant_id, lower(code)) where code is not null;
alter table public.app_products enable row level security;

-- ---------- Состав (BOM с версией) ----------
create table if not exists public.app_product_bom (
  id                 uuid primary key default gen_random_uuid(),
  tenant_id          uuid references public.tenants (id),
  product_id         uuid not null references public.app_products (id) on delete cascade,
  version            integer not null default 1,
  component_item_id  uuid references public.app_master_items (id) on delete set null,
  component_product_id uuid references public.app_products (id) on delete set null,
  qty                numeric not null default 1,
  unit               text,
  pos                text,
  note               text,
  created_at         timestamptz not null default now()
);
create index if not exists app_product_bom_idx on public.app_product_bom (product_id, version);
alter table public.app_product_bom enable row level security;

-- ---------- Документы (ЕСКД/ЕСТД/прочее) ----------
create table if not exists public.app_product_docs (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid references public.tenants (id),
  product_id  uuid not null references public.app_products (id) on delete cascade,
  doc_type    text not null default 'ЕСКД',   -- ЕСКД|ЕСТД|ТУ|прочее
  title       text,
  doc_id      uuid,
  note        text,
  created_at  timestamptz not null default now()
);
create index if not exists app_product_docs_idx on public.app_product_docs (product_id);
alter table public.app_product_docs enable row level security;

-- ---------- Изменения (ECN) ----------
create table if not exists public.app_ecn (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  product_id    uuid references public.app_products (id) on delete set null,
  number        text,
  title         text not null,
  reason        text,
  changes       jsonb not null default '[]'::jsonb,  -- [{field,old,new}]
  status        text not null default 'draft',        -- draft|pending|approved|rejected
  decided_by    uuid references public.app_users (id) on delete set null,
  decided_login text,
  decided_at    timestamptz,
  decision_note text,
  created_login text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists app_ecn_idx on public.app_ecn (tenant_id, status);
alter table public.app_ecn enable row level security;

-- ================= RPC: изделия =================
create or replace function public.app_products_list(p_token uuid, p_q text default null, p_state text default null)
returns table (id uuid, code text, name text, version integer, state text, bom bigint, docs bigint, updated_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query
    select p.id, p.code, p.name, p.version, p.state,
           (select count(*) from public.app_product_bom b where b.product_id = p.id and b.version = p.version),
           (select count(*) from public.app_product_docs d where d.product_id = p.id),
           p.updated_at
      from public.app_products p
     where (adm or p.tenant_id = ten)
       and (p_q is null or p_q = '' or p.name ilike '%'||p_q||'%' or coalesce(p.code,'') ilike '%'||p_q||'%')
       and (p_state is null or p_state = '' or p.state = p_state)
     order by p.name;
end $$;

create or replace function public.app_product_save(p_token uuid, p_id uuid, p_code text, p_name text, p_version integer, p_state text, p_item_id uuid, p_attrs jsonb, p_note text)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; uname text; newid uuid; st text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid; return; end if;
  select u.tenant_id, s.ulogin into ten, uname from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  if coalesce(trim(p_name),'') = '' then return query select false,'Укажите наименование изделия', null::uuid; return; end if;
  st := coalesce(nullif(trim(p_state),''),'draft');
  if st not in ('draft','released','obsolete') then return query select false,'Недопустимое состояние', null::uuid; return; end if;
  if p_id is null then
    insert into public.app_products (tenant_id, code, name, version, state, item_id, attrs, note, created_login)
    values (ten, nullif(trim(p_code),''), left(trim(p_name),200), greatest(coalesce(p_version,1),1), st, p_item_id, coalesce(p_attrs,'{}'::jsonb), nullif(trim(p_note),''), uname)
    returning app_products.id into newid;
    return query select true,'Изделие создано', newid;
  else
    update public.app_products p set code = nullif(trim(p_code),''), name = left(trim(p_name),200), version = greatest(coalesce(p_version, p.version),1),
           state = st, item_id = coalesce(p_item_id, p.item_id), attrs = coalesce(p_attrs, p.attrs), note = nullif(trim(p_note),''), updated_at = now()
     where p.id = p_id and (public.app_is_platform_admin(p_token) or p.tenant_id = ten)
     returning p.id into newid;
    if newid is null then return query select false,'Изделие не найдено', null::uuid; return; end if;
    return query select true,'Изделие сохранено', newid;
  end if;
end $$;

create or replace function public.app_product_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; n integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten := public.app_my_tenant(p_token);
  delete from public.app_products p where p.id = p_id and (public.app_is_platform_admin(p_token) or p.tenant_id = ten);
  get diagnostics n = row_count;
  if n = 0 then return query select false,'Изделие не найдено'; return; end if;
  return query select true,'Изделие удалено';
end $$;

-- ================= RPC: состав =================
create or replace function public.app_product_bom_list(p_token uuid, p_product_id uuid, p_version integer default null)
returns table (id uuid, version integer, component text, qty numeric, unit text, pos text, item_id uuid, product_id uuid, note text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean; v integer;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  select p.version into v from public.app_products p where p.id = p_product_id and (adm or p.tenant_id = ten);
  v := coalesce(p_version, v, 1);
  return query
    select b.id, b.version,
           coalesce(mi.name, cp.name, '—'),
           b.qty, coalesce(b.unit, mi.unit), b.pos, b.component_item_id, b.component_product_id, b.note
      from public.app_product_bom b
      left join public.app_master_items mi on mi.id = b.component_item_id
      left join public.app_products cp on cp.id = b.component_product_id
     where b.product_id = p_product_id and b.version = v and (adm or b.tenant_id = ten)
     order by b.pos nulls last, mi.name;
end $$;

create or replace function public.app_product_bom_save(p_token uuid, p_id uuid, p_product_id uuid, p_version integer, p_item_id uuid, p_product_comp uuid, p_qty numeric, p_unit text, p_position text, p_note text)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; newid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid; return; end if;
  ten := public.app_my_tenant(p_token);
  if not exists (select 1 from public.app_products p where p.id = p_product_id and (public.app_is_platform_admin(p_token) or p.tenant_id = ten)) then
    return query select false,'Изделие не найдено', null::uuid; return;
  end if;
  if p_item_id is null and p_product_comp is null then return query select false,'Укажите компонент', null::uuid; return; end if;
  if p_id is null then
    insert into public.app_product_bom (tenant_id, product_id, version, component_item_id, component_product_id, qty, unit, pos, note)
    values (ten, p_product_id, greatest(coalesce(p_version,1),1), p_item_id, p_product_comp, coalesce(p_qty,1), nullif(trim(p_unit),''), nullif(trim(p_position),''), nullif(trim(p_note),''))
    returning app_product_bom.id into newid;
    return query select true,'Компонент добавлен', newid;
  else
    update public.app_product_bom b set version = greatest(coalesce(p_version, b.version),1), component_item_id = p_item_id,
           component_product_id = p_product_comp, qty = coalesce(p_qty, b.qty), unit = nullif(trim(p_unit),''),
           pos = nullif(trim(p_position),''), note = nullif(trim(p_note),'')
     where b.id = p_id and (public.app_is_platform_admin(p_token) or b.tenant_id = ten)
     returning b.id into newid;
    if newid is null then return query select false,'Компонент не найден', null::uuid; return; end if;
    return query select true,'Компонент сохранён', newid;
  end if;
end $$;

create or replace function public.app_product_bom_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; n integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten := public.app_my_tenant(p_token);
  delete from public.app_product_bom b where b.id = p_id and (public.app_is_platform_admin(p_token) or b.tenant_id = ten);
  get diagnostics n = row_count;
  if n = 0 then return query select false,'Компонент не найден'; return; end if;
  return query select true,'Компонент удалён';
end $$;

-- ================= RPC: документы =================
create or replace function public.app_product_docs_list(p_token uuid, p_product_id uuid)
returns table (id uuid, doc_type text, title text, doc_id uuid, note text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query select d.id, d.doc_type, d.title, d.doc_id, d.note from public.app_product_docs d
    where d.product_id = p_product_id and (adm or d.tenant_id = ten) order by d.doc_type, d.title;
end $$;

create or replace function public.app_product_doc_save(p_token uuid, p_id uuid, p_product_id uuid, p_doc_type text, p_title text, p_doc_id uuid, p_note text)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; newid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid; return; end if;
  select u.tenant_id into ten from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  if p_id is null then
    insert into public.app_product_docs (tenant_id, product_id, doc_type, title, doc_id, note)
    values (ten, p_product_id, coalesce(nullif(trim(p_doc_type),''),'ЕСКД'), nullif(trim(p_title),''), p_doc_id, nullif(trim(p_note),''))
    returning app_product_docs.id into newid;
    return query select true,'Документ привязан', newid;
  else
    update public.app_product_docs d set doc_type = coalesce(nullif(trim(p_doc_type),''), d.doc_type), title = nullif(trim(p_title),''), doc_id = p_doc_id, note = nullif(trim(p_note),'')
     where d.id = p_id and (public.app_is_platform_admin(p_token) or d.tenant_id = ten)
     returning d.id into newid;
    if newid is null then return query select false,'Документ не найден', null::uuid; return; end if;
    return query select true,'Документ сохранён', newid;
  end if;
end $$;

create or replace function public.app_product_doc_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; n integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten := public.app_my_tenant(p_token);
  delete from public.app_product_docs d where d.id = p_id and (public.app_is_platform_admin(p_token) or d.tenant_id = ten);
  get diagnostics n = row_count;
  if n = 0 then return query select false,'Документ не найден'; return; end if;
  return query select true,'Документ отвязан';
end $$;

-- ================= RPC: изменения (ECN) =================
create or replace function public.app_ecn_list(p_token uuid, p_status text default null)
returns table (id uuid, product text, number text, title text, reason text, status text, decided_login text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean; st text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  st := nullif(trim(coalesce(p_status,'')),'');
  return query
    select e.id, p.name, e.number, e.title, e.reason, e.status, e.decided_login, e.created_at
      from public.app_ecn e left join public.app_products p on p.id = e.product_id
     where (adm or e.tenant_id = ten) and (st is null or e.status = st)
     order by e.created_at desc;
end $$;

create or replace function public.app_ecn_save(p_token uuid, p_id uuid, p_product_id uuid, p_number text, p_title text, p_reason text, p_changes jsonb)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; uname text; newid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid; return; end if;
  select u.tenant_id, s.ulogin into ten, uname from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  if coalesce(trim(p_title),'') = '' then return query select false,'Укажите суть изменения', null::uuid; return; end if;
  if p_changes is not null and jsonb_typeof(p_changes) <> 'array' then return query select false,'Изменения должны быть массивом', null::uuid; return; end if;
  if p_id is null then
    insert into public.app_ecn (tenant_id, product_id, number, title, reason, changes, created_login)
    values (ten, p_product_id, nullif(trim(p_number),''), left(trim(p_title),200), nullif(trim(p_reason),''), coalesce(p_changes,'[]'::jsonb), uname)
    returning app_ecn.id into newid;
    return query select true,'Изменение создано', newid;
  else
    update public.app_ecn e set product_id = coalesce(p_product_id, e.product_id), number = nullif(trim(p_number),''),
           title = left(trim(p_title),200), reason = nullif(trim(p_reason),''), changes = coalesce(p_changes, e.changes), updated_at = now()
     where e.id = p_id and e.status in ('draft','rejected') and (public.app_is_platform_admin(p_token) or e.tenant_id = ten)
     returning e.id into newid;
    if newid is null then return query select false,'Изменение не найдено или уже в работе', null::uuid; return; end if;
    return query select true,'Изменение сохранено', newid;
  end if;
end $$;

create or replace function public.app_ecn_set_status(p_token uuid, p_id uuid, p_status text, p_comment text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; uname text; uid uuid; st text; cur text; n integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.uid, s.ulogin into uid, uname from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  st := lower(trim(coalesce(p_status,'')));
  if st not in ('pending','approved','rejected','draft') then return query select false,'Недопустимый статус'; return; end if;
  select status into cur from public.app_ecn where id = p_id and (public.app_is_platform_admin(p_token) or tenant_id = ten);
  if cur is null then return query select false,'Изменение не найдено'; return; end if;
  if st in ('approved','rejected') and not (public.app_is_platform_admin(p_token) or public.app_is_owner(p_token)) then
    return query select false,'Решение принимает владелец/администратор'; return;
  end if;
  update public.app_ecn set status = st,
         decided_by = case when st in ('approved','rejected') then uid else decided_by end,
         decided_login = case when st in ('approved','rejected') then uname else decided_login end,
         decided_at = case when st in ('approved','rejected') then now() else decided_at end,
         decision_note = case when st in ('approved','rejected') then nullif(trim(p_comment),'') else decision_note end,
         updated_at = now()
   where id = p_id;
  get diagnostics n = row_count;
  if n = 0 then return query select false,'Изменение не найдено'; return; end if;
  return query select true,'Статус изменения: ' || st;
end $$;

create or replace function public.app_ecn_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; n integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten := public.app_my_tenant(p_token);
  delete from public.app_ecn e where e.id = p_id and e.status in ('draft','rejected') and (public.app_is_platform_admin(p_token) or e.tenant_id = ten);
  get diagnostics n = row_count;
  if n = 0 then return query select false,'Изменение не найдено или уже в работе'; return; end if;
  return query select true,'Изменение удалено';
end $$;

create or replace function public.app_plm_kpi(p_token uuid)
returns table (products bigint, released bigint, draft bigint, bom_lines bigint, docs bigint, ecn_pending bigint, ecn_approved bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query select
    (select count(*) from public.app_products p where adm or p.tenant_id=ten),
    (select count(*) from public.app_products p where (adm or p.tenant_id=ten) and p.state='released'),
    (select count(*) from public.app_products p where (adm or p.tenant_id=ten) and p.state='draft'),
    (select count(*) from public.app_product_bom b where adm or b.tenant_id=ten),
    (select count(*) from public.app_product_docs d where adm or d.tenant_id=ten),
    (select count(*) from public.app_ecn e where (adm or e.tenant_id=ten) and e.status='pending'),
    (select count(*) from public.app_ecn e where (adm or e.tenant_id=ten) and e.status='approved');
end $$;

-- ================= Демо =================
insert into public.app_products (tenant_id, code, name, version, state, attrs, created_login)
select 'aaaaaaaa-0000-0000-0000-000000000001', 'PRD-001', 'Корпус редуктора (демо)', 1, 'released', '{"material":"Сталь 45"}'::jsonb, 'owner'
where not exists (select 1 from public.app_products where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and code='PRD-001');

insert into public.app_product_bom (tenant_id, product_id, version, component_item_id, qty, unit, pos)
select 'aaaaaaaa-0000-0000-0000-000000000001', p.id, 1, m.id, 2.5, 'кг', '1'
from public.app_products p, public.app_master_items m
where p.tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and p.code='PRD-001'
  and m.tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and m.code='MAT-ST45'
  and not exists (select 1 from public.app_product_bom b where b.product_id=p.id and b.component_item_id=m.id and b.version=1);

insert into public.app_ecn (tenant_id, product_id, number, title, reason, changes, status, created_login)
select 'aaaaaaaa-0000-0000-0000-000000000001', p.id, 'ECN-001', 'Заменить материал на 40Х', 'Повышение прочности', '[{"field":"material","old":"Сталь 45","new":"40Х"}]'::jsonb, 'draft', 'owner'
from public.app_products p
where p.tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and p.code='PRD-001'
  and not exists (select 1 from public.app_ecn where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and number='ECN-001');

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Производство','PDM/PLM: изделия, состав, документы, изменения (ECN)',
   'W18c: изделия (app_products: код, версия, состояние draft/released/obsolete, связь с НСИ) и состав с версиями (app_product_bom: компоненты из НСИ или под-изделия, кол-во, позиция); документы (app_product_docs: ЕСКД/ЕСТД/ТУ, связь с doc_id); изменения (app_ecn: суть/причина/список изменений, статусы draft→pending→approved/rejected, решение владельца). KPI app_plm_kpi. Модуль «Изделия и состав» (apps/plm).',
   'PDM PLM изделие состав BOM версия ЕСКД ЕСТД ECN изменение')
) as v(category,question,answer,tags)
where not exists (
  select 1 from public.app_knowledge
   where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001' and question = 'PDM/PLM: изделия, состав, документы, изменения (ECN)'
);

-- ---------- Права ----------
grant execute on function public.app_products_list(uuid,text,text) to anon, authenticated;
grant execute on function public.app_product_save(uuid,uuid,text,text,integer,text,uuid,jsonb,text) to anon, authenticated;
grant execute on function public.app_product_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_product_bom_list(uuid,uuid,integer) to anon, authenticated;
grant execute on function public.app_product_bom_save(uuid,uuid,uuid,integer,uuid,uuid,numeric,text,text,text) to anon, authenticated;
grant execute on function public.app_product_bom_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_product_docs_list(uuid,uuid) to anon, authenticated;
grant execute on function public.app_product_doc_save(uuid,uuid,uuid,text,text,uuid,text) to anon, authenticated;
grant execute on function public.app_product_doc_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_ecn_list(uuid,text) to anon, authenticated;
grant execute on function public.app_ecn_save(uuid,uuid,uuid,text,text,text,jsonb) to anon, authenticated;
grant execute on function public.app_ecn_set_status(uuid,uuid,text,text) to anon, authenticated;
grant execute on function public.app_ecn_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_plm_kpi(uuid) to anon, authenticated;
