-- ============================================================
-- 3DMP Service · 0184_prod_analytics.sql  (план v4, W42 «Аналитика производства»)
-- APS-оптимизация (очередь с приоритетами), предиктивный ТОиР (по вибрации),
-- SPC-сигналы (выход за 2σ/3σ). Идемпотентно. Зависит от 0001..0183.
-- ============================================================

-- ---------- APS: рекомендованная очередь (приоритеты + сроки) ----------
create or replace function public.app_aps_optimize(p_token uuid)
returns table (seq integer, number text, title text, priority text, due_date date, plan_hours numeric, reason text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    select x.seq, x.number, x.title, x.priority, x.due_date, x.plan_hours, x.reason from (
      select row_number() over (
               order by case n.priority when 'urgent' then 0 when 'high' then 1 when 'normal' then 2 when 'low' then 3 else 2 end,
                        n.due_date nulls last, n.created_at)::int as seq,
             n.number, n.title, n.priority, n.due_date, n.plan_hours,
             case when n.due_date is not null and n.due_date < current_date then 'просрочен'
                  when n.priority in ('urgent','high') then 'высокий приоритет'
                  else 'план' end as reason
        from public.app_naryads n
       where (urole='admin' or n.tenant_id = ten) and n.status not in ('done','closed')
    ) x order by x.seq;
end $$;
grant execute on function public.app_aps_optimize(uuid) to anon, authenticated;

-- ---------- Предиктивный ТОиР: риск по вибрации ----------
create or replace function public.app_mnt_predictive(p_token uuid)
returns table (equipment text, last_value numeric, avg_value numeric, threshold numeric, trend text, days_to integer, risk text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    with a as (
      select v.equipment_id,
             avg(v.value) as avg_v,
             coalesce(stddev(v.value),0) as sd,
             (array_agg(v.value order by v.ts desc))[1] as last_v
        from public.app_vibro_readings v
       where (urole='admin' or v.tenant_id = ten)
       group by v.equipment_id
    )
    select e.name,
           round(a.last_v,3) as last_value,
           round(a.avg_v,3) as avg_value,
           round(coalesce(nullif(e.max_x,0), a.avg_v + 2*a.sd),3) as threshold,
           case when a.last_v > coalesce(nullif(e.max_x,0), a.avg_v + 2*a.sd) then 'рост' else 'норма' end as trend,
           case when a.last_v > coalesce(nullif(e.max_x,0), a.avg_v + 2*a.sd) then 0 else 30 end as days_to,
           case when a.last_v > coalesce(nullif(e.max_x,0), a.avg_v + 2*a.sd) then 'высокий'
                when a.sd > 0 and a.last_v > a.avg_v + a.sd then 'средний' else 'низкий' end as risk
      from a join public.app_equipment e on e.id = a.equipment_id
     order by (case when a.last_v > coalesce(nullif(e.max_x,0), a.avg_v + 2*a.sd) then 0 when a.sd > 0 and a.last_v > a.avg_v + a.sd then 1 else 2 end), e.name;
end $$;
grant execute on function public.app_mnt_predictive(uuid) to anon, authenticated;

-- ---------- SPC-сигналы (2σ/3σ) по параметру измерений ----------
create or replace function public.app_spc_signals(p_token uuid, p_param text default null)
returns table (param text, value numeric, ts timestamptz, signal text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query
    with m as (
      select q.param, avg(q.value) as avg_v, coalesce(stddev(q.value),0) as sd
        from public.app_qc_measures q
       where (urole='admin' or q.tenant_id = ten) and (p_param is null or q.param = p_param)
       group by q.param
    )
    select q.param, q.value, q.ts,
           case when m.sd > 0 and abs(q.value - m.avg_v) > 3*m.sd then 'за пределами 3σ'
                when m.sd > 0 and abs(q.value - m.avg_v) > 2*m.sd then 'предупреждение 2σ'
                else null end as signal
      from public.app_qc_measures q join m on m.param = q.param
     where (urole='admin' or q.tenant_id = ten) and (p_param is null or q.param = p_param)
       and m.sd > 0 and abs(q.value - m.avg_v) > 2*m.sd
     order by q.ts desc
     limit 100;
end $$;
grant execute on function public.app_spc_signals(uuid,text) to anon, authenticated;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001','Производство','Аналитика производства: APS-очередь, предиктив ТОиР, SPC-сигналы',
 'W42: app_aps_optimize — рекомендованная очередь нарядов (приоритет + срок: просроченные и высокий приоритет вперёд). app_mnt_predictive — риск оборудования по вибрации (последнее значение vs порог max_x или среднее+2σ): trend/risk/days_to. app_spc_signals(param) — точки вне 2σ/3σ по параметру измерений ОТК (SPC). Дашборд-аналитика — в модуле «Планирование».',
 'аналитика производство aps очередь приоритет предиктив тоир вибрация spc сигналы 3σ'
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Аналитика производства: APS-очередь, предиктив ТОиР, SPC-сигналы');
