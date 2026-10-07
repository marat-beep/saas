-- ============================================================
-- 3DMP Service · 0133_service_customer_card.sql  (S10 — карточка завода/заказчика)
-- Заказчик (завод/предприятие) с его заявками, оборудованием, гарантиями и KPI.
-- Идемпотентно. Зависит от 0001..0132.
-- ============================================================

-- ---------- Карточка заказчика (сводка) ----------
drop function if exists public.app_customer_card(uuid,uuid);
create or replace function public.app_customer_card(p_token uuid, p_customer_id uuid)
returns table (id uuid, name text, inn text, contact_person text, phone text, email text, address text, note text,
               requests bigint, open_requests bigint, done_requests bigint, cost_sum numeric,
               equipment_count bigint, warranties bigint, active_warranties bigint, contracts bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  select s.urole into urole from public.app_session_user(p_token) s;
  if urole is null then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token);
  return query
    select c.id, c.name, c.inn, c.contact_person, c.phone, c.email, c.address, c.note,
           (select count(*) from public.app_service_requests r where r.customer_id = c.id),
           (select count(*) from public.app_service_requests r where r.customer_id = c.id and r.status not in ('done','cancelled')),
           (select count(*) from public.app_service_requests r where r.customer_id = c.id and r.status = 'done'),
           coalesce((select sum(coalesce(r.cost,0)+coalesce(r.parts_cost,0)) from public.app_service_requests r where r.customer_id = c.id),0),
           (select count(distinct r.equipment_id) from public.app_service_requests r where r.customer_id = c.id and r.equipment_id is not null),
           (select count(*) from public.app_warranties w where w.customer_id = c.id),
           (select count(*) from public.app_warranties w where w.customer_id = c.id and w.active and (w.end_date is null or w.end_date >= current_date)),
           (select count(*) from public.app_service_contracts k where k.customer_id = c.id)
      from public.app_customers c
     where c.id = p_customer_id and (urole='admin' or c.tenant_id = ten);
end $$;

-- ---------- Заявки заказчика ----------
drop function if exists public.app_customer_requests(uuid,uuid);
create or replace function public.app_customer_requests(p_token uuid, p_customer_id uuid)
returns table (id uuid, number text, title text, kind text, status text, priority text, equipment text,
               reported_at timestamptz, resolved_at timestamptz, cost numeric, parts_cost numeric, engineer text, sla_state text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  select s.urole into urole from public.app_session_user(p_token) s;
  if urole is null then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token);
  return query
    select r.id, r.number, r.title, r.kind, r.status, r.priority, e.name, r.reported_at, r.resolved_at,
           r.cost, r.parts_cost, coalesce(r.assigned_login, r.engineer),
           case when r.status = 'done' then 'closed'
                when r.resolve_due is not null and r.resolve_due < now() then 'overdue'
                when r.resolve_due is not null and r.resolve_due < now() + interval '2 hours' then 'warn'
                else 'ok' end
      from public.app_service_requests r
      left join public.app_equipment e on e.id = r.equipment_id
     where r.customer_id = p_customer_id and (urole='admin' or r.tenant_id = ten)
     order by coalesce(r.reported_at, r.created_at) desc;
end $$;

-- ---------- Оборудование заказчика ----------
drop function if exists public.app_customer_equipment(uuid,uuid);
create or replace function public.app_customer_equipment(p_token uuid, p_customer_id uuid)
returns table (equipment_id uuid, name text, code text, kind text, warranty_license text, warranty_number text,
               warranty_end date, requests bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  select s.urole into urole from public.app_session_user(p_token) s;
  if urole is null then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token);
  return query
    select e.id, e.name, e.code, e.kind,
           (select w.license_no from public.app_warranties w where w.equipment_id=e.id and w.active order by w.end_date desc nulls last limit 1),
           (select w.number from public.app_warranties w where w.equipment_id=e.id and w.active order by w.end_date desc nulls last limit 1),
           (select w.end_date from public.app_warranties w where w.equipment_id=e.id and w.active order by w.end_date desc nulls last limit 1),
           (select count(*) from public.app_service_requests r where r.equipment_id=e.id)
      from public.app_equipment e
     where (urole='admin' or e.tenant_id = ten)
       and (e.id in (select r.equipment_id from public.app_service_requests r where r.customer_id = p_customer_id and r.equipment_id is not null)
            or e.id in (select w.equipment_id from public.app_warranties w where w.customer_id = p_customer_id and w.equipment_id is not null))
     order by e.name;
end $$;

grant execute on function public.app_customer_card(uuid,uuid)        to anon, authenticated;
grant execute on function public.app_customer_requests(uuid,uuid)    to anon, authenticated;
grant execute on function public.app_customer_equipment(uuid,uuid)   to anon, authenticated;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Сервис','Как найти станок, паспорт, историю ремонтов и завод',
   'Станок: app_service_find_equipment (поиск по названию/коду/гарантии) или apps/equipment. Паспорт станка: app_equipment_passport (гарантия, KPI, ТОиР, телеметрия) + история ремонта app_service_equipment_history. Завод/заказчик: карточка app_customer_card + заявки app_customer_requests + оборудование app_customer_equipment (в UI — «🏢 Заказчик» в карточке заявки). Заявки по станку/заводу: app_service_list / app_service_equipment_history / app_customer_requests. Системный поиск в шапке (app_global_search) ищет заявки, станки, заказчиков, БЗ.',
   'найти станок паспорт история ремонтов завод заказчик заявки поиск')
) as v(category,question,answer,tags)
where not exists (
  select 1 from public.app_knowledge
   where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001' and question = 'Как найти станок, паспорт, историю ремонтов и завод'
);
