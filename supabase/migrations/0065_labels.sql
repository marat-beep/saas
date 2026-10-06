-- ============================================================
-- 3DMP Service · 0065_labels.sql  (v43 — ЭПИК F: упаковка и маркировка)
-- Формы упаковки (места) и этикеток: грузовая этикетка, бирка позиции,
-- манипуляционные знаки. Печать (клиент). База знаний. Зависит от 0001..0064.
-- ============================================================

-- ---------- Упаковка (грузовые места) ----------
create table if not exists public.app_packages (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid references public.tenants (id),
  order_id     uuid references public.app_orders (id) on delete set null,
  package_no   int,
  kind         text not null default 'box',  -- box|pallet|crate|bag|other
  dims         text,                          -- Д×Ш×В, мм
  gross        numeric,
  net          numeric,
  positions    int,
  marks        text,                          -- манипуляционные знаки (хрупкое/верх/не кантовать)
  note         text,
  created_login text,
  created_at   timestamptz not null default now()
);
create index if not exists app_packages_idx on public.app_packages (tenant_id, order_id);
alter table public.app_packages enable row level security;

-- ---------- Этикетки ----------
create table if not exists public.app_labels (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid references public.tenants (id),
  order_id     uuid references public.app_orders (id) on delete set null,
  package_id   uuid references public.app_packages (id) on delete set null,
  label_type   text not null default 'cargo', -- cargo|position|tag
  recipient    text,
  sender       text default 'ООО «3Д Металлообработка Пресс»',
  order_number text,
  item         text,
  qty          numeric,
  dims         text,
  gross        numeric,
  net          numeric,
  position_no  int,
  identifier   text,
  cargo_no     int,
  cargo_total  int,
  note         text,
  created_login text,
  created_at   timestamptz not null default now()
);
create index if not exists app_labels_idx on public.app_labels (tenant_id, label_type, order_id);
alter table public.app_labels enable row level security;

