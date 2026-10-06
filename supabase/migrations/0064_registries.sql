-- ============================================================
-- 3DMP Service · 0064_registries.sql  (v42 — ЭПИК F: реестры)
-- Реестры: гравирование (заказы на гравировку), поставщики (реестр/аккредитация),
-- ТЭО (технико-экономическое обоснование: статьи и итог, из заявки).
-- База знаний. Зависит от 0001..0063.
-- ============================================================

-- ---------- Гравирование ----------
create sequence if not exists public.app_engraving_seq;
create table if not exists public.app_engraving (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid references public.tenants (id),
  number           text,
  order_id         uuid references public.app_orders (id) on delete set null,
  detail           text,
  machine          text,
  engraving_number text,
  minutes          numeric,
  ship_date        date,
  status           text not null default 'new', -- new|in_progress|done|cancelled
  note             text,
  created_login    text,
  created_at       timestamptz not null default now()
);
create index if not exists app_engraving_idx on public.app_engraving (tenant_id, status, ship_date);
alter table public.app_engraving enable row level security;

-- ---------- Поставщики ----------
create table if not exists public.app_suppliers (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid references public.tenants (id),
  name       text not null,
  inn        text,
  contact    text,
  phone      text,
  email      text,
  category   text,   -- металл|инструмент|комплектующие|услуги|прочее
  rating     numeric default 0,
  status     text not null default 'pending', -- pending|accredited|blocked
  note       text,
  created_login text,
  created_at timestamptz not null default now()
);
create index if not exists app_suppliers_idx on public.app_suppliers (tenant_id, status, category);
alter table public.app_suppliers enable row level security;

-- ---------- ТЭО ----------
create sequence if not exists public.app_teo_seq;
create table if not exists public.app_teo (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  number        text,
  order_id      uuid references public.app_orders (id) on delete set null,
  title         text not null,
  status        text not null default 'draft', -- draft|approved|rejected
  note          text,
  created_login text,
  created_at    timestamptz not null default now()
);
create index if not exists app_teo_idx on public.app_teo (tenant_id, status);
alter table public.app_teo enable row level security;

create table if not exists public.app_teo_lines (
  id       uuid primary key default gen_random_uuid(),
  teo_id   uuid references public.app_teo (id) on delete cascade,
  kind     text not null default 'other', -- consumables|metal|labor|service|other
  name     text not null,
  qty      numeric default 1,
  price    numeric default 0,
  amount   numeric default 0,
  sort     int default 100
);
create index if not exists app_teo_lines_idx on public.app_teo_lines (teo_id);
alter table public.app_teo_lines enable row level security;

