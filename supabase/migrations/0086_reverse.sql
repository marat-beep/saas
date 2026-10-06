-- ============================================================
-- 3DMP Service · 0086_reverse.sql  (v64 — Сессия O: A6 «Реверс-инжиниринг»)
-- Заявки на обратное проектирование: метод съёма (скан/обмер/чертёж/фото/
-- образец), результат (модель/чертёж), статусы. Зависит от 0001..0085.
-- ============================================================

create sequence if not exists public.app_reverse_seq;
create table if not exists public.app_reverse_orders (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  number        text,
  title         text not null,
  customer      text,
  part          text,
  method        text not null default 'scan',   -- scan|measure|drawing|photo|sample
  result_type   text not null default 'model',  -- model|drawing|both
  status        text not null default 'new',    -- new|scanning|modelling|review|done|cancelled
  assignee      text,
  order_id      uuid references public.app_orders (id) on delete set null,
  note          text,
  created_login text,
  created_at    timestamptz not null default now()
);
create index if not exists app_reverse_orders_idx on public.app_reverse_orders (tenant_id, status, created_at desc);
alter table public.app_reverse_orders enable row level security;

create or replace function public.app_reverse_list(p_token uuid, p_q text default null)
returns table (id uuid, number text, title text, customer text, part text, method text, result_type text,
               status text, assignee text, order_number text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query
    select r.id, r.number, r.title, r.customer, r.part, r.method, r.result_type, r.status, r.assignee, o.number, r.created_at
    from public.app_reverse_orders r left join public.app_orders o on o.id=r.order_id
    where (urole='admin' or r.tenant_id=ten)
      and (qq='' or lower(r.title) like '%'||qq||'%' or lower(coalesce(r.customer,'')) like '%'||qq||'%' or lower(coalesce(r.part,'')) like '%'||qq||'%')
    order by (r.status='done'), r.created_at desc;
end $$;

create or replace function public.app_reverse_save(p_token uuid, p_id uuid, p_title text, p_customer text, p_part text,
  p_method text, p_result_type text, p_assignee text, p_order_id uuid, p_note text)
returns table (id uuid, number text, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; ulogin text; rid uuid; rnum text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director','chief','master','technologist') then raise exception 'Недостаточно прав'; return; end if;
  if coalesce(trim(p_title),'')='' then raise exception 'Укажите изделие/название'; return; end if;
  if coalesce(p_method,'scan') not in ('scan','measure','drawing','photo','sample') then raise exception 'Неверный метод'; return; end if;
  if coalesce(p_result_type,'model') not in ('model','drawing','both') then raise exception 'Неверный результат'; return; end if;
  if p_id is null then
    rnum := 'REV-' || lpad(nextval('public.app_reverse_seq')::text, 5, '0');
    insert into public.app_reverse_orders (tenant_id, number, title, customer, part, method, result_type, assignee, order_id, note, created_login)
    values (ten, rnum, trim(p_title), nullif(trim(p_customer),''), nullif(trim(p_part),''), p_method, p_result_type,
            nullif(trim(p_assignee),''), p_order_id, nullif(trim(p_note),''), ulogin)
    returning id into rid;
    return query select rid, rnum, 'Заявка на реверс-инжиниринг создана';
  else
    update public.app_reverse_orders set title=trim(p_title), customer=nullif(trim(p_customer),''), part=nullif(trim(p_part),''),
      method=p_method, result_type=p_result_type, assignee=nullif(trim(p_assignee),''), order_id=p_order_id, note=nullif(trim(p_note),'')
     where id=p_id and (urole='admin' or tenant_id=ten) returning id, number into rid, rnum;
    return query select rid, rnum, 'Заявка обновлена';
  end if;
end $$;

create or replace function public.app_reverse_set_status(p_token uuid, p_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if p_status not in ('new','scanning','modelling','review','done','cancelled') then return query select false,'Неверный статус'; return; end if;
  update public.app_reverse_orders set status=p_status where id=p_id and (urole='admin' or tenant_id=ten);
  return query select true,'Статус обновлён';
end $$;

create or replace function public.app_reverse_kpi(p_token uuid)
returns table (total bigint, new_cnt bigint, in_progress bigint, done bigint, by_drawing bigint)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select count(*), count(*) filter (where status='new'),
    count(*) filter (where status in ('scanning','modelling','review')),
    count(*) filter (where status='done'),
    count(*) filter (where method='drawing')
    from public.app_reverse_orders where (urole='admin' or tenant_id=ten);
end $$;

grant execute on function public.app_reverse_list(uuid,text) to anon, authenticated;
grant execute on function public.app_reverse_save(uuid,uuid,text,text,text,text,text,text,uuid,text) to anon, authenticated;
grant execute on function public.app_reverse_set_status(uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_reverse_kpi(uuid) to anon, authenticated;

-- ---------- Демо (тенант A) ----------
insert into public.app_reverse_orders (tenant_id, number, title, customer, part, method, result_type, status, assignee, created_login)
select 'aaaaaaaa-0000-0000-0000-000000000001',
  'REV-' || lpad(nextval('public.app_reverse_seq')::text,5,'0'), v.title, v.cust, v.part, v.m, v.rt, v.st, v.who, 'technologist'
from (values
  ('Обратное проектирование зубчатого колеса','ООО «Механика»','Колесо z=42','scan','model','modelling','Технолог'),
  ('Обмер корпуса редуктора','АО «Привод»','Корпус','measure','drawing','done','Мастер')
) as v(title,cust,part,m,rt,st,who)
where not exists (select 1 from public.app_reverse_orders where tenant_id='aaaaaaaa-0000-0000-0000-000000000001');

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Продажи','Реверс-инжиниринг (A6)',
   'Модуль «Реверс-инжиниринг»: заявки на обратное проектирование (REV-NNNNN) — изделие, заказчик, деталь, метод съёма данных (3D-скан/обмер/чертёж/фото/образец), требуемый результат (3D-модель/чертёж/оба), исполнитель, связь с заявкой. Статусы: новая → сканирование → моделирование → проверка → готово. KPI по этапам.',
   'реверс-инжиниринг обратное проектирование 3д скан обмер чертёж модель A6')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Реверс-инжиниринг (A6)');
