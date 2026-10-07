-- ============================================================
-- 3DMP Service · 0115_mnt_runtime.sql  (v137 — ТОиР по наработке)
-- Статус обслуживания по наработке: суммируем часы работы (OEE run_min)
-- с последнего ТО и сравниваем с периодичностью (period_days × 8 ч).
-- Идемпотентно. Зависит от 0001..0114.
-- ============================================================

create or replace function public.app_mnt_runtime_status(p_token uuid)
returns table (plan_id uuid, equipment text, kind text, period_days int, last_done date, next_due date,
               run_hours numeric, due_hours numeric, pct numeric, status text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select p.id, coalesce(e.name, '—'), p.kind, p.period_days, p.last_done, p.next_due,
           round(coalesce(run.h, 0), 1),
           (coalesce(p.period_days, 30) * 8)::numeric,
           case when coalesce(p.period_days, 30) * 8 > 0 then round(coalesce(run.h, 0) / (coalesce(p.period_days, 30) * 8) * 100, 1) else null end,
           case
             when (p.next_due is not null and p.next_due < current_date) or coalesce(run.h, 0) >= coalesce(p.period_days, 30) * 8 then 'overdue'
             when coalesce(run.h, 0) >= 0.8 * coalesce(p.period_days, 30) * 8 then 'soon'
             else 'ok'
           end
      from public.app_mnt_plans p
      left join public.app_equipment e on e.id = p.equipment_id
      left join lateral (
        select sum(o.run_min) / 60.0 as h from public.app_oee_log o
         where o.equipment_id = p.equipment_id and (p.last_done is null or o.shift_date >= p.last_done)
      ) run on true
     where coalesce(p.active, true) and (urole = 'admin' or p.tenant_id = ten)
     order by p.next_due nulls last;
end $$;

grant execute on function public.app_mnt_runtime_status(uuid) to anon, authenticated;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Обслуживание','ТОиР по наработке',
   'app_mnt_runtime_status считает наработку оборудования с последнего ТО (сумма run_min из журнала OEE) и сравнивает с периодичностью (period_days × 8 ч): статус «ок», «скоро» (≥80%) или «просрочено» (по дате или по наработке). Для оборудования без данных OEE используется только дата следующего ТО.',
   'ТОиР обслуживание наработка часы OEE периодичность статус maintenance')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='ТОиР по наработке');
