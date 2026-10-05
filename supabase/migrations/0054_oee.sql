-- ============================================================
-- 3DMP Service · 0054_oee.sql  (v34.0 — прототип B17 → «OEE-монитор»)
-- Учёт смен по оборудованию: план/работа/простои, годные/всего → OEE (упрощённо).
-- Связь: оборудование, MES, ТОиР, инструмент. База знаний. Зависит от 0001..0053.
-- ============================================================

create table if not exists public.app_oee_log (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid references public.tenants (id),
  equipment_id   uuid references public.app_equipment (id) on delete set null,
  shift_date     date not null default current_date,
  shift          text,           -- 1|2|night
  planned_min    numeric default 0,
  run_min        numeric default 0,
  downtime_min   numeric default 0,
  downtime_reason text,
  good_qty       numeric default 0,
  total_qty      numeric default 0,
  note           text,
  created_login  text,
  created_at     timestamptz not null default now()
);
create index if not exists app_oee_log_idx on public.app_oee_log (tenant_id, shift_date desc);
alter table public.app_oee_log enable row level security;

-- ---------- Список ----------
create or replace function public.app_oee_log_list(p_token uuid, p_q text default null)
returns table (id uuid, equipment_id uuid, equipment text, shift_date date, shift text,
               planned_min numeric, run_min numeric, downtime_min numeric, downtime_reason text,
               good_qty numeric, total_qty numeric, availability numeric, quality numeric, oee numeric, note text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query
    select o.id, o.equipment_id, e.name, o.shift_date, o.shift, o.planned_min, o.run_min, o.downtime_min, o.downtime_reason,
      o.good_qty, o.total_qty,
      round(case when o.planned_min>0 then least(o.run_min,o.planned_min)/o.planned_min*100 else 0 end,1),
      round(case when o.total_qty>0 then o.good_qty/o.total_qty*100 else 0 end,1),
      round((case when o.planned_min>0 then least(o.run_min,o.planned_min)/o.planned_min else 0 end)
          * (case when o.total_qty>0 then o.good_qty/o.total_qty else 0 end) * 100, 1),
      o.note
    from public.app_oee_log o left join public.app_equipment e on e.id = o.equipment_id
    where (urole='admin' or o.tenant_id = ten)
      and (qq='' or lower(coalesce(e.name,'')) like '%'||qq||'%' or lower(coalesce(o.downtime_reason,'')) like '%'||qq||'%')
    order by o.shift_date desc, e.name;
end $$;

-- ---------- KPI ----------
create or replace function public.app_oee_kpi(p_token uuid)
returns table (records bigint, avg_oee numeric, avg_availability numeric, avg_quality numeric, downtime_total numeric)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select
    count(*),
    coalesce(round(avg((case when planned_min>0 then least(run_min,planned_min)/planned_min else 0 end)
                       * (case when total_qty>0 then good_qty/total_qty else 0 end) * 100),1),0),
    coalesce(round(avg(case when planned_min>0 then least(run_min,planned_min)/planned_min*100 else 0 end),1),0),
    coalesce(round(avg(case when total_qty>0 then good_qty/total_qty*100 else 0 end),1),0),
    coalesce(sum(downtime_min),0)
    from public.app_oee_log where (urole='admin' or tenant_id = ten);
end $$;

-- ---------- OEE по оборудованию ----------
create or replace function public.app_oee_by_equipment(p_token uuid)
returns table (equipment text, records bigint, avg_oee numeric, downtime_total numeric)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select coalesce(e.name,'—'), count(*),
      coalesce(round(avg((case when o.planned_min>0 then least(o.run_min,o.planned_min)/o.planned_min else 0 end)
                         * (case when o.total_qty>0 then o.good_qty/o.total_qty else 0 end) * 100),1),0),
      coalesce(sum(o.downtime_min),0)
    from public.app_oee_log o left join public.app_equipment e on e.id = o.equipment_id
    where (urole='admin' or o.tenant_id = ten)
    group by coalesce(e.name,'—')
    order by 3 desc;
end $$;

-- ---------- Сохранить ----------
create or replace function public.app_oee_save(p_token uuid, p_id uuid, p_equipment_id uuid, p_date date, p_shift text,
  p_planned numeric, p_run numeric, p_downtime numeric, p_reason text, p_good numeric, p_total numeric, p_note text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid; urole text; ulogin text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','master','chief','operator') then return query select false,'Недостаточно прав'; return; end if;
  if p_equipment_id is null then return query select false,'Выберите оборудование'; return; end if;
  if coalesce(p_planned,0) <= 0 then return query select false,'Укажите плановое время > 0'; return; end if;
  if p_id is null then
    insert into public.app_oee_log (tenant_id, equipment_id, shift_date, shift, planned_min, run_min, downtime_min, downtime_reason, good_qty, total_qty, note, created_login)
    values (ten, p_equipment_id, coalesce(p_date,current_date), nullif(trim(p_shift),''), p_planned, coalesce(p_run,0), coalesce(p_downtime,0),
            nullif(trim(p_reason),''), coalesce(p_good,0), coalesce(p_total,0), nullif(trim(p_note),''), ulogin);
  else
    update public.app_oee_log set equipment_id=p_equipment_id, shift_date=coalesce(p_date,shift_date), shift=nullif(trim(p_shift),''),
      planned_min=p_planned, run_min=coalesce(p_run,0), downtime_min=coalesce(p_downtime,0), downtime_reason=nullif(trim(p_reason),''),
      good_qty=coalesce(p_good,0), total_qty=coalesce(p_total,0), note=nullif(trim(p_note),'')
     where id=p_id and (urole='admin' or tenant_id=ten);
  end if;
  return query select true,'Сохранено';
end $$;

grant execute on function public.app_oee_log_list(uuid,text) to anon, authenticated;
grant execute on function public.app_oee_kpi(uuid) to anon, authenticated;
grant execute on function public.app_oee_by_equipment(uuid) to anon, authenticated;
grant execute on function public.app_oee_save(uuid,uuid,uuid,date,text,numeric,numeric,numeric,text,numeric,numeric,text) to anon, authenticated;

-- ---------- Демо (тенант A) ----------
insert into public.app_oee_log (tenant_id, equipment_id, shift_date, shift, planned_min, run_min, downtime_min, downtime_reason, good_qty, total_qty, created_login)
select 'aaaaaaaa-0000-0000-0000-000000000001', e.id, current_date - v.d, v.sh, 480, v.run, v.dt, v.reason, v.good, v.total, 'master'
from public.app_equipment e
join (values
  ('frezerny',1,'1',420,60,'переналадка',95,100),
  ('frezerny',2,'1',400,80,'ожидание материала',90,98),
  ('tokarny',1,'1',440,40,'инструмент',98,100),
  ('edm',1,'1',300,180,'поломка/ремонт',40,50)
) as v(eqkind, d, sh, run, dt, reason, good, total) on e.kind = v.eqkind
where not exists (select 1 from public.app_oee_log where tenant_id='aaaaaaaa-0000-0000-0000-000000000001');

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('OEE','Что такое OEE и как его вести?',
   'OEE — общая эффективность оборудования. Упрощённо: OEE = Доступность × Качество, где Доступность = работа/план, Качество = годные/всего. Ведите по сменам: плановое время, фактическая работа, простои с причиной, годные/всего. В модуле видно средний OEE, доступность, качество, суммарные простои и рейтинг оборудования.',
   'OEE эффективность доступность качество простои смена оборудование'),
  ('OEE','Как снижать простои?',
   'Анализируйте причины простоев (переналадка, ожидание материала, поломка/ремонт, инструмент). Поломки ведут в ТОиР, износ инструмента — в «Инструмент и стойкость», ожидание материала — в склад/закупки. Рейтинг оборудования показывает, где теряется эффективность.',
   'OEE простои причины ТОиР инструмент склад переналадка')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Что такое OEE и как его вести?');
