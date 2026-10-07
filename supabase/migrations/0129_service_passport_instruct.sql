-- ============================================================
-- 3DMP Service · 0129_service_passport_instruct.sql  (S7 — история ремонта в паспорте, инструкции оператору)
-- Паспорт станка с историей ремонта (список заявок) и передача инструкций
-- оператору с выезда. Идемпотентно. Зависит от 0001..0128.
-- ============================================================

-- ---------- История ремонта по станку (для паспорта) ----------
drop function if exists public.app_service_equipment_history(uuid,uuid);
create or replace function public.app_service_equipment_history(p_token uuid, p_equipment_id uuid)
returns table (id uuid, number text, title text, kind text, status text, reported_at timestamptz, resolved_at timestamptz,
               cost numeric, parts_cost numeric, engineer text, source text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  select s.urole into urole from public.app_session_user(p_token) s;
  if urole is null then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token);
  return query
    select r.id, r.number, r.title, r.kind, r.status, r.reported_at, r.resolved_at,
           r.cost, r.parts_cost, coalesce(r.assigned_login, r.engineer), r.source
      from public.app_service_requests r
     where r.equipment_id = p_equipment_id and (urole='admin' or r.tenant_id = ten)
     order by coalesce(r.reported_at, r.created_at) desc;
end $$;

-- ---------- Инструкция оператору (с выезда) ----------
drop function if exists public.app_service_instruct(uuid,uuid,text,text);
create or replace function public.app_service_instruct(p_token uuid, p_id uuid, p_text text, p_kind text default 'instruction')
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ulogin text; ten uuid; r record;
begin
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  if uid is null then return query select false, 'Сессия недействительна'; return; end if;
  if not public.app_can(p_token,'service','edit') then return query select false, 'Нет прав'; return; end if;
  if coalesce(trim(p_text),'')='' then return query select false, 'Введите текст инструкции'; return; end if;
  ten := public.app_my_tenant(p_token);
  select r.number, r.tenant_id, r.equipment_id into r from public.app_service_requests r
   where r.id=p_id and (public.app_is_platform_admin(p_token) or r.tenant_id=ten);
  if r.number is null then return query select false, 'Заявка не найдена'; return; end if;
  insert into public.app_service_history (tenant_id, request_id, kind, text, by_login)
  values (coalesce(r.tenant_id,ten), p_id, coalesce(nullif(trim(p_kind),''),'instruction'), 'Инструкция: ' || trim(p_text), ulogin);
  perform public.app_notif_roles_t(coalesce(r.tenant_id,ten), array['operator','master','technologist','support','manager'],
          'Инструкция по ' || r.number, trim(p_text), 'apps/service/index.html');
  return query select true, 'Инструкция отправлена в заявку и оператору';
end $$;

grant execute on function public.app_service_equipment_history(uuid,uuid)      to anon, authenticated;
grant execute on function public.app_service_instruct(uuid,uuid,text,text)     to anon, authenticated;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Сервис','Паспорт станка и инструкции на выезде',
   'Паспорт станка хранится в оборудовании (app_equipment) и собирается на лету: app_equipment_passport (гарантия, сводные KPI, ТОиР, телеметрия) + app_service_equipment_history (история ремонта — список сервисных заявок). Изменять: оборудование — в apps/equipment; гарантии/контракты — в apps/service (раздел «Гарантии/контракты»); записи истории — автоматически из заявок. Печать — «📄 Паспорт в PDF» (со историей ремонта). Инструкции оператору: типовая — шаблоны (app_service_templates, вид «Заметка»); с выезда инженер отправляет инструкцию в заявку (app_service_instruct) — попадает в историю и уведомление оператору/мастеру; база знаний — app_knowledge (apps/guide). Делиться: применить шаблон/отправить инструкцию (видно всем по заявке) или дать ссылку на статью БЗ.',
   'паспорт станка история ремонта печать инструкция оператору шаблоны база знаний поделиться')
) as v(category,question,answer,tags)
where not exists (
  select 1 from public.app_knowledge
   where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001' and question = 'Паспорт станка и инструкции на выезде'
);
