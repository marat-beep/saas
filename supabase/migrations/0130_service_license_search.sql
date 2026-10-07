-- ============================================================
-- 3DMP Service · 0130_service_license_search.sql  (S8 — лицензии гарантий, идентификация, поиск)
-- Генерация лицензионных номеров гарантий (срок, идентификация), расширенный
-- поиск по станкам/ремонтам/номерам гарантий. Идемпотентно. Зависит от 0001..0129.
-- ============================================================

create sequence if not exists public.app_warranty_seq;

alter table public.app_warranties add column if not exists license_no text;

-- выровнять последовательность под существующие
update public.app_warranties set license_no = 'WR-' || to_char(coalesce(start_date, current_date), 'YYYY') || '-' || lpad(nextval('public.app_warranty_seq')::text, 5, '0')
 where license_no is null;
select setval('public.app_warranty_seq', greatest(coalesce((select count(*) from public.app_warranties),0),1), true);

create unique index if not exists app_warranties_license_idx on public.app_warranties (tenant_id, license_no);

-- ---------- Список гарантий (с лицензией) ----------
drop function if exists public.app_warranty_list(uuid);
create or replace function public.app_warranty_list(p_token uuid)
returns table (id uuid, equipment_id uuid, equipment text, customer text, number text, license_no text, provider text,
               start_date date, end_date date, active boolean, days_left integer, status text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  select s.urole into urole from public.app_session_user(p_token) s;
  if urole is null then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token);
  return query
    select w.id, w.equipment_id, e.name, c.name, w.number, w.license_no, w.provider, w.start_date, w.end_date, w.active,
           case when w.end_date is not null then (w.end_date - current_date) else null end,
           case when not w.active then 'off'
                when w.start_date > current_date then 'planned'
                when w.end_date is not null and w.end_date < current_date then 'expired'
                else 'active' end
      from public.app_warranties w
      left join public.app_equipment e on e.id = w.equipment_id
      left join public.app_customers c on c.id = w.customer_id
     where (urole='admin' or w.tenant_id = ten)
     order by w.end_date desc nulls last;
end $$;

-- ---------- Сохранение гарантии (генерация лицензии) ----------
drop function if exists public.app_warranty_save(uuid,uuid,uuid,uuid,text,text,date,date,text,text,boolean);
create or replace function public.app_warranty_save(
  p_token uuid, p_id uuid, p_equipment_id uuid, p_customer_id uuid, p_number text, p_provider text,
  p_start_date date, p_end_date date, p_coverage text, p_terms text, p_active boolean
) returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ulogin text; ten uuid; wid uuid; lic text;
begin
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  if uid is null then return query select false, 'Сессия недействительна', null::uuid; return; end if;
  if not public.app_can(p_token, 'service', 'edit') then return query select false, 'Нет прав', null::uuid; return; end if;
  if p_equipment_id is null then return query select false, 'Выберите оборудование', null::uuid; return; end if;
  ten := public.app_my_tenant(p_token);
  if p_id is null then
    lic := 'WR-' || to_char(coalesce(p_start_date, current_date), 'YYYY') || '-' || lpad(nextval('public.app_warranty_seq')::text, 5, '0');
    insert into public.app_warranties (tenant_id, equipment_id, customer_id, number, license_no, provider, start_date, end_date, coverage, terms, active, created_by, created_login)
    values (ten, p_equipment_id, p_customer_id, nullif(trim(p_number),''), lic, coalesce(nullif(trim(p_provider),''),'manufacturer'),
            coalesce(p_start_date, current_date), p_end_date, nullif(trim(p_coverage),''), nullif(trim(p_terms),''), coalesce(p_active,true), uid, ulogin)
    returning app_warranties.id into wid;
    return query select true, 'Гарантия сохранена (лицензия ' || lic || ')', wid;
  else
    update public.app_warranties w set equipment_id=p_equipment_id, customer_id=p_customer_id, number=nullif(trim(p_number),''),
      provider=coalesce(nullif(trim(p_provider),''),w.provider), start_date=coalesce(p_start_date,w.start_date), end_date=p_end_date,
      coverage=nullif(trim(p_coverage),''), terms=nullif(trim(p_terms),''), active=coalesce(p_active,w.active),
      license_no = coalesce(w.license_no, 'WR-' || to_char(coalesce(p_start_date, current_date), 'YYYY') || '-' || lpad(nextval('public.app_warranty_seq')::text, 5, '0'))
     where w.id=p_id and (public.app_is_platform_admin(p_token) or w.tenant_id=ten);
    if not found then return query select false, 'Гарантия не найдена', null::uuid; return; end if;
    return query select true, 'Гарантия сохранена', p_id;
  end if;
end $$;

