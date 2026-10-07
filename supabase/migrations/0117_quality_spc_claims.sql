-- ============================================================
-- 3DMP Service · 0117_quality_spc_claims.sql  (W2 — SPC и претензии/CAPA)
-- SPC: измерения app_qc_measures, контрольная карта x̄/Rs (I-MR), Cp/Cpk.
-- Претензии: app_claims + CAPA app_capa_actions, связь с app_issues.
-- Идемпотентно. Зависит от 0001..0116.
-- ============================================================

create sequence if not exists public.app_claim_seq;

-- ---------- Измерения (SPC) ----------
create table if not exists public.app_qc_measures (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  check_id      uuid references public.app_qc_checks (id) on delete set null,
  position_id   uuid references public.app_qc_lines (id) on delete set null,
  param         text not null,
  value         numeric not null,
  ts            timestamptz not null default now(),
  created_by    uuid references public.app_users (id) on delete set null,
  created_login text,
  created_at    timestamptz not null default now()
);
create index if not exists app_qc_measures_idx on public.app_qc_measures (tenant_id, param, ts desc);

-- ---------- Претензии ----------
create table if not exists public.app_claims (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  number        text unique not null,
  customer      text,
  product       text,
  reason        text,
  qty           numeric default 1,
  severity      text not null default 'minor',   -- minor | major | critical
  status        text not null default 'new',      -- new | accepted | in_work | capa | closed | rejected
  description   text,
  resolution    text,
  assigned_login text,
  issue_id      uuid references public.app_issues (id) on delete set null,
  order_id      uuid references public.app_orders (id) on delete set null,
  created_by    uuid references public.app_users (id) on delete set null,
  created_login text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  closed_at     timestamptz
);
create index if not exists app_claims_idx on public.app_claims (tenant_id, status, created_at desc);

-- ---------- CAPA-мероприятия ----------
create table if not exists public.app_capa_actions (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid references public.tenants (id),
  claim_id    uuid references public.app_claims (id) on delete cascade,
  kind        text not null default 'corrective',  -- corrective | preventive
  title       text not null,
  responsible text,
  due_date    date,
  status      text not null default 'planned',      -- planned | in_work | done | verified
  note        text,
  created_login text,
  created_at  timestamptz not null default now(),
  done_at     timestamptz
);
create index if not exists app_capa_actions_idx on public.app_capa_actions (tenant_id, claim_id);

alter table public.app_qc_measures   enable row level security;
alter table public.app_claims        enable row level security;
alter table public.app_capa_actions  enable row level security;

-- ============================================================
--  SPC (контрольная карта x̄/Rs, Cp/Cpk)
-- ============================================================

-- Сводка по параметру: I-MR карта и индексы воспроизводимости.
drop function if exists public.app_qc_spc_stats(uuid,text,numeric,numeric,integer);
create or replace function public.app_qc_spc_stats(
  p_token uuid, p_param text, p_lsl numeric default null, p_usl numeric default null, p_limit integer default 50
) returns table (param text, n integer, cl numeric, ucl numeric, lcl numeric,
                 mrbar numeric, sigma numeric, sd numeric, cp numeric, cpk numeric, pp numeric, ppk numeric,
                 out_count integer, in_control boolean)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; urole text; ten uuid; vals numeric[]; nn int; i int;
        v_m numeric; v_mrbar numeric; v_sigma numeric; v_sd numeric; v_ucl numeric; v_lcl numeric;
        v_cp numeric; v_cpk numeric; v_pp numeric; v_ppk numeric; v_occ int;
