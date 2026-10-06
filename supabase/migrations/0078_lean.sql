-- ============================================================
-- 3DMP Service · 0078_lean.sql  (v56 — Сессия H: B7 «Бережливое производство»)
-- Кайдзен-предложения и 7 видов потерь: статусы, экономия, эффект.
-- База знаний. Зависит от 0001..0077.
-- ============================================================

create table if not exists public.app_lean_actions (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid references public.tenants (id),
  title       text not null,
  category    text not null default 'other', -- overproduction|waiting|transport|overprocessing|inventory|motion|defects|other
  description text,
  author      text,
  status      text not null default 'idea',  -- idea|approved|in_progress|done|rejected
  savings     numeric default 0,             -- экономия ₽/год
  effect      text,
  created_login text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists app_lean_actions_idx on public.app_lean_actions (tenant_id, status, category);
alter table public.app_lean_actions enable row level security;

create or replace function public.app_lean_list(p_token uuid, p_q text default null)
returns table (id uuid, title text, category text, author text, status text, savings numeric, effect text, description text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; qq text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token); qq := lower(coalesce(trim(p_q),''));
  return query select a.id, a.title, a.category, a.author, a.status, a.savings, a.effect, a.description, a.created_at
    from public.app_lean_actions a
    where (urole='admin' or a.tenant_id=ten)
      and (qq='' or lower(a.title) like '%'||qq||'%' or lower(coalesce(a.author,'')) like '%'||qq||'%' or lower(coalesce(a.description,'')) like '%'||qq||'%')
    order by (a.status='done'), a.created_at desc;
end $$;

create or replace function public.app_lean_save(p_token uuid, p_id uuid, p_title text, p_category text,
  p_description text, p_author text, p_savings numeric, p_effect text)
returns table (id uuid, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare ten uuid; urole text; ulogin text; lid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole, s.ulogin into urole, ulogin from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_title),'')='' then raise exception 'Укажите название предложения'; return; end if;
  if p_category not in ('overproduction','waiting','transport','overprocessing','inventory','motion','defects','other') then raise exception 'Неверная категория потерь'; return; end if;
  if p_id is null then
    insert into public.app_lean_actions (tenant_id, title, category, description, author, savings, effect, created_login)
    values (ten, trim(p_title), p_category, nullif(trim(p_description),''), coalesce(nullif(trim(p_author),''), ulogin), coalesce(p_savings,0), nullif(trim(p_effect),''), ulogin)
    returning id into lid;
    return query select lid, 'Предложение добавлено';
  else
    update public.app_lean_actions set title=trim(p_title), category=p_category, description=nullif(trim(p_description),''),
      author=coalesce(nullif(trim(p_author),''),author), savings=coalesce(p_savings,0), effect=nullif(trim(p_effect),''), updated_at=now()
     where id=p_id and (urole='admin' or tenant_id=ten) returning id into lid;
    return query select lid, 'Предложение обновлено';
  end if;
end $$;

create or replace function public.app_lean_set_status(p_token uuid, p_id uuid, p_status text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if p_status not in ('idea','approved','in_progress','done','rejected') then return query select false,'Неверный статус'; return; end if;
  update public.app_lean_actions set status=p_status, updated_at=now() where id=p_id and (urole='admin' or tenant_id=ten);
  return query select true,'Статус обновлён';
end $$;

create or replace function public.app_lean_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  delete from public.app_lean_actions where id=p_id and (urole='admin' or tenant_id=ten);
  return query select true,'Предложение удалено';
end $$;

create or replace function public.app_lean_kpi(p_token uuid)
returns table (total bigint, ideas bigint, active bigint, done bigint, savings_sum numeric, top_category text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text; ten uuid; tc text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  select a.category into tc from public.app_lean_actions a
    where (urole='admin' or a.tenant_id=ten) group by a.category order by count(*) desc limit 1;
  return query select count(*), count(*) filter (where status='idea'),
    count(*) filter (where status in ('approved','in_progress')),
    count(*) filter (where status='done'),
    coalesce(sum(savings) filter (where status='done'),0), tc
    from public.app_lean_actions where (urole='admin' or tenant_id=ten);
end $$;

grant execute on function public.app_lean_list(uuid,text) to anon, authenticated;
grant execute on function public.app_lean_save(uuid,uuid,text,text,text,text,numeric,text) to anon, authenticated;
grant execute on function public.app_lean_set_status(uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_lean_delete(uuid,uuid) to anon, authenticated;
grant execute on function public.app_lean_kpi(uuid) to anon, authenticated;

-- ---------- Демо (тенант A) ----------
insert into public.app_lean_actions (tenant_id, title, category, description, author, status, savings, effect, created_login)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.title, v.cat, v.descr, v.author, v.status, v.sav, v.eff, 'master'
from (values
  ('Сократить время поиска инструмента','motion','Организовать тумбы с маркировкой у станков','Мастер', 'done', 60000, 'поиск инструмента −40%'),
  ('Уменьшить переналадку','waiting','SMED: подготовка оснастки заранее','Технолог','in_progress',120000, 'простои −25%'),
  ('Повторное использование СОЖ','inventory','Система регенерации СОЖ','Снабженец','idea',80000, null),
  ('Снизить брак по размеру','defects','Контрольный калибр на операции 20','ОТК','approved',150000,'брак −0.5%')
) as v(title,cat,descr,author,status,sav,eff)
where not exists (select 1 from public.app_lean_actions where tenant_id='aaaaaaaa-0000-0000-0000-000000000001');

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Производство','Бережливое производство (B7)',
   'Модуль «Бережливое производство»: кайдзен-предложения по 7 видам потерь (перепроизводство, ожидание, транспортировка, излишняя обработка, запасы, движения, дефекты). Статусы: идея → одобрено → в работе → внедрено. Учёт экономии (₽/год) и эффекта. KPI: всего, идей, в работе, внедрено, сумма экономии.',
   'бережливое производство lean кайдзен 7 видов потерь экономия B7')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Бережливое производство (B7)');
