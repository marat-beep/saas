-- ============================================================
-- 3DMP Service · 0135_mnt_service_link.sql  (Модуль ТОиР → сервис: заявка по плану)
-- Ручное создание сервисной заявки из плана ТОиР (связка ППР ↔ сервис).
-- Идемпотентно. Зависит от 0001..0134.
-- ============================================================

drop function if exists public.app_mnt_plan_service_request(uuid,uuid);
create or replace function public.app_mnt_plan_service_request(p_token uuid, p_plan_id uuid)
returns table (ok boolean, message text, request_id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ulogin text; ten uuid; p record; sid uuid; snum text; respmin int; resmin int;
begin
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  if uid is null then return query select false, 'Сессия недействительна', null::uuid; return; end if;
  if not public.app_can(p_token,'service','edit') then return query select false, 'Нет прав', null::uuid; return; end if;
  ten := public.app_my_tenant(p_token);
  select p.id, p.tenant_id, p.equipment_id, p.kind, e.name as eq_name into p
    from public.app_mnt_plans p left join public.app_equipment e on e.id = p.equipment_id
   where p.id = p_plan_id and (public.app_is_platform_admin(p_token) or p.tenant_id = ten);
  if p.id is null then return query select false, 'План не найден', null::uuid; return; end if;
  if p.equipment_id is null then return query select false, 'В плане не указано оборудование', null::uuid; return; end if;
  if exists (select 1 from public.app_service_requests r where r.plan_id = p.id and r.status not in ('done','cancelled'))
     or exists (select 1 from public.app_service_requests r where r.equipment_id = p.equipment_id and r.status not in ('done','cancelled')) then
    return query select false, 'По оборудованию уже есть открытая заявка сервиса', null::uuid; return;
  end if;

  select resp_min, res_min into respmin, resmin from public.app_service_sla_minutes('high');
  snum := 'SRV-' || lpad(nextval('public.app_service_seq')::text, 5, '0');
  insert into public.app_service_requests
    (tenant_id, number, equipment_id, title, kind, priority, channel, source, plan_id, reported_at, response_due, resolve_due, assigned_login, created_login)
  values (coalesce(p.tenant_id,ten), snum, p.equipment_id, 'ППР (ТОиР): ' || coalesce(p.eq_name,'оборудование') || ' — ' || coalesce(p.kind,'ТО'),
          'service', 'high', 'manual', 'ppr', p.id, now(), now() + make_interval(mins => respmin), now() + make_interval(mins => resmin), null, ulogin)
  returning id into sid;
  insert into public.app_service_history (tenant_id, request_id, kind, text, by_login)
  values (coalesce(p.tenant_id,ten), sid, 'event', 'Заявка создана из плана ТОиР (' || coalesce(p.kind,'ТО') || ')', ulogin);
  perform public.app_notif_roles_t(coalesce(p.tenant_id,ten), array['admin','owner','manager','director','chief','master'],
          'Сервис: заявка из ТОиР ' || snum, coalesce(p.eq_name,'оборудование'), 'apps/service/index.html');
  return query select true, 'Заявка сервиса создана: ' || snum, sid;
end $$;

grant execute on function public.app_mnt_plan_service_request(uuid,uuid) to anon, authenticated;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Обслуживание','Связка ТОиР и сервиса',
   'Из плана ТОиР можно создать сервисную заявку: app_mnt_plan_service_request (кнопка «→ Сервис» в плане). Заявка получает источник ppr и plan_id, приоритет high, SLA; защита от дубля — если по оборудованию уже есть открытая заявка, создание блокируется. Массово — app_service_ppr_scan (по просроченным планам).',
   'ТОиР ППР сервис заявка связка план')
) as v(category,question,answer,tags)
where not exists (
  select 1 from public.app_knowledge
   where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001' and question = 'Связка ТОиР и сервиса'
);
