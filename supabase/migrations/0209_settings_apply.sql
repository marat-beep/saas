-- ============================================================
-- 3DMP Service · 0209_settings_apply.sql
-- Прокидка настроек модулей (app_tenant_settings) в бизнес-логику RPC.
-- app_setting_get + применение: planning.default_capacity (APS),
-- procurement.price_weight (ранжирование КП), production.shift_hours (график смен).
-- Идемпотентно. Зависит от 0001..0208.
-- ============================================================

create or replace function public.app_setting_get(p_token uuid, p_module text, p_key text, p_default text default null)
returns text
language plpgsql stable security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; adm boolean; v text;
begin
  if not public.app_production_allowed(p_token) then return p_default; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  select s.settings ->> p_key into v from public.app_tenant_settings s
   where s.module = lower(trim(p_module)) and (adm or s.tenant_id = ten) limit 1;
  return coalesce(nullif(v,''), p_default);
end $$;

-- ---------- APS-солвер: ёмкость РЦ по умолчанию из настроек ----------
create or replace function public.app_aps_solve(p_token uuid, p_from date default current_date, p_days integer default 14)
returns table (naryads integer, slots integer, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid; uname text; v_from date; v_days int; i int; d date; wcid uuid; cap numeric; used numeric; take numeric; rem numeric;
        rec record; first_day date; last_day date; cnt_n int := 0; cnt_s int := 0; def_cap numeric;
begin
  if not public.app_production_allowed(p_token) then return query select 0,0,'Доступ запрещён'; return; end if;
  if not public.app_can_edit(p_token, 'planning') then return query select 0,0,'Нет прав на планирование'; return; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  select s.ulogin into uname from public.app_session_user(p_token) s;
  def_cap := coalesce(public.app_setting_get(p_token, 'planning', 'default_capacity', null)::numeric, 8);
  v_from := coalesce(p_from, current_date);
  v_days := greatest(least(coalesce(p_days,14),60),1);
  delete from public.app_plan_slots where (adm or tenant_id = ten) and source = 'aps'
    and plan_date between v_from and v_from + (v_days - 1);
  for rec in
    select n.id, n.number, n.wc_id, n.plan_hours, n.fact_hours, n.priority, n.due_date
      from public.app_naryads n
     where (adm or n.tenant_id = ten) and n.status in ('open','in_progress','paused','queue')
     order by case n.priority when 'high' then 0 when 'normal' then 1 else 2 end, n.due_date nulls last, n.created_at
  loop
    rem := greatest(coalesce(rec.plan_hours,0) - coalesce(rec.fact_hours,0), 0);
    if rem <= 0 then continue; end if;
    wcid := rec.wc_id;
    if wcid is null then
      select w.id into wcid from public.app_work_centers w
       where (adm or w.tenant_id = ten)
       order by (select coalesce(sum(s.hours),0) from public.app_plan_slots s where s.wc_id = w.id) limit 1;
    end if;
    if wcid is null then continue; end if;
    first_day := null; last_day := null;
    for i in 0 .. (v_days - 1) loop
      exit when rem <= 0;
      d := v_from + i;
      cap := coalesce((select c.capacity_hours from public.app_wc_capacity c where c.wc_id = wcid and c.cap_date = d), def_cap);
      used := coalesce((select sum(s.hours) from public.app_plan_slots s where s.wc_id = wcid and s.plan_date = d), 0);
      take := least(rem, greatest(cap - used, 0));
      if take > 0 then
        insert into public.app_plan_slots (tenant_id, plan_date, wc_id, naryad_id, hours, source, created_login)
        values (ten, d, wcid, rec.id, take, 'aps', uname);
        cnt_s := cnt_s + 1;
        rem := rem - take;
        if first_day is null then first_day := d; end if;
        last_day := d;
      end if;
    end loop;
    if first_day is not null then
      update public.app_naryads set plan_start = first_day, plan_end = last_day, updated_at = now() where id = rec.id;
      cnt_n := cnt_n + 1;
    end if;
  end loop;
  return query select cnt_n, cnt_s, 'Распределено нарядов: ' || cnt_n || ', слотов: ' || cnt_s;
end $$;

-- ---------- Ранжирование КП: вес цены из настроек ----------
create or replace function public.app_bid_rank(p_token uuid, p_tender_id uuid)
returns table (rank integer, bid_id uuid, supplier text, price numeric, term_days integer, score numeric, basis text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare min_p numeric; min_t numeric; pw numeric; rest numeric;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  pw := coalesce(public.app_setting_get(p_token, 'procurement', 'price_weight', null)::numeric, 60) / 100.0;
  pw := greatest(least(pw, 1), 0);
  rest := 1 - pw;   -- остаток делится: срок 75%, рейтинг 25%
  select min(b.price), min(nullif(b.term_days,0)) into min_p, min_t from public.bids b where b.tender_id = p_tender_id;
  if min_p is null then return; end if;
  return query
    with base as (
      select b.id, coalesce(s.name, b.supplier_name) as sup, b.price, b.term_days, coalesce(s.rating,0) as rt
        from public.bids b left join public.app_suppliers s on lower(s.name) = lower(coalesce(b.supplier_name,''))
       where b.tender_id = p_tender_id
    ), sc as (
      select b.id, b.sup, b.price, b.term_days, b.rt,
             round(pw * (100.0 * min_p / greatest(b.price, 0.01))
                 + rest * 0.75 * (case when b.term_days is null or min_t is null then 50 else 100.0 * min_t / greatest(b.term_days,1) end)
                 + rest * 0.25 * (least(b.rt,5) * 20), 1) as score
        from base b
    )
    select row_number() over (order by sc.score desc, sc.price)::int, sc.id, sc.sup, sc.price, sc.term_days, sc.score,
           'цена ' || round(pw*100) || '% · срок ' || round(rest*75) || '% · рейтинг ' || round(rest*25) || '%'
      from sc order by sc.score desc, sc.price;
end $$;

-- ---------- График смен: часы по умолчанию из настроек ----------
create or replace function public.app_shift_schedule_save(p_token uuid, p_id uuid, p_employee_id uuid, p_date date,
  p_shift_type text, p_hours numeric, p_note text)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; uname text; newid uuid; dep uuid; st text; conflict_kind text; def_h numeric;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён', null::uuid; return; end if;
  if not public.app_can_edit(p_token, 'hr') then return query select false,'Нет прав на правку графика', null::uuid; return; end if;
  select u.tenant_id, s.ulogin into ten, uname from public.app_session_user(p_token) s join public.app_users u on u.id = s.uid;
  def_h := coalesce(public.app_setting_get(p_token, 'production', 'shift_hours', null)::numeric, 8);
  if p_date is null then return query select false,'Укажите дату смены', null::uuid; return; end if;
  select e.department_id into dep from public.app_employees e where e.id = p_employee_id and (public.app_is_platform_admin(p_token) or e.tenant_id = ten);
  if not exists (select 1 from public.app_employees e where e.id = p_employee_id and (public.app_is_platform_admin(p_token) or e.tenant_id = ten)) then
    return query select false,'Сотрудник не найден', null::uuid; return;
  end if;
  st := coalesce(nullif(trim(p_shift_type),''),'1');
  select a.kind into conflict_kind from public.app_absences a
   where a.employee_id = p_employee_id and a.status = 'approved' and p_date between a.date_from and a.date_to limit 1;
  if conflict_kind is not null then
    return query select false, 'Сотрудник в отсутствии (' || conflict_kind || ') — смена не поставлена', null::uuid; return;
  end if;
  if p_id is null then
    if exists (select 1 from public.app_shift_schedule s where s.employee_id = p_employee_id and s.shift_date = p_date and s.shift_type = st and s.tenant_id = ten) then
      return query select false,'Такая смена уже есть', null::uuid; return;
    end if;
    insert into public.app_shift_schedule (tenant_id, employee_id, department_id, shift_date, shift_type, hours, note, created_login)
    values (ten, p_employee_id, dep, p_date, st, coalesce(p_hours, def_h), nullif(trim(p_note),''), uname)
    returning app_shift_schedule.id into newid;
    return query select true,'Смена поставлена в график', newid;
  else
    update public.app_shift_schedule s set employee_id = p_employee_id, department_id = dep, shift_date = p_date,
           shift_type = st, hours = coalesce(p_hours, def_h), note = nullif(trim(p_note),'')
     where s.id = p_id and (public.app_is_platform_admin(p_token) or s.tenant_id = ten)
     returning s.id into newid;
    if newid is null then return query select false,'Смена не найдена', null::uuid; return; end if;
    return query select true,'Смена графика сохранена', newid;
  end if;
exception when unique_violation then
  return query select false,'Такая смена уже есть', null::uuid;
end $$;

-- ================= База знаний =================
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Платформа','Применение настроек модулей в бизнес-логике (0209)',
   'Настройки мастера (app_tenant_settings) применяются в RPC через app_setting_get(token, module, key, default): planning.default_capacity — ёмкость РЦ по умолчанию в APS-солвере; procurement.price_weight — вес цены при ранжировании КП (остаток: срок 75%/рейтинг 25%); production.shift_hours — часы смены по умолчанию в графике. Значение по умолчанию сохраняется, если настройка не задана.',
   'настройки модулей применение app_setting_get capacity price_weight shift_hours')
) as v(category,question,answer,tags)
where not exists (
  select 1 from public.app_knowledge
   where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001'
     and question = 'Применение настроек модулей в бизнес-логике (0209)'
);

-- ================= Права =================
grant execute on function public.app_setting_get(uuid,text,text,text) to anon, authenticated;
grant execute on function public.app_aps_solve(uuid,date,integer) to anon, authenticated;
grant execute on function public.app_bid_rank(uuid,uuid) to anon, authenticated;
grant execute on function public.app_shift_schedule_save(uuid,uuid,uuid,date,text,numeric,text) to anon, authenticated;