begin
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token);

  select array_agg(m.value order by m.ts, m.created_at) into vals from (
    select x.value, x.ts, x.created_at from public.app_qc_measures x
     where x.param = p_param and (urole = 'admin' or x.tenant_id = ten)
     order by x.ts, x.created_at
     limit greatest(2, least(coalesce(p_limit, 50), 500))
  ) m;
  nn := coalesce(array_length(vals, 1), 0);
  if nn < 2 then
    return query select p_param, nn, null::numeric, null::numeric, null::numeric,
                        null::numeric, null::numeric, null::numeric, null::numeric, null::numeric, null::numeric, null::numeric,
                        0, true;
    return;
  end if;

  select avg(v) into v_m from unnest(vals) v;
  v_mrbar := 0;
  for i in 2..nn loop v_mrbar := v_mrbar + abs(vals[i] - vals[i-1]); end loop;
  v_mrbar := v_mrbar / (nn - 1);
  v_sigma := v_mrbar / 1.128;                       -- d2 для n=2 (moving range)
  select stddev_samp(v) into v_sd from unnest(vals) v;
  v_ucl := v_m + 3 * v_sigma;
  v_lcl := v_m - 3 * v_sigma;
  v_occ := 0;
  for i in 1..nn loop if vals[i] > v_ucl or vals[i] < v_lcl then v_occ := v_occ + 1; end if; end loop;
  if p_lsl is not null and p_usl is not null and v_sigma > 0 then
    v_cp := (p_usl - p_lsl) / (6 * v_sigma);
    v_cpk := least(p_usl - v_m, v_m - p_lsl) / (3 * v_sigma);
  end if;
  if p_lsl is not null and p_usl is not null and v_sd > 0 then
    v_pp := (p_usl - p_lsl) / (6 * v_sd);
    v_ppk := least(p_usl - v_m, v_m - p_lsl) / (3 * v_sd);
  end if;

  return query select p_param, nn, round(v_m, 4), round(v_ucl, 4), round(v_lcl, 4),
                      round(v_mrbar, 4), round(v_sigma, 4), round(v_sd, 4),
                      round(v_cp, 3), round(v_cpk, 3), round(v_pp, 3), round(v_ppk, 3),
                      v_occ, (v_occ = 0);
end $$;

-- Точки контрольной карты (для графика): значение + границы + выход за контроль.
drop function if exists public.app_qc_spc_points(uuid,text,integer);
create or replace function public.app_qc_spc_points(p_token uuid, p_param text, p_limit integer default 50)
returns table (seq integer, ts timestamptz, value numeric, cl numeric, ucl numeric, lcl numeric, out_ctl boolean)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; urole text; ten uuid; st record; r record; i int := 0;
begin
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token);
  select * into st from public.app_qc_spc_stats(p_token, p_param, null, null, p_limit);
  for r in
    select x.value, x.ts from public.app_qc_measures x
     where x.param = p_param and (urole = 'admin' or x.tenant_id = ten)
     order by x.ts, x.created_at
     limit greatest(2, least(coalesce(p_limit, 50), 500))
  loop
    i := i + 1;
    return query select i, r.ts, r.value, st.cl, st.ucl, st.lcl, (r.value > st.ucl or r.value < st.lcl);
  end loop;
end $$;

-- Список параметров (для выбора) с числом измерений.
drop function if exists public.app_qc_params(uuid);
create or replace function public.app_qc_params(p_token uuid)
returns table (param text, n bigint, last_ts timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; urole text; ten uuid;
begin
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token);
  return query
    select x.param, count(*), max(x.ts)
      from public.app_qc_measures x
     where (urole = 'admin' or x.tenant_id = ten)
     group by x.param order by max(x.ts) desc;
end $$;

-- Список измерений по параметру.
drop function if exists public.app_qc_measures_list(uuid,text,integer);
create or replace function public.app_qc_measures_list(p_token uuid, p_param text default null, p_limit integer default 100)
returns table (id uuid, param text, value numeric, ts timestamptz, check_id uuid, check_number text, position_id uuid, created_login text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; urole text; ten uuid;
begin
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token);
  return query
    select x.id, x.param, x.value, x.ts, x.check_id, c.number, x.position_id, x.created_login
      from public.app_qc_measures x
      left join public.app_qc_checks c on c.id = x.check_id
     where (urole = 'admin' or x.tenant_id = ten)
       and (p_param is null or x.param = p_param)
     order by x.ts desc
     limit greatest(1, least(coalesce(p_limit, 100), 500));
end $$;

-- Добавить измерение.
drop function if exists public.app_qc_measure_add(uuid,uuid,uuid,text,numeric);
create or replace function public.app_qc_measure_add(
  p_token uuid, p_check_id uuid, p_position_id uuid, p_param text, p_value numeric
) returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ulogin text; ten uuid; mid uuid;
begin
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  if uid is null then return query select false, 'Сессия недействительна', null::uuid; return; end if;
  if not public.app_can(p_token, 'qc', 'edit') then return query select false, 'Нет прав на ввод измерений', null::uuid; return; end if;
  if coalesce(trim(p_param), '') = '' then return query select false, 'Укажите параметр', null::uuid; return; end if;
  if p_value is null then return query select false, 'Укажите значение', null::uuid; return; end if;
  ten := public.app_my_tenant(p_token);
  insert into public.app_qc_measures (tenant_id, check_id, position_id, param, value, created_by, created_login)
  values (ten, p_check_id, p_position_id, trim(p_param), p_value, uid, ulogin)
  returning app_qc_measures.id into mid;
  return query select true, 'Измерение добавлено', mid;
