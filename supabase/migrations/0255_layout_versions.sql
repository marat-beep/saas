-- ============================================================
-- 3DMP Service · 0255_layout_versions.sql
-- «Планировки»: история версий проекта (снимки data) — паритет с robot.
-- Идемпотентно. Зависит от 0001..0254.
-- ============================================================

create table if not exists public.app_layout_plan_versions (
  id         uuid primary key default gen_random_uuid(),
  layout_id  uuid not null references public.app_layout_plans (id) on delete cascade,
  version    integer not null default 1,
  name       text,
  data       jsonb not null default '{}'::jsonb,
  created_by text,
  at         timestamptz not null default now()
);
create index if not exists app_layout_plan_versions_idx on public.app_layout_plan_versions (layout_id, at desc);
alter table public.app_layout_plan_versions enable row level security;

create or replace function public.app_layout_plan_version_save(p_token uuid, p_layout_id uuid, p_name text)
returns table (ok boolean, message text, version integer)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid; uname text; d jsonb; v int;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён',0; return; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  select s.ulogin into uname from public.app_session_user(p_token) s;
  select l.data into d from public.app_layout_plans l where l.id = p_layout_id and (adm or l.tenant_id = ten);
  if d is null then return query select false,'Планировка не найдена',0; return; end if;
  select coalesce(max(v.version),0) + 1 into v from public.app_layout_plan_versions v where v.layout_id = p_layout_id;
  insert into public.app_layout_plan_versions (layout_id, version, name, data, created_by)
  values (p_layout_id, v, nullif(trim(p_name),''), d, uname);
  return query select true, 'Версия сохранена', v;
end $$;

create or replace function public.app_layout_plan_version_list(p_token uuid, p_layout_id uuid)
returns table (id uuid, version integer, name text, created_by text, at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query select v.id, v.version, v.name, v.created_by, v.at
    from public.app_layout_plan_versions v
    join public.app_layout_plans l on l.id = v.layout_id
   where v.layout_id = p_layout_id and (adm or l.tenant_id = ten)
   order by v.version desc;
end $$;

create or replace function public.app_layout_plan_version_get(p_token uuid, p_version_id uuid)
returns table (version integer, name text, data jsonb, at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query select v.version, v.name, v.data, v.at
    from public.app_layout_plan_versions v
    join public.app_layout_plans l on l.id = v.layout_id
   where v.id = p_version_id and (adm or l.tenant_id = ten);
end $$;

grant execute on function public.app_layout_plan_version_save(uuid,uuid,text) to anon, authenticated;
grant execute on function public.app_layout_plan_version_list(uuid,uuid) to anon, authenticated;
grant execute on function public.app_layout_plan_version_get(uuid,uuid) to anon, authenticated;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select null, v.category, v.question, v.answer, v.tags
from (values
  ('Производство','Планировки: история версий проекта',
   'В модуле «Планировки» можно сохранять версии проекта (снимок планировки) — app_layout_plan_version_save, список app_layout_plan_version_list, восстановление app_layout_plan_version_get. Кнопка «История»: сохранить версию, посмотреть список, откатиться к выбранной.',
   'планировки история версий снимок проекта app_layout_plan_versions откат')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge k where k.question=v.question);
