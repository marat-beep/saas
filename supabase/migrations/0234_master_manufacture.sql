-- ============================================================
-- 3DMP Service · 0234_master_manufacture.sql
-- «Мастер производства»: по детали за один проход создаёт маршрут
-- (из типового, с уточняющей операцией), наряд, сменно-суточное задание
-- (app_daily_jobs) и документ-техкарту. Расширяет app_tech_wizard_run (0233).
-- Идемпотентно. Зависит от 0001..0233.
-- ============================================================

create or replace function public.app_master_manufacture(
  p_token uuid, p_code text, p_title text,
  p_material text default null, p_qty numeric default 1, p_due date default null, p_operation text default null,
  p_make_naryad boolean default true, p_make_tasks boolean default true, p_make_doc boolean default true)
returns table (ok boolean, message text, route_id uuid, route_number text, steps integer, naryad_number text, doc_number text, jobs integer)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare r record; jc integer := 0; msg text;
begin
  if not public.app_production_allowed(p_token) then
    return query select false,'Доступ запрещён',null::uuid,null::text,0,null::text,null::text,0; return;
  end if;
  select * into r from public.app_tech_wizard_run(p_token, p_code, p_title, p_material, p_qty, p_due, p_make_naryad, p_make_doc, p_operation);
  if not coalesce(r.ok, false) then
    return query select false, coalesce(r.message,'Не удалось создать техпроцесс'), null::uuid, null::text, 0, null::text, null::text, 0; return;
  end if;
  msg := coalesce(r.message, 'Готово');
  if coalesce(p_make_tasks, true) then
    perform public.app_daily_job_build(p_token, current_date);
    select count(*) into jc from public.app_daily_job_list(p_token, current_date);
    msg := msg || ' · ССЗ: ' || jc;
  end if;
  return query select true, msg, r.route_id, r.route_number, r.steps, r.naryad_number, r.doc_number, jc;
end $$;

grant execute on function public.app_master_manufacture(uuid,text,text,text,numeric,date,text,boolean,boolean,boolean) to anon, authenticated;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select null, v.category, v.question, v.answer, v.tags
from (values
  ('Технология','Мастера-плитки: быстрый ввод детали, техпроцесса, наряда и документации',
   'Мастера — отдельные элементы (плитки), которые можно размещать в любом модуле (по подгруппе/контуру) и число которых не ограничено. Плитка «Деталь → техпроцесс → задание, наряд и документ» (RPC app_master_manufacture) за один проход: строит маршрут из типового, добавляет уточняющую операцию, создаёт наряд, формирует сменно-суточное задание (app_daily_job_build) и документ-техкарту. Каркас мастеров: assets/js/masters.js (плитки + AppWizard), точки монтирования — контейнер #masters в модулях.',
   'мастера плитки быстрый ввод мастер производства деталь техпроцесс наряд задание документ app_master_manufacture masters')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge k where k.question=v.question);
