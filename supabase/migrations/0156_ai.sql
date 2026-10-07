-- ============================================================
-- 3DMP Service · 0156_ai.sql  (W11 — ИИ)
-- Авто-нормирование (эвристики+LLM-задел), CV-ОТК по фото, цифровой двойник,
-- AI-помощник по базе знаний и журнал ИИ-задач.
-- Идемпотентно. Зависит от 0001..0155.
-- ============================================================

-- ---------- Журнал ИИ-задач ----------
create table if not exists public.app_ai_jobs (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  kind          text not null default 'norming',   -- norming|cv_qc|twin|llm
  ref_type      text,
  ref_id        uuid,
  input         jsonb not null default '{}'::jsonb,
  output        jsonb not null default '{}'::jsonb,
  status        text not null default 'done',       -- pending|processing|done|error
  model         text,
  score         numeric,
  note          text,
  created_by    uuid references public.app_users (id) on delete set null,
  created_login text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists app_ai_jobs_idx on public.app_ai_jobs (tenant_id, kind, created_at desc);
alter table public.app_ai_jobs enable row level security;

-- ---------- RPC: журнал и KPI ----------
create or replace function public.app_ai_jobs_list(p_token uuid, p_kind text default null, p_limit integer default 50)
returns table (id uuid, kind text, ref_type text, ref_id uuid, status text, score numeric, note text, output jsonb, created_login text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean; k text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token);
  ten := public.app_my_tenant(p_token);
  k := nullif(trim(coalesce(p_kind,'')),'');
  return query
    select j.id, j.kind, j.ref_type, j.ref_id, j.status, j.score, j.note, j.output, j.created_login, j.created_at
      from public.app_ai_jobs j
     where (adm or j.tenant_id = ten) and (k is null or j.kind = k)
     order by j.created_at desc limit greatest(coalesce(p_limit,50),1);
end $$;

create or replace function public.app_ai_job_update(p_token uuid, p_id uuid, p_status text, p_output jsonb, p_score numeric, p_note text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; n integer;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  ten := public.app_my_tenant(p_token);
  update public.app_ai_jobs j set status = coalesce(nullif(trim(p_status),''), j.status),
         output = coalesce(p_output, j.output), score = coalesce(p_score, j.score), note = coalesce(p_note, j.note), updated_at = now()
   where j.id = p_id and (public.app_is_platform_admin(p_token) or j.tenant_id = ten);
  get diagnostics n = row_count;
  if n = 0 then return query select false,'Задача не найдена'; return; end if;
  return query select true,'Задача обновлена';
end $$;

create or replace function public.app_ai_kpi(p_token uuid)
returns table (jobs bigint, done bigint, pending bigint, avg_score numeric, last_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token);
  ten := public.app_my_tenant(p_token);
  return query select
    (select count(*) from public.app_ai_jobs j where adm or j.tenant_id = ten),
    (select count(*) from public.app_ai_jobs j where (adm or j.tenant_id = ten) and j.status='done'),
    (select count(*) from public.app_ai_jobs j where (adm or j.tenant_id = ten) and j.status in ('pending','processing')),
    (select round(avg(j.score),1) from public.app_ai_jobs j where (adm or j.tenant_id = ten) and j.score is not null),
    (select max(j.created_at) from public.app_ai_jobs j where adm or j.tenant_id = ten);
end $$;

-- ---------- Авто-нормирование (эвристики по нормам и факту) ----------
create or replace function public.app_ai_norming_suggest(p_token uuid, p_operation text default null)
returns table (operation text, machine_kind text, setup_min numeric, unit_min numeric, rate_hour numeric,
               samples bigint, source text, confidence numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean; op text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token);
  ten := public.app_my_tenant(p_token);
  op := nullif(trim(coalesce(p_operation,'')),'');
  return query
  with ops as (
    select distinct operation from public.app_norms where (adm or tenant_id = ten or tenant_id is null) and coalesce(operation,'') <> ''
    union
    select distinct name from public.app_operations where (adm or tenant_id = ten or tenant_id is null) and coalesce(name,'') <> ''
    union
    select distinct o.operation from public.app_naryad_ops o join public.app_naryads n on n.id = o.naryad_id
     where (adm or n.tenant_id = ten) and coalesce(o.operation,'') <> ''
  ), base as (
    select x.operation,
      (select nm.machine_kind from public.app_norms nm where nm.operation = x.operation and (adm or nm.tenant_id = ten or nm.tenant_id is null)
         order by nm.tenant_id nulls last limit 1) as machine_kind,
      (select nm.setup_min from public.app_norms nm where nm.operation = x.operation and (adm or nm.tenant_id = ten or nm.tenant_id is null)
         order by nm.tenant_id nulls last limit 1) as n_setup,
      (select nm.unit_min from public.app_norms nm where nm.operation = x.operation and (adm or nm.tenant_id = ten or nm.tenant_id is null)
         order by nm.tenant_id nulls last limit 1) as n_unit,
      (select nm.rate_hour from public.app_norms nm where nm.operation = x.operation and (adm or nm.tenant_id = ten or nm.tenant_id is null)
         order by nm.tenant_id nulls last limit 1) as n_rate,
      (select count(*) from public.app_naryad_ops o join public.app_naryads n on n.id = o.naryad_id
         where o.operation = x.operation and (adm or n.tenant_id = ten)) as samples,
      (select avg(coalesce(nullif(o.fact_hours,0), o.plan_hours) * 60) from public.app_naryad_ops o join public.app_naryads n on n.id = o.naryad_id
         where o.operation = x.operation and (adm or n.tenant_id = ten)) as a_unit
    from ops x
  )
  select b.operation, b.machine_kind,
    round(coalesce(b.n_setup,0),2),
    round(coalesce(b.n_unit, b.a_unit, 0),2),
    round(coalesce(b.n_rate,0),2),
    coalesce(b.samples,0),
    case when b.n_unit is not null then 'норма' when b.a_unit is not null then 'факт' else 'нет данных' end,
    (case when b.n_unit is not null then least(100, 70 + least(coalesce(b.samples,0),6)*5)
         else least(90, coalesce(b.samples,0)*15) end)::numeric
   from base b
  where op is null or b.operation = op
  order by (case when b.n_unit is not null then 'норма' else 'факт' end), b.operation;
end $$;

create or replace function public.app_ai_norming_apply(p_token uuid, p_items jsonb)
returns table (ok boolean, message text, count integer)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; uname text; it jsonb; cnt integer := 0; q text; mk text; su numeric; un numeric; rt numeric;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён',0; return; end if;
  select u.tenant_id, s.ulogin into ten, uname from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  if p_items is null or jsonb_typeof(p_items) <> 'array' then return query select false,'Ожидается массив позиций',0; return; end if;
  for it in select * from jsonb_array_elements(p_items) loop
    q := nullif(trim(it->>'operation'),'');
    if q is null then continue; end if;
    mk := nullif(trim(it->>'machine_kind'),'');
    su := nullif(it->>'setup_min','')::numeric;
    un := nullif(it->>'unit_min','')::numeric;
    rt := nullif(it->>'rate_hour','')::numeric;
    if exists (select 1 from public.app_norms where operation = q and tenant_id = ten) then
      update public.app_norms set machine_kind = coalesce(mk, machine_kind), setup_min = coalesce(su, setup_min),
             unit_min = coalesce(un, unit_min), rate_hour = coalesce(rt, rate_hour)
       where operation = q and tenant_id = ten;
    else
      insert into public.app_norms (tenant_id, operation, machine_kind, setup_min, unit_min, rate_hour, note)
      values (ten, q, mk, coalesce(su,0), coalesce(un,0), coalesce(rt,0), 'Авто-нормирование');
    end if;
    cnt := cnt + 1;
  end loop;
  insert into public.app_ai_jobs (tenant_id, kind, input, output, status, model, note, created_login)
  values (ten, 'norming', jsonb_build_object('items', cnt), jsonb_build_object('applied', cnt), 'done', 'heuristic', 'Применено норм: ' || cnt, uname);
  return query select true, 'Применено норм: ' || cnt, cnt;
end $$;

-- ---------- CV-ОТК по фото (эвристика + задел под внешнюю CV-модель) ----------
create or replace function public.app_ai_cv_qc(p_token uuid, p_check_id uuid)
returns table (score numeric, verdict text, note text, defects integer)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean; uname text; tot numeric; good numeric; dfc integer; sc numeric; vd text; photos integer; nt text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token);
  ten := public.app_my_tenant(p_token);
  select s.ulogin into uname from public.app_session_user(p_token) s;
  select coalesce(c.qty_total,0), coalesce(c.qty_good,0) into tot, good
    from public.app_qc_checks c where c.id = p_check_id and (adm or c.tenant_id = ten);
  if not found then return query select null::numeric, 'нет', 'Проверка не найдена', 0; return; end if;
  dfc := greatest(tot - good, 0);
  sc := case when tot > 0 then round(dfc / tot * 100, 2) else 0 end;
  vd := case when sc <= 2 then 'годен' when sc <= 5 then 'риск' else 'брак' end;
  select count(*) into photos from public.app_attachments a where a.entity_type = 'qc' and a.entity_id = p_check_id;
  nt := 'Фото: ' || coalesce(photos,0) || ' · дефектных: ' || dfc || ' из ' || tot::int || ' · доля брака ' || sc || '%';
  insert into public.app_ai_jobs (tenant_id, kind, ref_type, ref_id, input, output, status, model, score, note, created_login)
  values (ten, 'cv_qc', 'qc', p_check_id, jsonb_build_object('total', tot, 'good', good, 'photos', photos),
          jsonb_build_object('verdict', vd, 'defect_pct', sc), 'done', 'heuristic-cv', sc, nt, uname);
  return query select sc, vd, nt, dfc;
end $$;

-- ---------- Цифровой двойник: рекомендации ----------
create or replace function public.app_ai_twin(p_token uuid, p_limit integer default 20)
returns table (kind text, title text, detail text, impact numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token);
  ten := public.app_my_tenant(p_token);
  return query
  select kind, title, detail, impact from (
  -- 1) просроченные заказы
  select 'сроки'::text as kind, 'Просроченные заявки'::text as title,
         (o.number || ' · ' || coalesce(o.title,'') || ' · срок ' || to_char(o.due_date,'DD.MM.YY')) as detail,
         greatest((current_date - o.due_date),0)::numeric as impact
    from public.app_orders o
   where (adm or o.tenant_id = ten) and o.due_date is not null and o.due_date < current_date and o.status not in ('done','cancelled')
  union all
  -- 2) дефицит материалов
  select 'запасы', 'Дефицит материала',
         m.name || ' · остаток ' || m.qty || ' < мин ' || m.min_qty,
         greatest(coalesce(m.min_qty,0) - coalesce(m.qty,0),0)
    from public.app_materials m
   where (adm or m.tenant_id = ten) and coalesce(m.qty,0) < coalesce(m.min_qty,0)
  union all
  -- 3) износ инструмента
  select 'инструмент', 'Инструмент на пределе',
         t.name || ' · наработка ' || coalesce(t.used_min,0) || ' / ресурс ' || coalesce(t.resource_min,0),
         coalesce(t.used_min,0)
    from public.app_tool_life t
   where (adm or t.tenant_id = ten) and coalesce(t.resource_min,0) > 0 and coalesce(t.used_min,0) >= t.resource_min
  union all
  -- 4) перегрузка рабочих центров (по плановым часам открытых нарядов)
  select 'загрузка', 'Перегрузка центра',
         wc.name || ' · открытых часов ' || round(sum(greatest(coalesce(n.plan_hours,0)-coalesce(n.fact_hours,0),0)),1),
         round(sum(greatest(coalesce(n.plan_hours,0)-coalesce(n.fact_hours,0),0)),1)
    from public.app_naryads n join public.app_work_centers wc on wc.id = n.wc_id
   where (adm or n.tenant_id = ten) and n.status in ('open','in_progress','paused','queue')
   group by wc.name
  having sum(greatest(coalesce(n.plan_hours,0)-coalesce(n.fact_hours,0),0)) >= 16
  ) t
  order by impact desc
  limit greatest(coalesce(p_limit,20),1);
