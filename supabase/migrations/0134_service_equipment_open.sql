-- ============================================================
-- 3DMP Service · 0134_service_equipment_open.sql  (S11 — открытые заявки по станку)
-- Открытые сервисные заявки по оборудованию (для паспорта станка).
-- Идемпотентно. Зависит от 0001..0133.
-- ============================================================

drop function if exists public.app_service_equipment_open(uuid,uuid);
create or replace function public.app_service_equipment_open(p_token uuid, p_equipment_id uuid)
returns table (id uuid, number text, title text, status text, priority text, reported_at timestamptz, engineer text, sla_state text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  select s.urole into urole from public.app_session_user(p_token) s;
  if urole is null then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token);
  return query
    select r.id, r.number, r.title, r.status, r.priority, r.reported_at, coalesce(r.assigned_login, r.engineer),
           case when r.resolve_due is not null and r.resolve_due < now() then 'overdue'
                when r.resolve_due is not null and r.resolve_due < now() + interval '2 hours' then 'warn'
                else 'ok' end
      from public.app_service_requests r
     where r.equipment_id = p_equipment_id and r.status not in ('done','cancelled') and (urole='admin' or r.tenant_id = ten)
     order by (r.priority='critical') desc, r.reported_at desc;
end $$;

grant execute on function public.app_service_equipment_open(uuid,uuid) to anon, authenticated;