-- ================= Гравирование: RPC =================
create or replace function public.app_engraving_list(p_token uuid, p_q text default null)
returns table (id uuid, number text, order_id uuid, order_number text, detail text, machine text, engraving_number text,
               minutes numeric, ship_date date, status text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query
    select g.id, g.number, g.order_id, o.number, g.detail, g.machine, g.engraving_number, g.minutes, g.ship_date, g.status, g.created_at
    from public.app_engraving g left join public.app_orders o on o.id = g.order_id
    where (urole='admin' or g.tenant_id = ten)
      and (qq='' or lower(coalesce(g.detail,'')) like '%'||qq||'%' or lower(coalesce(g.engraving_number,'')) like '%'||qq||'%' or lower(coalesce(o.number,'')) like '%'||qq||'%')
    order by (g.status='done'), coalesce(g.ship_date, current_date + 365), g.created_at desc;
end $$;

create or replace function public.app_engraving_kpi(p_token uuid)
returns table (total bigint, queue bigint, done bigint, minutes_sum numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select count(*), count(*) filter (where status in ('new','in_progress')),
    count(*) filter (where status='done'), coalesce(sum(minutes),0)
    from public.app_engraving where (urole='admin' or tenant_id = ten);
end $$;

create or replace function public.app_engraving_save(p_token uuid, p_id uuid, p_order_id uuid, p_detail text,
  p_machine text, p_engraving_number text, p_minutes numeric, p_ship_date date, p_note text)
returns table (id uuid, number text, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; ulogin text; gid uuid; gnum text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director','chief','master','technologist') then raise exception 'Недостаточно прав'; end if;
  if coalesce(trim(p_detail),'') = '' and p_order_id is null then raise exception 'Укажите деталь или заявку'; return; end if;
  if p_id is null then
    gnum := 'ENG-' || lpad(nextval('public.app_engraving_seq')::text, 5, '0');
    insert into public.app_engraving (tenant_id, number, order_id, detail, machine, engraving_number, minutes, ship_date, note, created_login)
    values (ten, gnum, p_order_id, nullif(trim(p_detail),''), nullif(trim(p_machine),''), nullif(trim(p_engraving_number),''),
            p_minutes, p_ship_date, nullif(trim(p_note),''), ulogin)
    returning id into gid;
    return query select gid, gnum, 'Заказ на гравирование создан';
  else
    update public.app_engraving set order_id=p_order_id, detail=nullif(trim(p_detail),''), machine=nullif(trim(p_machine),''),
      engraving_number=nullif(trim(p_engraving_number),''), minutes=p_minutes, ship_date=p_ship_date, note=nullif(trim(p_note),'')
     where id=p_id and (urole='admin' or tenant_id=ten) returning id, number into gid, gnum;
    return query select gid, gnum, 'Заказ обновлён';
  end if;
end $$;

create or replace function public.app_engraving_set_status(p_token uuid, p_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if p_status not in ('new','in_progress','done','cancelled') then return query select false,'Неверный статус'; return; end if;
  update public.app_engraving set status=p_status where id=p_id and (urole='admin' or tenant_id=ten);
  return query select true,'Статус обновлён';
end $$;

-- ================= Поставщики: RPC =================
create or replace function public.app_suppliers_list(p_token uuid, p_category text default null, p_q text default null)
returns table (id uuid, name text, inn text, contact text, phone text, email text, category text, rating numeric, status text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query
    select s.id, s.name, s.inn, s.contact, s.phone, s.email, s.category, s.rating, s.status, s.created_at
    from public.app_suppliers s
    where (urole='admin' or s.tenant_id = ten)
      and (coalesce(p_category,'')='' or s.category = p_category)
      and (qq='' or lower(s.name) like '%'||qq||'%' or lower(coalesce(s.inn,'')) like '%'||qq||'%' or lower(coalesce(s.contact,'')) like '%'||qq||'%')
    order by (s.status='blocked'), s.rating desc nulls last, s.name;
end $$;

create or replace function public.app_suppliers_kpi(p_token uuid)
returns table (total bigint, accredited bigint, pending bigint, blocked bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select count(*), count(*) filter (where status='accredited'),
    count(*) filter (where status='pending'), count(*) filter (where status='blocked')
    from public.app_suppliers where (urole='admin' or tenant_id = ten);
end $$;

create or replace function public.app_suppliers_save(p_token uuid, p_id uuid, p_name text, p_inn text, p_contact text,
  p_phone text, p_email text, p_category text, p_rating numeric, p_note text)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; ulogin text; sid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director','supply') then raise exception 'Недостаточно прав'; end if;
  if coalesce(trim(p_name),'') = '' then raise exception 'Укажите наименование поставщика'; return; end if;
  if p_id is null then
    insert into public.app_suppliers (tenant_id, name, inn, contact, phone, email, category, rating, note, created_login)
    values (ten, trim(p_name), nullif(trim(p_inn),''), nullif(trim(p_contact),''), nullif(trim(p_phone),''),
            nullif(trim(p_email),''), nullif(trim(p_category),''), coalesce(p_rating,0), nullif(trim(p_note),''), ulogin)
    returning id into sid;
    return query select sid, 'Поставщик добавлен';
  else
    update public.app_suppliers set name=trim(p_name), inn=nullif(trim(p_inn),''), contact=nullif(trim(p_contact),''),
      phone=nullif(trim(p_phone),''), email=nullif(trim(p_email),''), category=nullif(trim(p_category),''),
      rating=coalesce(p_rating,rating), note=nullif(trim(p_note),'')
     where id=p_id and (urole='admin' or tenant_id=ten) returning id into sid;
    return query select sid, 'Поставщик обновлён';
  end if;
end $$;

create or replace function public.app_suppliers_set_status(p_token uuid, p_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if p_status not in ('pending','accredited','blocked') then return query select false,'Неверный статус'; return; end if;
  update public.app_suppliers set status=p_status where id=p_id and (urole='admin' or tenant_id=ten);
  return query select true,'Статус обновлён';
end $$;

-- ================= ТЭО: RPC =================
create or replace function public.app_teo_total(p_teo_id uuid) returns numeric
language sql stable security definer set search_path = public
as $$ select coalesce(sum(amount),0) from public.app_teo_lines where teo_id = p_teo_id $$;

create or replace function public.app_teo_list(p_token uuid, p_q text default null)
returns table (id uuid, number text, title text, order_number text, status text, total numeric, lines bigint, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query
    select t.id, t.number, t.title, o.number, t.status,
      coalesce((select sum(l.amount) from public.app_teo_lines l where l.teo_id=t.id),0),
      (select count(*) from public.app_teo_lines l where l.teo_id=t.id), t.created_at
    from public.app_teo t left join public.app_orders o on o.id=t.order_id
    where (urole='admin' or t.tenant_id = ten)
      and (qq='' or lower(t.title) like '%'||qq||'%' or lower(coalesce(t.number,'')) like '%'||qq||'%')
    order by t.created_at desc;
end $$;

create or replace function public.app_teo_kpi(p_token uuid)
returns table (total bigint, drafts bigint, approved bigint, amount_sum numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select (select count(*) from public.app_teo where (urole='admin' or tenant_id=ten)),
      (select count(*) from public.app_teo where status='draft' and (urole='admin' or tenant_id=ten)),
      (select count(*) from public.app_teo where status='approved' and (urole='admin' or tenant_id=ten)),
      (select coalesce(sum(l.amount),0) from public.app_teo_lines l
        join public.app_teo t on t.id=l.teo_id where (urole='admin' or t.tenant_id=ten));
end $$;

create or replace function public.app_teo_save(p_token uuid, p_id uuid, p_order_id uuid, p_title text, p_note text)
returns table (id uuid, number text, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; ulogin text; tid uuid; tnum text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director','economist') then raise exception 'Недостаточно прав'; end if;
  if coalesce(trim(p_title),'') = '' then raise exception 'Укажите название ТЭО'; return; end if;
  if p_id is null then
    tnum := 'TEO-' || lpad(nextval('public.app_teo_seq')::text, 5, '0');
    insert into public.app_teo (tenant_id, number, order_id, title, note, created_login)
    values (ten, tnum, p_order_id, trim(p_title), nullif(trim(p_note),''), ulogin)
    returning id into tid;
    return query select tid, tnum, 'ТЭО создано';
  else
    update public.app_teo set order_id=p_order_id, title=trim(p_title), note=nullif(trim(p_note),'')
     where id=p_id and (urole='admin' or tenant_id=ten) returning id, number into tid, tnum;
    return query select tid, tnum, 'ТЭО обновлено';
  end if;
end $$;

create or replace function public.app_teo_lines_list(p_token uuid, p_teo_id uuid)
returns table (id uuid, kind text, name text, qty numeric, price numeric, amount numeric, sort int)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select l.id, l.kind, l.name, l.qty, l.price, l.amount, l.sort
    from public.app_teo_lines l join public.app_teo t on t.id=l.teo_id
    where l.teo_id=p_teo_id and (urole='admin' or t.tenant_id=ten)
    order by l.sort, l.name;
end $$;

create or replace function public.app_teo_line_save(p_token uuid, p_id uuid, p_teo_id uuid, p_kind text,
  p_name text, p_qty numeric, p_price numeric)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; lid uuid; amt numeric;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director','economist') then raise exception 'Недостаточно прав'; return; end if;
  if coalesce(trim(p_name),'') = '' then raise exception 'Укажите статью'; return; end if;
  if not exists (select 1 from public.app_teo where id=p_teo_id and (urole='admin' or tenant_id=ten)) then raise exception 'ТЭО не найдено'; end if;
  amt := coalesce(p_qty,1)*coalesce(p_price,0);
  if p_id is null then
    insert into public.app_teo_lines (teo_id, kind, name, qty, price, amount)
    values (p_teo_id, coalesce(nullif(trim(p_kind),''),'other'), trim(p_name), coalesce(p_qty,1), coalesce(p_price,0), amt)
    returning id into lid;
    return query select lid, 'Статья добавлена';
  else
    update public.app_teo_lines set kind=coalesce(nullif(trim(p_kind),''),kind), name=trim(p_name),
      qty=coalesce(p_qty,1), price=coalesce(p_price,0), amount=amt
     where id=p_id and teo_id=p_teo_id returning id into lid;
    return query select lid, 'Статья обновлена';
  end if;
end $$;

create or replace function public.app_teo_line_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  delete from public.app_teo_lines l using public.app_teo t
    where l.id=p_id and t.id=l.teo_id and (urole='admin' or t.tenant_id=ten);
  return query select true,'Статья удалена';
end $$;

create or replace function public.app_teo_set_status(p_token uuid, p_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; t text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if p_status not in ('draft','approved','rejected') then return query select false,'Неверный статус'; return; end if;
  select title into t from public.app_teo where id=p_id and (urole='admin' or tenant_id=ten);
  update public.app_teo set status=p_status where id=p_id and (urole='admin' or tenant_id=ten);
  if p_status='approved' then
    perform public.app_notif_roles_t(ten, array['admin','owner','director','economist'], 'ТЭО утверждено: '||coalesce(t,''), '', 'apps/teo/index.html');
  end if;
  return query select true,'Статус обновлён';
end $$;

create or replace function public.app_teo_from_order(p_token uuid, p_order_id uuid)
returns table (id uuid, number text, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; ulogin text; tid uuid; tnum text; o record;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select ao.* into o from public.app_orders ao where ao.id=p_order_id and (urole='admin' or ao.tenant_id=ten);
  if o.id is null then raise exception 'Заявка не найдена'; end if;
  tnum := 'TEO-' || lpad(nextval('public.app_teo_seq')::text, 5, '0');
  insert into public.app_teo (tenant_id, number, order_id, title, note, created_login)
  values (ten, tnum, p_order_id, 'ТЭО по заявке '||o.number, 'Создано из заявки', ulogin) returning id into tid;
  insert into public.app_teo_lines (teo_id, kind, name, qty, price, amount, sort)
  values (tid, 'other', coalesce(o.title,'Изделие'), 1, coalesce(o.amount,0), coalesce(o.amount,0), 10);
  return query select tid, tnum, 'ТЭО создано из заявки';
end $$;

grant execute on function public.app_engraving_list(uuid,text) to anon, authenticated;
grant execute on function public.app_engraving_kpi(uuid) to anon, authenticated;
grant execute on function public.app_engraving_save(uuid,uuid,uuid,text,text,text,numeric,date,text) to anon, authenticated;
grant execute on function public.app_engraving_set_status(uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_suppliers_list(uuid,text,text) to anon, authenticated;
grant execute on function public.app_suppliers_kpi(uuid) to anon, authenticated;
grant execute on function public.app_suppliers_save(uuid,uuid,text,text,text,text,text,text,numeric,text) to anon, authenticated;
grant execute on function public.app_suppliers_set_status(uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_teo_list(uuid,text) to anon, authenticated;
grant execute on function public.app_teo_kpi(uuid) to anon, authenticated;
grant execute on function public.app_teo_save(uuid,uuid,uuid,text,text) to anon, authenticated;
grant execute on function public.app_teo_lines_list(uuid,uuid) to anon, authenticated;
grant execute on function public.app_teo_line_save(uuid,uuid,uuid,text,text,numeric,numeric) to anon, authenticated;
grant execute on function public.app_teo_line_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_teo_set_status(uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_teo_from_order(uuid,uuid) to anon, authenticated;

-- ---------- Демо (тенант A) ----------
insert into public.app_suppliers (tenant_id, name, inn, contact, phone, email, category, rating, status, note, created_login)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.name, v.inn, v.contact, v.phone, v.email, v.cat, v.rating, v.status, v.note, 'supply'
from (values
  ('ООО «МеталлСервис»','7712345678','Иванов И.И.','+7 495 111-22-33','sales@metall.ru','металл',4.8,'accredited','Поставки конструкционной стали'),
  ('ООО «Инструмент-Про»','7798765432','Петров П.П.','+7 495 222-33-44','info@instr.ru','инструмент',4.5,'accredited','Твёрдосплавный инструмент'),
  ('ООО «ОснасткаПлюс»','7734567890','Сидоров А.А.','+7 812 333-44-55','zakaz@osnastka.ru','комплектующие',3.9,'pending','На аккредитации')
) as v(name,inn,contact,phone,email,cat,rating,status,note)
where not exists (select 1 from public.app_suppliers where tenant_id='aaaaaaaa-0000-0000-0000-000000000001');

insert into public.app_engraving (tenant_id, number, order_id, detail, machine, engraving_number, minutes, ship_date, status, created_login)
select 'aaaaaaaa-0000-0000-0000-000000000001', 'ENG-' || lpad(nextval('public.app_engraving_seq')::text,5,'0'),
  (select id from public.app_orders where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' order by created_at limit 1),
  'Маркировка партии деталей', 'Лазерный маркер', 'G-2026-001', 35, current_date + 2, 'in_progress', 'master'
where not exists (select 1 from public.app_engraving where tenant_id='aaaaaaaa-0000-0000-0000-000000000001');

insert into public.app_teo (tenant_id, number, order_id, title, status, note, created_login)
select 'aaaaaaaa-0000-0000-0000-000000000001', 'TEO-' || lpad(nextval('public.app_teo_seq')::text,5,'0'),
  (select id from public.app_orders where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' order by created_at limit 1),
  'ТЭО изготовления оснастки', 'draft', 'Демо-расчёт', 'economist'
where not exists (select 1 from public.app_teo where tenant_id='aaaaaaaa-0000-0000-0000-000000000001');

insert into public.app_teo_lines (teo_id, kind, name, qty, price, amount, sort)
select t.id, v.kind, v.name, v.qty, v.price, v.qty*v.price, v.sort
from public.app_teo t,
(values
  ('metal','Сталь 40Х, кг', 120, 85, 10),
  ('consumables','СОЖ и расходники, л', 20, 350, 20),
  ('labor','Слесарные работы, ч', 40, 700, 30),
  ('labor','Фрезерная обработка, ч', 60, 1200, 40),
  ('service','Термообработка, кг', 120, 90, 50)
) as v(kind,name,qty,price,sort)
where t.tenant_id='aaaaaaaa-0000-0000-0000-000000000001'
  and not exists (select 1 from public.app_teo_lines l where l.teo_id=t.id);

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Реестры','Реестр гравирования (B36)',
   'Модуль «Гравирование»: заказ на гравировку (ENG-NNNNN) с заявкой, деталью, станком, номером гравировки, временем (мин) и датой отгрузки. Статусы: новый → в работе → выполнен. KPI: всего, в очереди, выполнено, сумма минут.',
   'гравирование маркировка реестр отгрузка время'),
  ('Реестры','Реестр поставщиков (B33/закупки)',
   'Модуль «Поставщики»: карточки контрагентов (наименование, ИНН, контакт, категория, рейтинг), статусы: на аккредитации → аккредитован → заблокирован. Связь с закупками и порталом поставщика. KPI: всего, аккредитовано, на аккредитации, заблокировано.',
   'поставщики реестр аккредитация ИНН рейтинг'),
  ('Реестры','ТЭО — технико-экономическое обоснование',
   'Модуль «ТЭО»: обоснование (TEO-NNNNN) со статьями (металл, расходники, работы, услуги, прочее). Итог считается по статьям. Можно создать из заявки одной кнопкой. Статусы: черновик → утверждено/отклонено. KPI: всего, черновиков, утверждено, сумма.',
   'ТЭО обоснование статьи себестоимость металл работы услуги')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Реестр гравирования (B36)');