end $$;

-- ---------- AI-помощник по базе знаний ----------
create or replace function public.app_ai_ask(p_token uuid, p_prompt text)
returns table (job_id uuid, answer text, source text, score numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; uname text; q text; a text; cat text; jid uuid; pr text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token);
  select s.ulogin into uname from public.app_session_user(p_token) s;
  pr := nullif(trim(coalesce(p_prompt,'')),'');
  if pr is null then return query select null::uuid, 'Задайте вопрос.', 'нет', 0::numeric; return; end if;
  select k.question, k.answer, k.category into q, a, cat
    from public.app_knowledge k
   where (k.tenant_id = ten or k.tenant_id is null)
     and (k.question ilike '%' || pr || '%' or k.answer ilike '%' || pr || '%' or k.tags ilike '%' || pr || '%')
   order by (case when k.question ilike '%' || pr || '%' then 0 else 1 end), length(k.answer)
   limit 1;
  if a is null then
    a := 'По запросу «' || pr || '» в базе знаний ничего не найдено. Уточните формулировку или добавьте статью.';
    q := 'нет совпадений';
  end if;
  insert into public.app_ai_jobs (tenant_id, kind, input, output, status, model, note, created_login)
  values (ten, 'llm', jsonb_build_object('prompt', pr), jsonb_build_object('answer', a, 'source', q), 'done', 'kb-search', left(a,200), uname)
  returning app_ai_jobs.id into jid;
  return query select jid, a, coalesce(q, '—'), 0::numeric;