-- ---------- Список заявок v3: расширенный поиск (станок/код/гарантия/лицензия) ----------
drop function if exists public.app_service_list(uuid,text);
create or replace function public.app_service_list(p_token uuid, p_q text default null)
returns table (id uuid, number text, customer text, equipment text, title text, kind text, status text, priority text,
               channel text, source text, is_warranty boolean, assigned_login text, engineer text,
               scheduled_date date, reported_at timestamptz, response_due timestamptz, resolve_due timestamptz,
               first_response_at timestamptz, resolved_at timestamptz, cost numeric, parts_cost numeric,
               sla_state text, warranty_license text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query
    select s.id, s.number, c.name, e.name, s.title, s.kind, s.status, s.priority,
           s.channel, s.source, s.is_warranty, s.assigned_login, s.engineer,
           s.scheduled_date, s.reported_at, s.response_due, s.resolve_due,
           s.first_response_at, s.resolved_at, s.cost, s.parts_cost,
           case when s.status = 'done' then 'closed'
                when s.resolve_due is not null and s.resolve_due < now() then 'overdue'
                when s.resolve_due is not null and s.resolve_due < now() + interval '2 hours' then 'warn'
                else 'ok' end,
           w.license_no, s.created_at
    from public.app_service_requests s
    left join public.app_customers c on c.id = s.customer_id
    left join public.app_equipment e on e.id = s.equipment_id
    left join public.app_warranties w on w.id = s.warranty_id
    where (urole='admin' or s.tenant_id = ten)
      and (qq=''
        or lower(s.title) like '%'||qq||'%' or lower(coalesce(s.number,'')) like '%'||qq||'%'
        or lower(coalesce(c.name,'')) like '%'||qq||'%'
        or lower(coalesce(e.name,'')) like '%'||qq||'%' or lower(coalesce(e.code,'')) like '%'||qq||'%'
        or lower(coalesce(s.engineer,'')) like '%'||qq||'%' or lower(coalesce(s.assigned_login,'')) like '%'||qq||'%'
        or lower(coalesce(s.fault_code,'')) like '%'||qq||'%'
        or lower(coalesce(w.number,'')) like '%'||qq||'%' or lower(coalesce(w.license_no,'')) like '%'||qq||'%')
    order by (s.priority='critical') desc, s.created_at desc;
end $$;

-- ---------- Поиск: оборудование/гарантия/ремонты ----------
drop function if exists public.app_service_find_equipment(uuid,text,integer);
create or replace function public.app_service_find_equipment(p_token uuid, p_q text, p_limit integer default 30)
returns table (equipment_id uuid, name text, code text, kind text, warranty_license text, warranty_number text,
               warranty_end date, requests bigint, last_repair timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; qq text;
begin
  select s.urole into urole from public.app_session_user(p_token) s;
  if urole is null then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query
    select e.id, e.name, e.code, e.kind,
           (select w.license_no from public.app_warranties w where w.equipment_id=e.id and w.active order by w.end_date desc nulls last limit 1),
           (select w.number from public.app_warranties w where w.equipment_id=e.id and w.active order by w.end_date desc nulls last limit 1),
           (select w.end_date from public.app_warranties w where w.equipment_id=e.id and w.active order by w.end_date desc nulls last limit 1),
           (select count(*) from public.app_service_requests r where r.equipment_id=e.id),
           (select max(coalesce(r.resolved_at,r.closed_at)) from public.app_service_requests r where r.equipment_id=e.id)
      from public.app_equipment e
     where (urole='admin' or e.tenant_id = ten)
       and (qq='' or lower(coalesce(e.name,'')) like '%'||qq||'%' or lower(coalesce(e.code,'')) like '%'||qq||'%'
            or exists (select 1 from public.app_warranties w where w.equipment_id=e.id
                        and (lower(coalesce(w.number,'')) like '%'||qq||'%' or lower(coalesce(w.license_no,'')) like '%'||qq||'%')))
     order by e.name
     limit greatest(1, least(coalesce(p_limit,30),100));
end $$;

grant execute on function public.app_warranty_list(uuid)                                   to anon, authenticated;
grant execute on function public.app_warranty_save(uuid,uuid,uuid,uuid,text,text,date,date,text,text,boolean) to anon, authenticated;
grant execute on function public.app_service_list(uuid,text)                               to anon, authenticated;
grant execute on function public.app_service_find_equipment(uuid,text,integer)             to anon, authenticated;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Сервис','Лицензии гарантий и поиск станков/ремонтов',
   'Каждой гарантии присваивается лицензионный (учётный) номер WR-ГГГГ-NNNNN (app_warranties.license_no) — по нему идентифицируют оборудование и гарантийный период; внешний номер производителя — в поле number. Поиск по заявкам (app_service_list) идёт по номеру заявки, теме, заказчику, станку и коду, инженеру, коду ошибки и по номерам гарантии/лицензии. Поиск по оборудованию — app_service_find_equipment (название/код/номер гарантии), из него — переход в паспорт станка и историю ремонта.',
   'лицензия гарантия WR номер идентификация поиск станок ремонт паспорт')
) as v(category,question,answer,tags)
where not exists (
  select 1 from public.app_knowledge
   where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001' and question = 'Лицензии гарантий и поиск станков/ремонтов'
);