end $$;

-- ============================================================
--  Претензии и CAPA
-- ============================================================

-- Список претензий (KPI/связи).
drop function if exists public.app_claim_list(uuid);
create or replace function public.app_claim_list(p_token uuid)
returns table (id uuid, number text, customer text, product text, reason text, qty numeric, severity text,
               status text, assigned_login text, issue_id uuid, issue_title text, order_number text,
               capa_total bigint, capa_done bigint, created_at timestamptz, updated_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; urole text; ten uuid;
begin
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Доступ запрещён'; end if;
  if not public.app_can(p_token, 'claims', 'view') then raise exception 'Нет прав'; end if;
  ten := public.app_my_tenant(p_token);
  return query
    select cl.id, cl.number, cl.customer, cl.product, cl.reason, cl.qty, cl.severity, cl.status,
           cl.assigned_login, cl.issue_id, i.title, o.number,
           (select count(*) from public.app_capa_actions a where a.claim_id = cl.id),
           (select count(*) from public.app_capa_actions a where a.claim_id = cl.id and a.status in ('done','verified')),
           cl.created_at, cl.updated_at
      from public.app_claims cl
      left join public.app_issues i on i.id = cl.issue_id
      left join public.app_orders o on o.id = cl.order_id
     where (urole = 'admin' or cl.tenant_id = ten)
     order by cl.created_at desc;
end $$;

-- Создать/изменить претензию.
drop function if exists public.app_claim_save(uuid,uuid,text,text,text,numeric,text,text,text);
create or replace function public.app_claim_save(
  p_token uuid, p_id uuid, p_customer text, p_product text, p_reason text, p_qty numeric,
  p_severity text, p_description text, p_assigned_login text
) returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ulogin text; ten uuid; cid uuid; cnum text;
begin
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  if uid is null then return query select false, 'Сессия недействительна', null::uuid; return; end if;
  if not public.app_can(p_token, 'claims', 'edit') then return query select false, 'Нет прав на претензии', null::uuid; return; end if;
  if coalesce(trim(p_reason), '') = '' then return query select false, 'Укажите причину претензии', null::uuid; return; end if;
  if p_severity is not null and p_severity not in ('minor','major','critical') then
    return query select false, 'Неизвестная критичность', null::uuid; return;
  end if;
  ten := public.app_my_tenant(p_token);

  if p_id is null then
    cnum := 'CLM-' || lpad(nextval('public.app_claim_seq')::text, 5, '0');
    insert into public.app_claims (tenant_id, number, customer, product, reason, qty, severity, description,
                                   assigned_login, created_by, created_login)
    values (ten, cnum, nullif(trim(p_customer),''), nullif(trim(p_product),''), trim(p_reason),
            coalesce(p_qty, 1), coalesce(nullif(trim(p_severity),''), 'minor'), nullif(trim(p_description),''),
            nullif(trim(p_assigned_login),''), uid, ulogin)
    returning app_claims.id into cid;
    perform public.app_notif_roles_t(ten, array['admin','owner','manager','qc','director'],
            'Новая претензия ' || cnum, trim(p_reason), 'apps/claims/index.html');
    return query select true, 'Претензия зарегистрирована', cid;
  else
    update public.app_claims cl
       set customer = nullif(trim(p_customer),''),
           product = nullif(trim(p_product),''),
           reason = trim(p_reason),
           qty = coalesce(p_qty, cl.qty),
           severity = coalesce(nullif(trim(p_severity),''), cl.severity),
           description = nullif(trim(p_description),''),
           assigned_login = nullif(trim(p_assigned_login),''),
           updated_at = now()
     where cl.id = p_id and (public.app_can(p_token,'claims','edit'))
       and (public.app_is_platform_admin(p_token) or cl.tenant_id = ten);
    if not found then return query select false, 'Претензия не найдена', null::uuid; return; end if;
    return query select true, 'Претензия сохранена', p_id;
  end if;
end $$;

-- Смена статуса претензии.
drop function if exists public.app_claim_set_status(uuid,uuid,text,text);
create or replace function public.app_claim_set_status(p_token uuid, p_id uuid, p_status text, p_resolution text default null)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ulogin text; ten uuid; cnum text; ciss uuid;
begin
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  if uid is null then return query select false, 'Сессия недействительна'; return; end if;
  if not public.app_can(p_token, 'claims', 'edit') then return query select false, 'Нет прав'; return; end if;
  if p_status not in ('new','accepted','in_work','capa','closed','rejected') then
    return query select false, 'Неизвестный статус'; return; end if;
  ten := public.app_my_tenant(p_token);
  select cl.number, cl.issue_id into cnum, ciss from public.app_claims cl
   where cl.id = p_id and (public.app_is_platform_admin(p_token) or cl.tenant_id = ten);
  if cnum is null then return query select false, 'Претензия не найдена'; return; end if;
  update public.app_claims cl
     set status = p_status,
         resolution = coalesce(nullif(trim(p_resolution),''), cl.resolution),
         updated_at = now(),
         closed_at = case when p_status in ('closed','rejected') then now() else null end
   where cl.id = p_id;
  -- синхронизация связанной проблемы
  if ciss is not null then
    update public.app_issues set status = case when p_status in ('closed') then 'closed'
                                                when p_status in ('rejected') then 'closed'
                                                when p_status in ('in_work','capa') then 'in_progress'
                                                else 'open' end,
           updated_at = now()
     where id = ciss;
  end if;
  perform public.app_notif_roles_t(ten, array['admin','owner','manager','qc'],
          'Претензия ' || cnum || ': ' || p_status, coalesce(nullif(trim(p_resolution),''), ''), 'apps/claims/index.html');
  return query select true, 'Статус обновлён';
end $$;

-- Эскалация претензии в проблему (app_issues).
drop function if exists public.app_claim_escalate(uuid,uuid);
create or replace function public.app_claim_escalate(p_token uuid, p_id uuid)
returns table (ok boolean, message text, issue_id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ulogin text; ten uuid; cl record; iid uuid; prio text;
begin
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  if uid is null then return query select false, 'Сессия недействительна', null::uuid; return; end if;
  if not public.app_can(p_token, 'claims', 'edit') then return query select false, 'Нет прав', null::uuid; return; end if;
  ten := public.app_my_tenant(p_token);
  select * into cl from public.app_claims c
   where c.id = p_id and (public.app_is_platform_admin(p_token) or c.tenant_id = ten);
  if cl.id is null then return query select false, 'Претензия не найдена', null::uuid; return; end if;
  prio := case when cl.severity = 'critical' then 'critical' when cl.severity = 'major' then 'high' else 'normal' end;

  if cl.issue_id is not null then
    return query select true, 'Претензия уже связана с проблемой', cl.issue_id; return;
  end if;

  insert into public.app_issues (tenant_id, title, description, priority, source, status, assignee, escalated, escalated_at, created_login)
  values (cl.tenant_id, 'Претензия ' || cl.number || ': ' || coalesce(cl.reason, ''),
          coalesce(cl.description, '') || E'\nЗаказчик: ' || coalesce(cl.customer, '—'),
          prio, 'claims', 'open', cl.assigned_login, true, now(), ulogin)
  returning app_issues.id into iid;

  update public.app_claims set issue_id = iid, status = case when status = 'new' then 'in_work' else status end, updated_at = now()
   where id = p_id;

  perform public.app_notif_roles_t(cl.tenant_id, array['admin','owner','manager','qc','director','chief'],
          'ЭСКАЛАЦИЯ претензии ' || cl.number, coalesce(cl.reason, ''), 'apps/issues/index.html');
  return query select true, 'Претензия связана с проблемой', iid;
end $$;

-- Удалить претензию.
drop function if exists public.app_claim_delete(uuid,uuid);
create or replace function public.app_claim_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ten uuid;
begin
  select s.uid into uid from public.app_session_user(p_token) s;
  if uid is null then return query select false, 'Сессия недействительна'; return; end if;
  if not public.app_can(p_token, 'claims', 'edit') then return query select false, 'Нет прав'; return; end if;
  ten := public.app_my_tenant(p_token);
  delete from public.app_claims c
   where c.id = p_id and (public.app_is_platform_admin(p_token) or c.tenant_id = ten);
  if not found then return query select false, 'Претензия не найдена'; return; end if;
  return query select true, 'Претензия удалена';
end $$;

-- CAPA: список по претензии.
drop function if exists public.app_capa_list(uuid,uuid);
create or replace function public.app_capa_list(p_token uuid, p_claim_id uuid)
returns table (id uuid, claim_id uuid, kind text, title text, responsible text, due_date date, status text, note text, created_at timestamptz, done_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; urole text; ten uuid;
begin
  select s.uid, s.urole into uid, urole from public.app_session_user(p_token) s;
  if uid is null then raise exception 'Доступ запрещён'; end if;
  ten := public.app_my_tenant(p_token);
  return query
    select a.id, a.claim_id, a.kind, a.title, a.responsible, a.due_date, a.status, a.note, a.created_at, a.done_at
      from public.app_capa_actions a
     where a.claim_id = p_claim_id and (urole = 'admin' or a.tenant_id = ten)
     order by a.created_at;
end $$;

-- CAPA: создать/изменить.
drop function if exists public.app_capa_save(uuid,uuid,uuid,text,text,text,date,text,text);
create or replace function public.app_capa_save(
  p_token uuid, p_id uuid, p_claim_id uuid, p_kind text, p_title text, p_responsible text,
  p_due_date date, p_status text, p_note text
) returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ulogin text; ten uuid; aid uuid; cl_tenant uuid;
begin
  select s.uid, s.ulogin into uid, ulogin from public.app_session_user(p_token) s;
  if uid is null then return query select false, 'Сессия недействительна', null::uuid; return; end if;
  if not public.app_can(p_token, 'claims', 'edit') then return query select false, 'Нет прав', null::uuid; return; end if;
  if coalesce(trim(p_title), '') = '' then return query select false, 'Укажите мероприятие', null::uuid; return; end if;
  if p_status is not null and p_status not in ('planned','in_work','done','verified') then
    return query select false, 'Неизвестный статус', null::uuid; return;
  end if;
  ten := public.app_my_tenant(p_token);
  select c.tenant_id into cl_tenant from public.app_claims c
   where c.id = p_claim_id and (public.app_is_platform_admin(p_token) or c.tenant_id = ten);
  if cl_tenant is null then return query select false, 'Претензия не найдена', null::uuid; return; end if;

  if p_id is null then
    insert into public.app_capa_actions (tenant_id, claim_id, kind, title, responsible, due_date, status, note, created_login)
    values (cl_tenant, p_claim_id, coalesce(nullif(trim(p_kind),''),'corrective'), trim(p_title),
            nullif(trim(p_responsible),''), p_due_date, coalesce(nullif(trim(p_status),''),'planned'), nullif(trim(p_note),''), ulogin)
    returning app_capa_actions.id into aid;
    return query select true, 'Мероприятие добавлено', aid;
  else
    update public.app_capa_actions a
       set kind = coalesce(nullif(trim(p_kind),''), a.kind),
           title = trim(p_title),
           responsible = nullif(trim(p_responsible),''),
           due_date = p_due_date,
           status = coalesce(nullif(trim(p_status),''), a.status),
           note = nullif(trim(p_note),''),
           done_at = case when coalesce(p_status,'') in ('done','verified') then coalesce(a.done_at, now()) else null end
     where a.id = p_id and a.claim_id = p_claim_id
       and (public.app_is_platform_admin(p_token) or a.tenant_id = ten);
    if not found then return query select false, 'Мероприятие не найдено', null::uuid; return; end if;
    return query select true, 'Мероприятие сохранено', p_id;
  end if;
end $$;

-- CAPA: удалить.
drop function if exists public.app_capa_delete(uuid,uuid);
create or replace function public.app_capa_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare uid uuid; ten uuid;
begin
  select s.uid into uid from public.app_session_user(p_token) s;
  if uid is null then return query select false, 'Сессия недействительна'; return; end if;
  if not public.app_can(p_token, 'claims', 'edit') then return query select false, 'Нет прав'; return; end if;
  ten := public.app_my_tenant(p_token);
  delete from public.app_capa_actions a
   where a.id = p_id and (public.app_is_platform_admin(p_token) or a.tenant_id = ten);
  if not found then return query select false, 'Мероприятие не найдено'; return; end if;
  return query select true, 'Мероприятие удалено';
end $$;

-- ---------- Права (матрица) ----------
insert into public.app_role_permissions (id, tenant_id, role, module_id, can_view, can_edit)
select gen_random_uuid(), null, v.role, 'claims', true, v.edit
from (values ('admin', true), ('owner', true), ('manager', true), ('qc', true),
             ('director', true), ('chief', false), ('technologist', false)) as v(role, edit)
where not exists (
  select 1 from public.app_role_permissions p where p.module_id = 'claims' and p.role = v.role and p.tenant_id is null
);

grant execute on function public.app_qc_spc_stats(uuid,text,numeric,numeric,integer) to anon, authenticated;
grant execute on function public.app_qc_spc_points(uuid,text,integer)                  to anon, authenticated;
grant execute on function public.app_qc_params(uuid)                                   to anon, authenticated;
grant execute on function public.app_qc_measures_list(uuid,text,integer)              to anon, authenticated;
grant execute on function public.app_qc_measure_add(uuid,uuid,uuid,text,numeric)      to anon, authenticated;
grant execute on function public.app_claim_list(uuid)                                  to anon, authenticated;
grant execute on function public.app_claim_save(uuid,uuid,text,text,text,numeric,text,text,text) to anon, authenticated;
grant execute on function public.app_claim_set_status(uuid,uuid,text,text)            to anon, authenticated;
grant execute on function public.app_claim_escalate(uuid,uuid)                         to anon, authenticated;
grant execute on function public.app_claim_delete(uuid,uuid)                           to anon, authenticated;
grant execute on function public.app_capa_list(uuid,uuid)                              to anon, authenticated;
grant execute on function public.app_capa_save(uuid,uuid,uuid,text,text,text,date,text,text) to anon, authenticated;
grant execute on function public.app_capa_delete(uuid,uuid)                            to anon, authenticated;

-- ---------- Демо-данные (тенант A) ----------
insert into public.app_qc_measures (tenant_id, param, value, ts, created_login)
select 'aaaaaaaa-0000-0000-0000-000000000001', 'Диаметр Ø12H7',
       12.008 + 0.004 * sin(g * 1.3) + 0.002 * ((g % 3) - 1),
       now() - (20 - g) * interval '1 hour', 'otk'
from generate_series(1, 20) g
where not exists (
  select 1 from public.app_qc_measures
   where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001' and param = 'Диаметр Ø12H7'
);

insert into public.app_claims (tenant_id, number, customer, product, reason, qty, severity, status, description, assigned_login, created_login)
select 'aaaaaaaa-0000-0000-0000-000000000001', 'CLM-00001', 'ООО «Клиент-2»', 'Кронштейн КР-01',
       'Несоответствие размера отверстия', 3, 'major', 'new',
       'При приёмке выявлено несоответствие Ø12H7 (завышен размер).', 'otk', 'otk'
where not exists (
  select 1 from public.app_claims where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001' and number = 'CLM-00001'
);

-- выровнять последовательность нумерации претензий с существующими номерами
select setval('public.app_claim_seq',
  greatest(coalesce((select max(nullif(regexp_replace(number, '\D', '', 'g'), '')::bigint) from public.app_claims), 0), 1));

insert into public.app_capa_actions (tenant_id, claim_id, kind, title, responsible, due_date, status, note, created_login)
select 'aaaaaaaa-0000-0000-0000-000000000001', c.id, 'corrective', 'Переналадка и контроль Ø12H7', 'master',
       current_date + 5, 'planned', 'Проверить износ развёртки, настроить режим.', 'otk'
from public.app_claims c
where c.tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001' and c.number = 'CLM-00001'
  and not exists (select 1 from public.app_capa_actions a where a.claim_id = c.id and a.title = 'Переналадка и контроль Ø12H7');

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Качество','SPC — контрольные карты и Cp/Cpk',
   'Статистическое управление процессом (SPC): измерения (app_qc_measures) по параметру образуют контрольную карту индивидуальных значений x̄ и скользящих размахов Rs (I-MR). Границы: центральная линия = среднее, UCL/LCL = среднее ± 3·σ, где σ = MRbar/1.128. Точки вне границ подсвечиваются. Индексы воспроизводимости Cp/Cpk считаются по границам допуска (LSL/USL), Pp/Ppk — по общему СКО. RPC: app_qc_spc_stats, app_qc_spc_points, app_qc_params, app_qc_measure_add.',
   'SPC контрольная карта Cp Cpk I-MR xbar Rs качество измерения воспроизводимость')
  ,('Качество','Претензии и CAPA',
   'Претензии (app_claims): номер CLM-NNNNN, заказчик, изделие, причина, количество, критичность, статус (новая → принята → в работе → CAPA → закрыта/отклонена). Эскалация претензии создаёт связанную проблему app_issues (источник claims). CAPA-мероприятия (app_capa_actions): корректирующие/предупреждающие, ответственный, срок, статус (запланировано/в работе/выполнено/проверено). RPC: app_claim_save/set_status/escalate/delete, app_capa_save/delete.',
   'претензии claims CAPA корректирующие предупреждающие качество рекламации app_issues')
) as v(category,question,answer,tags)
where not exists (
  select 1 from public.app_knowledge
   where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001' and question = v.question
);