end $$;

-- ---------- Демо ----------
insert into public.app_ai_jobs (tenant_id, kind, input, output, status, model, score, note, created_login)
select 'aaaaaaaa-0000-0000-0000-000000000001', 'norming', '{"items":0}'::jsonb, '{"applied":0}'::jsonb, 'done', 'heuristic', null, 'Демо: пилот авто-нормирования', 'owner'
where not exists (select 1 from public.app_ai_jobs where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and kind='norming');

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Аналитика','ИИ: авто-нормирование, CV-ОТК, цифровой двойник, AI-помощник',
   'W11: журнал ИИ-задач (app_ai_jobs, app_ai_jobs_list/update/kpi); авто-нормирование (app_ai_norming_suggest — эвристики по нормам и факту, confidence; app_ai_norming_apply — запись в app_norms); CV-ОТК по фото (app_ai_cv_qc — доля брака и вердикт, задел под внешнюю CV-модель через app_integrations); цифровой двойник (app_ai_twin — рекомендации по срокам/запасам/инструменту/загрузке); AI-помощник по базе знаний (app_ai_ask). Модуль «ИИ-помощник» (apps/ai).',
   'ИИ авто-нормирование CV ОТК фото цифровой двойник рекомендации база знаний LLM')
) as v(category,question,answer,tags)
where not exists (
  select 1 from public.app_knowledge
   where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001' and question = 'ИИ: авто-нормирование, CV-ОТК, цифровой двойник, AI-помощник'
);

-- ---------- Права ----------
grant execute on function public.app_ai_jobs_list(uuid,text,integer) to anon, authenticated;
grant execute on function public.app_ai_job_update(uuid,uuid,text,jsonb,numeric,text) to anon, authenticated;
grant execute on function public.app_ai_kpi(uuid) to anon, authenticated;
grant execute on function public.app_ai_norming_suggest(uuid,text) to anon, authenticated;
grant execute on function public.app_ai_norming_apply(uuid,jsonb) to anon, authenticated;
grant execute on function public.app_ai_cv_qc(uuid,uuid) to anon, authenticated;
grant execute on function public.app_ai_twin(uuid,integer) to anon, authenticated;
grant execute on function public.app_ai_ask(uuid,text) to anon, authenticated;
