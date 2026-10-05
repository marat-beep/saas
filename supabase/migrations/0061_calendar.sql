-- ============================================================
-- 3DMP Service · 0061_calendar.sql  (v39 — ЭПИК D: производственный календарь, B38)
-- Календарь РФ (праздники/сокращённые) + расчёт рабочих дней. База знаний.
-- Зависит от 0001..0060.
-- ============================================================

create table if not exists public.app_calendar (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid references public.tenants (id),
  cal_date   date not null,
  kind       text not null default 'holiday', -- holiday|short|work|shift
  name       text,
  note       text,
  created_at timestamptz not null default now(),
  unique (tenant_id, cal_date)
);
create index if not exists app_calendar_idx on public.app_calendar (cal_date);
alter table public.app_calendar enable row level security;

-- ---------- Список ----------
create or replace function public.app_calendar_list(p_token uuid, p_from date default null, p_to date default null)
returns table (id uuid, cal_date date, kind text, name text, note text)
language plpgsql security definer set search_path = public
as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select c.id, c.cal_date, c.kind, c.name, c.note
    from public.app_calendar c
    where (c.tenant_id is null or c.tenant_id = ten or urole='admin')
      and (p_from is null or c.cal_date >= p_from) and (p_to is null or c.cal_date <= p_to)
    order by c.cal_date;
end $$;

-- ---------- Добавить/изменить день ----------
create or replace function public.app_calendar_save(p_token uuid, p_date date, p_kind text, p_name text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid; urole text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','hr','chief') then return query select false,'Недостаточно прав'; return; end if;
  if p_date is null then return query select false,'Укажите дату'; return; end if;
  insert into public.app_calendar (tenant_id, cal_date, kind, name)
  values (ten, p_date, coalesce(nullif(trim(p_kind),''),'holiday'), nullif(trim(p_name),''))
  on conflict (tenant_id, cal_date) do update set kind = excluded.kind, name = excluded.name;
  return query select true,'Сохранено';
end $$;

create or replace function public.app_calendar_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
declare ten uuid; urole text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','hr','chief') then return query select false,'Недостаточно прав'; return; end if;
  delete from public.app_calendar where id=p_id and (urole='admin' or tenant_id=ten);
  return query select true,'Удалено';
end $$;

-- ---------- Прибавить рабочие дни ----------
create or replace function public.app_calendar_add_days(p_token uuid, p_start date, p_days integer)
returns table (result date)
language plpgsql security definer set search_path = public
as $$
declare ten uuid; urole text; d date; left_n integer;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  d := coalesce(p_start, current_date);
  left_n := greatest(coalesce(p_days,0),0);
  while left_n > 0 loop
    d := d + 1;
    if extract(dow from d) not in (0,6)
       and not exists (select 1 from public.app_calendar c where c.cal_date = d and c.kind in ('holiday') and (c.tenant_id is null or c.tenant_id=ten)) then
      left_n := left_n - 1;
    end if;
  end loop;
  return query select d;
end $$;

grant execute on function public.app_calendar_list(uuid,date,date) to anon, authenticated;
grant execute on function public.app_calendar_save(uuid,date,text,text) to anon, authenticated;
grant execute on function public.app_calendar_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_calendar_add_days(uuid,date,integer) to anon, authenticated;

-- ---------- Наполнение: праздники РФ 2025–2026 (глобально) ----------
insert into public.app_calendar (tenant_id, cal_date, kind, name)
select null, d::date, v.kind, v.name
from (values
  ('2025-01-01','holiday','Новый год'),('2025-01-02','holiday','Новогодние каникулы'),('2025-01-03','holiday','Новогодние каникулы'),
  ('2025-01-06','holiday','Новогодние каникулы'),('2025-01-07','holiday','Рождество'),('2025-01-08','holiday','Новогодние каникулы'),
  ('2025-01-09','work','Рабочий день (перенос)'),('2025-02-23','holiday','День защитника Отечества'),('2025-03-08','holiday','8 Марта'),
  ('2025-05-01','holiday','Праздник Весны и Труда'),('2025-05-09','holiday','День Победы'),('2025-06-12','holiday','День России'),
  ('2025-11-04','holiday','День народного единства'),('2025-03-07','short','Сокращённый день'),('2025-04-30','short','Сокращённый день'),
  ('2025-05-08','short','Сокращённый день'),('2025-06-11','short','Сокращённый день'),('2025-11-03','short','Сокращённый день'),('2025-12-31','short','Сокращённый день'),
  ('2026-01-01','holiday','Новый год'),('2026-01-02','holiday','Новогодние каникулы'),('2026-01-05','holiday','Новогодние каникулы'),
  ('2026-01-06','holiday','Новогодние каникулы'),('2026-01-07','holiday','Рождество'),('2026-01-08','holiday','Новогодние каникулы'),
  ('2026-02-23','holiday','День защитника Отечества'),('2026-03-08','holiday','8 Марта'),('2026-05-01','holiday','Праздник Весны и Труда'),
  ('2026-05-09','holiday','День Победы'),('2026-06-12','holiday','День России'),('2026-11-04','holiday','День народного единства')
) as v(d, kind, name)
where not exists (select 1 from public.app_calendar where tenant_id is null);

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Календарь','Производственный календарь РФ',
   'Модуль «Календарь»: праздничные, сокращённые и рабочие (переносы) дни. Используется для расчёта рабочих дней и сроков: функция «прибавить рабочие дни» учитывает выходные и праздники. Праздники заданы глобально (РФ) и могут дополняться организацией.',
   'календарь праздники рабочие дни переносы срок РФ')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Производственный календарь РФ');
