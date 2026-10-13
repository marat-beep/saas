-- ============================================================
-- 3DMP Service · 0241_calendar2.sql
-- X12 (остаток): производственный календарь — автозагрузка праздников РФ
-- за год и API рабочих дней (для планирования/кадров).
--  • app_calendar_load_ru(p_token, p_year) — догрузка фиксированных
--    праздников РФ (01.01–08.01, 23.02, 08.03, 01.05, 09.05, 12.06, 04.11).
--  • app_workdays(p_token, p_from, p_days) — список следующих рабочих дней.
--  • app_workdays_between(p_token, p_from, p_to) — число рабочих дней.
-- Идемпотентно. Зависит от 0001..0240.
-- ============================================================

create or replace function public.app_calendar_load_ru(p_token uuid, p_year integer)
returns table (ok boolean, added integer, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare y int; n int := 0; d date;
begin
  if not public.app_production_allowed(p_token) then return query select false,0,'Доступ запрещён'; return; end if;
  if not (public.app_can_edit(p_token,'hr') or public.app_can_edit(p_token,'production') or public.app_is_platform_admin(p_token)) then
    return query select false,0,'Нет прав'; return; end if;
  y := coalesce(p_year, extract(year from current_date)::int);
  for d in select gs::date from generate_series(make_date(y,1,1), make_date(y,12,31), interval '1 day') gs loop
    if (extract(month from d), extract(day from d)) in
       ((1,1),(1,2),(1,3),(1,4),(1,5),(1,6),(1,7),(1,8),(2,23),(3,8),(5,1),(5,9),(6,12),(11,4)) then
      if not exists (select 1 from public.app_calendar c where c.tenant_id is null and c.cal_date = d) then
        insert into public.app_calendar (tenant_id, cal_date, kind, name) values (null, d, 'holiday', 'Праздник РФ');
        n := n + 1;
      end if;
    end if;
  end loop;
  return query select true, n, 'Праздники РФ за ' || y || ': добавлено ' || n || ' (всего заполнено фиксированных)';
end $$;

create or replace function public.app_workdays(p_token uuid, p_from date, p_days integer)
returns table (day date)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid; f date; lim date;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  f := coalesce(p_from, current_date);
  lim := f + (greatest(coalesce(p_days,0),0) * 2 + 12);
  return query
    select gs::date from generate_series(f, lim, interval '1 day') gs
     where gs::date >= f
       and extract(dow from gs::date) not in (0,6)
       and not exists (select 1 from public.app_calendar c
                        where c.cal_date = gs::date and c.kind in ('holiday')
                          and (c.tenant_id is null or c.tenant_id = ten or adm))
     order by gs::date
     limit greatest(coalesce(p_days,0),0);
end $$;

create or replace function public.app_workdays_between(p_token uuid, p_from date, p_to date)
returns integer
language plpgsql security definer set search_path = public
as $$
declare adm boolean; ten uuid; a date; b date; n int;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  a := coalesce(p_from, current_date); b := coalesce(p_to, current_date);
  if b < a then return 0; end if;
  select count(*) into n from generate_series(a, b, interval '1 day') gs
   where extract(dow from gs::date) not in (0,6)
     and not exists (select 1 from public.app_calendar c
                      where c.cal_date = gs::date and c.kind in ('holiday')
                        and (c.tenant_id is null or c.tenant_id = ten or adm));
  return coalesce(n,0);
end $$;

grant execute on function public.app_calendar_load_ru(uuid,integer) to anon, authenticated;
grant execute on function public.app_workdays(uuid,date,integer) to anon, authenticated;
grant execute on function public.app_workdays_between(uuid,date,date) to anon, authenticated;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select null, v.category, v.question, v.answer, v.tags
from (values
  ('Календарь','Календарь: автозагрузка праздников РФ и API рабочих дней',
   'Кнопка «Загрузить праздники РФ» добавляет фиксированные праздники за выбранный год (01.01–08.01, 23.02, 08.03, 01.05, 09.05, 12.06, 04.11) — RPC app_calendar_load_ru. API рабочих дней: app_workdays (список N следующих рабочих дней) и app_workdays_between (число рабочих дней между датами) — учитывают выходные и праздники; используются планированием (прибавление рабочих дней app_calendar_add_days) и кадрами (графики).',
   'календарь праздники РФ автозагрузка рабочие дни API app_workdays планирование кадры')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge k where k.question=v.question);