-- ================= Упаковка: RPC =================
create or replace function public.app_package_list(p_token uuid, p_q text default null)
returns table (id uuid, order_number text, package_no int, kind text, dims text, gross numeric, net numeric,
               positions int, marks text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query
    select p.id, o.number, p.package_no, p.kind, p.dims, p.gross, p.net, p.positions, p.marks, p.created_at
    from public.app_packages p left join public.app_orders o on o.id=p.order_id
    where (urole='admin' or p.tenant_id=ten)
      and (qq='' or lower(coalesce(o.number,'')) like '%'||qq||'%' or lower(coalesce(p.dims,'')) like '%'||qq||'%')
    order by coalesce(o.number,''), p.package_no;
end $$;

create or replace function public.app_package_kpi(p_token uuid)
returns table (packages bigint, gross_sum numeric, net_sum numeric, positions_sum bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select count(*), coalesce(sum(gross),0), coalesce(sum(net),0), coalesce(sum(positions),0)
    from public.app_packages where (urole='admin' or tenant_id=ten);
end $$;

create or replace function public.app_package_save(p_token uuid, p_id uuid, p_order_id uuid, p_package_no int,
  p_kind text, p_dims text, p_gross numeric, p_net numeric, p_positions int, p_marks text, p_note text)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; ulogin text; pid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director','chief','master') then raise exception 'Недостаточно прав'; end if;
  if p_id is null then
    insert into public.app_packages (tenant_id, order_id, package_no, kind, dims, gross, net, positions, marks, note, created_login)
    values (ten, p_order_id, p_package_no, coalesce(nullif(trim(p_kind),''),'box'), nullif(trim(p_dims),''),
            p_gross, p_net, p_positions, nullif(trim(p_marks),''), nullif(trim(p_note),''), ulogin)
    returning id into pid;
    return query select pid, 'Грузовое место добавлено';
  else
    update public.app_packages set order_id=p_order_id, package_no=p_package_no, kind=coalesce(nullif(trim(p_kind),''),kind),
      dims=nullif(trim(p_dims),''), gross=p_gross, net=p_net, positions=p_positions, marks=nullif(trim(p_marks),''), note=nullif(trim(p_note),'')
     where id=p_id and (urole='admin' or tenant_id=ten) returning id into pid;
    return query select pid, 'Грузовое место обновлено';
  end if;
end $$;

create or replace function public.app_package_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  delete from public.app_packages where id=p_id and (urole='admin' or tenant_id=ten);
  return query select true,'Грузовое место удалено';
end $$;

-- ================= Этикетки: RPC =================
create or replace function public.app_label_list(p_token uuid, p_type text default null, p_q text default null)
returns table (id uuid, label_type text, order_number text, recipient text, sender text, item text, qty numeric,
               dims text, gross numeric, net numeric, position_no int, identifier text, cargo_no int, cargo_total int, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query
    select l.id, l.label_type, l.order_number, l.recipient, l.sender, l.item, l.qty, l.dims, l.gross, l.net,
           l.position_no, l.identifier, l.cargo_no, l.cargo_total, l.created_at
    from public.app_labels l
    where (urole='admin' or l.tenant_id=ten)
      and (coalesce(p_type,'')='' or l.label_type=p_type)
      and (qq='' or lower(coalesce(l.recipient,'')) like '%'||qq||'%' or lower(coalesce(l.item,'')) like '%'||qq||'%' or lower(coalesce(l.order_number,'')) like '%'||qq||'%')
    order by l.created_at desc;
end $$;

create or replace function public.app_label_kpi(p_token uuid)
returns table (total bigint, cargo bigint, pos_lbl bigint, tag_lbl bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select count(*), count(*) filter (where label_type='cargo'),
    count(*) filter (where label_type='position'), count(*) filter (where label_type='tag')
    from public.app_labels where (urole='admin' or tenant_id=ten);
end $$;

create or replace function public.app_label_save(p_token uuid, p_id uuid, p_order_id uuid, p_package_id uuid,
  p_label_type text, p_recipient text, p_sender text, p_item text, p_qty numeric, p_dims text,
  p_gross numeric, p_net numeric, p_position_no int, p_identifier text, p_cargo_no int, p_cargo_total int, p_note text)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; ulogin text; lid uuid; onum text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director','chief','master','supply') then raise exception 'Недостаточно прав'; end if;
  onum := (select number from public.app_orders where id=p_order_id);
  if p_id is null then
    insert into public.app_labels (tenant_id, order_id, package_id, label_type, recipient, sender, order_number, item, qty,
      dims, gross, net, position_no, identifier, cargo_no, cargo_total, note, created_login)
    values (ten, p_order_id, p_package_id, coalesce(nullif(trim(p_label_type),''),'cargo'),
            nullif(trim(p_recipient),''), coalesce(nullif(trim(p_sender),''),'ООО «3Д Металлообработка Пресс»'),
            onum, nullif(trim(p_item),''), p_qty, nullif(trim(p_dims),''), p_gross, p_net, p_position_no,
            nullif(trim(p_identifier),''), p_cargo_no, p_cargo_total, nullif(trim(p_note),''), ulogin)
    returning id into lid;
    return query select lid, 'Этикетка сохранена';
  else
    update public.app_labels set order_id=p_order_id, package_id=p_package_id,
      label_type=coalesce(nullif(trim(p_label_type),''),label_type), recipient=nullif(trim(p_recipient),''),
      sender=coalesce(nullif(trim(p_sender),''),sender), order_number=onum, item=nullif(trim(p_item),''), qty=p_qty,
      dims=nullif(trim(p_dims),''), gross=p_gross, net=p_net, position_no=p_position_no, identifier=nullif(trim(p_identifier),''),
      cargo_no=p_cargo_no, cargo_total=p_cargo_total, note=nullif(trim(p_note),'')
     where id=p_id and (urole='admin' or tenant_id=ten) returning id into lid;
    return query select lid, 'Этикетка обновлена';
  end if;
end $$;

create or replace function public.app_label_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  delete from public.app_labels where id=p_id and (urole='admin' or tenant_id=ten);
  return query select true,'Этикетка удалена';
end $$;

grant execute on function public.app_package_list(uuid,text) to anon, authenticated;
grant execute on function public.app_package_kpi(uuid) to anon, authenticated;
grant execute on function public.app_package_save(uuid,uuid,uuid,int,text,text,numeric,numeric,int,text,text) to anon, authenticated;
grant execute on function public.app_package_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_label_list(uuid,text,text) to anon, authenticated;
grant execute on function public.app_label_kpi(uuid) to anon, authenticated;
grant execute on function public.app_label_save(uuid,uuid,uuid,uuid,text,text,text,text,numeric,text,numeric,numeric,int,text,int,int,text) to anon, authenticated;
grant execute on function public.app_label_delete(uuid,uuid) to anon, authenticated;

-- ---------- Демо (тенант A) ----------
insert into public.app_packages (tenant_id, order_id, package_no, kind, dims, gross, net, positions, marks, note, created_login)
select 'aaaaaaaa-0000-0000-0000-000000000001',
  (select id from public.app_orders where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' order by created_at limit 1),
  v.no, v.kind, v.dims, v.gross, v.net, v.pos, v.marks, v.note, 'master'
from (values
  (1,'crate','1200×800×600', 340, 300, 4, 'Верх, не кантовать', 'Основное место'),
  (2,'pallet','1200×800×400', 180, 160, 2, 'Хрупкое, верх', 'Комплектующие')
) as v(no,kind,dims,gross,net,pos,marks,note)
where not exists (select 1 from public.app_packages where tenant_id='aaaaaaaa-0000-0000-0000-000000000001');

insert into public.app_labels (tenant_id, order_id, package_id, label_type, recipient, order_number, item, qty, dims, gross, net, cargo_no, cargo_total, created_login)
select 'aaaaaaaa-0000-0000-0000-000000000001',
  p.order_id, p.id, 'cargo', 'ООО «Заказчик-1»', o.number, 'Штамп вырубной', 4, p.dims, p.gross, p.net, p.package_no, 2, 'master'
from public.app_packages p join public.app_orders o on o.id=p.order_id
where p.tenant_id='aaaaaaaa-0000-0000-0000-000000000001'
  and not exists (select 1 from public.app_labels where tenant_id='aaaaaaaa-0000-0000-0000-000000000001');

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Упаковка','Упаковка и маркировка груза (B37)',
   'Модуль «Упаковка и маркировка»: грузовые места (вид: коробка/паллета/ящик, габариты, брутто/нетто, число позиций, манипуляционные знаки) и этикетки: грузовая (получатель/отправитель, № заявки, товар, габариты, брутто/нетто, 1/3), бирка позиции (№ заявки, № позиции, описание, идентификатор, количество, срок) и манипуляционные знаки. Печать этикеток — из карточки.',
   'упаковка маркировка грузовая этикетка бирка брутто нетто манипуляционные знаки')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Упаковка и маркировка груза (B37)');
