-- ============================================================
-- 3DMP Service · 0070_industry.sql  (v48 — ЭПИК G: P3 отраслевая аналитика)
-- Отраслевые бенчмарки (нормочас, OEE, брак, маржа и др.) + сравнение
-- показателей организации с отраслью + платформенная сводка. База знаний.
-- Зависит от 0001..0069.
-- ============================================================

create table if not exists public.app_industry_benchmarks (
  id         uuid primary key default gen_random_uuid(),
  metric     text not null,          -- normohour_rate|oee_pct|defect_pct|margin_pct|lead_days|utilization_pct
  category   text,                    -- оснастка|штампы|ЧПУ|металлообработка|общее
  region     text default 'RU',
  value      numeric not null default 0,
  unit       text,
  period     text,
  source     text,
  note       text,
  created_at timestamptz not null default now()
);
create index if not exists app_industry_benchmarks_idx on public.app_industry_benchmarks (metric, category);
alter table public.app_industry_benchmarks enable row level security;

create or replace function public.app_industry_benchmarks_list(p_token uuid, p_metric text default null)
returns table (id uuid, metric text, category text, region text, value numeric, unit text, period text, source text, note text)
language plpgsql security definer set search_path = public
as $$
declare urole text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  return query select b.id, b.metric, b.category, b.region, b.value, b.unit, b.period, b.source, b.note
    from public.app_industry_benchmarks b
    where (coalesce(p_metric,'')='' or b.metric=p_metric)
    order by b.metric, b.category;
end $$;

create or replace function public.app_industry_benchmark_save(p_token uuid, p_id uuid, p_metric text, p_category text,
  p_region text, p_value numeric, p_unit text, p_period text, p_source text, p_note text)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
declare urole text; bid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  if urole <> 'admin' then raise exception 'Только администратор платформы'; return; end if;
  if coalesce(trim(p_metric),'')='' then raise exception 'Укажите метрику'; return; end if;
  if p_id is null then
    insert into public.app_industry_benchmarks (metric, category, region, value, unit, period, source, note)
    values (trim(p_metric), nullif(trim(p_category),''), coalesce(nullif(trim(p_region),''),'RU'), coalesce(p_value,0),
            nullif(trim(p_unit),''), nullif(trim(p_period),''), nullif(trim(p_source),''), nullif(trim(p_note),''))
    returning id into bid;
    return query select bid, 'Бенчмарк добавлен';
  else
    update public.app_industry_benchmarks set metric=trim(p_metric), category=nullif(trim(p_category),''),
      region=coalesce(nullif(trim(p_region),''),region), value=coalesce(p_value,value), unit=nullif(trim(p_unit),''),
      period=nullif(trim(p_period),''), source=nullif(trim(p_source),''), note=nullif(trim(p_note),'')
     where id=p_id returning id into bid;
    return query select bid, 'Бенчмарк обновлён';
  end if;
end $$;

-- Сравнение показателей организации с отраслевым бенчмарком
create or replace function public.app_industry_compare(p_token uuid)
returns table (metric text, own numeric, benchmark numeric, unit text, delta_pct numeric)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid; own_nh numeric; own_oee numeric; own_def numeric; b_nh numeric; b_oee numeric; b_def numeric;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);

  own_nh := (select avg(rate_hour) from public.app_cost_rates where (urole='admin' or tenant_id=ten) and rate_hour>0);
  own_oee := (select round(avg(case when planned_min>0 then (run_min/planned_min) * (case when total_qty>0 then good_qty/total_qty else 0 end) else null end)*100,1)
              from public.app_oee_log where (urole='admin' or tenant_id=ten));
  own_def := (select round(100.0*count(*) filter (where l.result='no')/greatest(count(*),1),1)
              from public.app_qc_lines l join public.app_qc_checks c on c.id=l.check_id
              where (urole='admin' or c.tenant_id=ten));

  b_nh := (select avg(value) from public.app_industry_benchmarks where metric='normohour_rate');
  b_oee := (select avg(value) from public.app_industry_benchmarks where metric='oee_pct');
  b_def := (select avg(value) from public.app_industry_benchmarks where metric='defect_pct');

  return query
  select 'normohour_rate', own_nh, b_nh, '₽/ч',
    case when coalesce(b_nh,0)>0 then round((own_nh-b_nh)/b_nh*100,1) else null end
  union all
  select 'oee_pct', own_oee, b_oee, '%',
    case when coalesce(b_oee,0)>0 then round((own_oee-b_oee)/b_oee*100,1) else null end
  union all
  select 'defect_pct', own_def, b_def, '%',
    case when coalesce(b_def,0)>0 then round((own_def-b_def)/b_def*100,1) else null end;
end $$;

-- Платформенная сводка (админ): агрегаты по всем организациям
create or replace function public.app_industry_stats(p_token uuid)
returns table (tenants bigint, active_tenants bigint, users bigint, orders bigint, naryads bigint, tenders bigint, escrow_released numeric)
language plpgsql security definer set search_path = public
as $$
declare urole text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  if urole <> 'admin' then raise exception 'Только администратор платформы'; end if;
  return query select
    (select count(*) from public.tenants),
    (select count(*) from public.tenants where coalesce(status,'active')='active'),
    (select count(*) from public.app_users),
    (select count(*) from public.app_orders),
    (select count(*) from public.app_naryads),
    (select count(*) from public.tenders),
    (select coalesce(sum(amount),0) from public.app_escrow_deals where status='released');
end $$;

grant execute on function public.app_industry_benchmarks_list(uuid,text) to anon, authenticated;
grant execute on function public.app_industry_benchmark_save(uuid,uuid,text,text,text,numeric,text,text,text,text) to anon, authenticated;
grant execute on function public.app_industry_compare(uuid) to anon, authenticated;
grant execute on function public.app_industry_stats(uuid) to anon, authenticated;

-- ---------- Отраслевые бенчмарки (демо-ориентиры) ----------
insert into public.app_industry_benchmarks (metric, category, region, value, unit, period, source, note)
select v.metric, v.cat, 'RU', v.val, v.unit, v.period, v.src, v.note
from (values
  ('normohour_rate','ЧПУ','RU'::text, 2500, '₽/ч','2026','обзор рынка','Средняя ставка нормочаса ЧПУ'),
  ('normohour_rate','Слесарные',null, 1200, '₽/ч','2026','обзор рынка','Слесарная обработка'),
  ('oee_pct','Металлообработка',null, 65, '%','2026','benchmark','Целевой OEE'),
  ('defect_pct','Металлообработка',null, 3, '%','2026','benchmark','Допустимый уровень брака'),
  ('margin_pct','Оснастка',null, 22, '%','2026','benchmark','Средняя маржа по оснастке'),
  ('lead_days','Оснастка',null, 45, 'дн','2026','benchmark','Средний срок изготовления'),
  ('utilization_pct','ЧПУ',null, 78, '%','2026','benchmark','Загрузка оборудования')
) as v(metric,cat,region,val,unit,period,src,note)
where not exists (select 1 from public.app_industry_benchmarks where metric='normohour_rate' and category='ЧПУ');

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Платформа','Отраслевая аналитика и бенчмарки (P3)',
   'Модуль «Отраслевая аналитика»: эталонные отраслевые показатели (нормочас, OEE, брак, маржа, сроки, загрузка) и сравнение показателей вашей организации с отраслью — вычисляются отклонения (delta %). Администратор платформы видит сводку по всем организациям.',
   'отраслевая аналитика бенчмарк нормочас OEE брак маржа сравнение P3')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Отраслевая аналитика и бенчмарки (P3)');
