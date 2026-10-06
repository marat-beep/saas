-- ============================================================
-- 3DMP Service · 0077_setup.sql  (v55 — Сессия G: B20 «Наладка»)
-- Наладки/переналадки оборудования: план/факт часов, статусы, исполнитель,
-- привязка к наряду. База знаний. Зависит от 0001..0076.
-- ============================================================

create table if not exists public.app_setups (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid references public.tenants (id),
  naryad_id     uuid references public.app_naryads (id) on delete set null,
  equipment     text,
  setup_type    text not null default 'setup',  -- setup|changeover|trial|adjust
  planned_hours numeric default 0,
  fact_hours    numeric default 0,
  status        text not null default 'planned', -- planned|in_progress|done|cancelled
  assignee      text,
  note          text,
  created_login text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists app_setups_idx on public.app_setups (tenant_id, status, created_at desc);
alter table public.app_setups enable row level security;

create or replace function public.app_setups_list(p_token uuid, p_q text default null)
returns table (id uuid, naryad_number text, equipment text, setup_type text, planned_hours numeric,
               fact_hours numeric, status text, assignee text, naryad_id uuid, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query
    select s.id, na.number, s.equipment, s.setup_type, s.planned_hours, s.fact_hours, s.status, s.assignee, s.naryad_id, s.created_at
    from public.app_setups s left join public.app_naryads na on na.id = s.naryad_id
    where (urole='admin' or s.tenant_id=ten)
      and (qq='' or lower(coalesce(s.equipment,'')) like '%'||qq||'%' or lower(coalesce(s.assignee,'')) like '%'||qq||'%' or lower(coalesce(na.number,'')) like '%'||qq||'%')
    order by (s.status='done'), s.created_at desc;
end $$;

create or replace function public.app_setup_save(p_token uuid, p_id uuid, p_naryad_id uuid, p_equipment text,
  p_setup_type text, p_planned_hours numeric, p_assignee text, p_note text)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; ulogin text; sid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if urole not in ('admin','owner','manager','director','chief','master','technologist','operator') then raise exception 'Недостаточно прав'; return; end if;
  if coalesce(trim(p_equipment),'')='' then raise exception 'Укажите оборудование'; return; end if;
  if p_id is null then
    insert into public.app_setups (tenant_id, naryad_id, equipment, setup_type, planned_hours, assignee, note, created_login)
    values (ten, p_naryad_id, trim(p_equipment), coalesce(nullif(trim(p_setup_type),''),'setup'), coalesce(p_planned_hours,0), nullif(trim(p_assignee),''), nullif(trim(p_note),''), ulogin)
    returning id into sid;
    return query select sid, 'Наладка создана';
  else
    update public.app_setups set naryad_id=p_naryad_id, equipment=trim(p_equipment), setup_type=coalesce(nullif(trim(p_setup_type),''),setup_type),
      planned_hours=coalesce(p_planned_hours,planned_hours), assignee=nullif(trim(p_assignee),''), note=nullif(trim(p_note),''), updated_at=now()
     where id=p_id and (urole='admin' or tenant_id=ten) returning id into sid;
    return query select sid, 'Наладка обновлена';
  end if;
end $$;

create or replace function public.app_setup_set_status(p_token uuid, p_id uuid, p_status text, p_fact_hours numeric default null)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if p_status not in ('planned','in_progress','done','cancelled') then return query select false,'Неверный статус'; return; end if;
  update public.app_setups set status=p_status,
    fact_hours = coalesce(p_fact_hours, fact_hours),
    updated_at = now()
   where id=p_id and (urole='admin' or tenant_id=ten);
  return query select true,'Статус обновлён';
end $$;

create or replace function public.app_setup_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  delete from public.app_setups where id=p_id and (urole='admin' or tenant_id=ten);
  return query select true,'Наладка удалена';
end $$;

create or replace function public.app_setups_kpi(p_token uuid)
returns table (total bigint, planned bigint, in_progress bigint, done bigint, hours_planned numeric, hours_fact numeric)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select count(*), count(*) filter (where status='planned'), count(*) filter (where status='in_progress'),
    count(*) filter (where status='done'), coalesce(sum(planned_hours),0), coalesce(sum(fact_hours),0)
    from public.app_setups where (urole='admin' or tenant_id=ten);
end $$;

grant execute on function public.app_setups_list(uuid,text) to anon, authenticated;
grant execute on function public.app_setup_save(uuid,uuid,uuid,text,text,numeric,text,text) to anon, authenticated;
grant execute on function public.app_setup_set_status(uuid,uuid,text,numeric) to anon, authenticated;
grant execute on function public.app_setup_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_setups_kpi(uuid) to anon, authenticated;

-- ---------- Демо (тенант A) ----------
insert into public.app_setups (tenant_id, naryad_id, equipment, setup_type, planned_hours, fact_hours, status, assignee, note, created_login)
select 'aaaaaaaa-0000-0000-0000-000000000001',
  (select id from public.app_naryads where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' order by created_at limit 1),
  v.eq, v.st, v.ph, v.fh, v.status, v.who, v.note, 'master'
from (values
  ('Feeler FTC-350Xl','changeover', 1.5, 0, 'planned','Сидоров','Переналадка под новый патрон'),
  ('ЭЭО проволочная','setup', 2.0, 1.5, 'in_progress','Петров','Установка проволоки 0.25'),
  ('Плоскошлифовальный','adjust', 0.5, 0.5, 'done','Иванов','Правка круга')
) as v(eq,st,ph,fh,status,who,note)
where not exists (select 1 from public.app_setups where tenant_id='aaaaaaaa-0000-0000-0000-000000000001');

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Производство','Наладка оборудования (B20)',
   'Модуль «Наладка»: учёт наладок/переналадок/пробных пусков/подналадок оборудования с планом и фактом часов, исполнителем и привязкой к наряду. Статусы: запланирована → в работе → выполнена. KPI: всего, план/факт часов. Помогает видеть долю простоев на переналадку.',
   'наладка переналадка setup простои часы план факт B20')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Наладка оборудования (B20)');
