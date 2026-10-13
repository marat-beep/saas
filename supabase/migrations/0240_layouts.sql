-- ============================================================
-- 3DMP Service · 0240_layouts.sql
-- Модуль «Планировки» (layout): конструктор расстановки оборудования
-- (цех/офис/компрессорная/участок/линия) — аналог «robot» для SAAS.
-- Проект хранится как jsonb (элементы/сетка/размеры). RPC list/get/save/delete.
-- Таблица app_layout_plans (отдельно от app_layouts из EAM/0166).
-- Идемпотентно. Зависит от 0001..0239.
-- ============================================================

create table if not exists public.app_layout_plans (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid references public.tenants (id),
  name       text not null,
  kind       text not null default 'shop',   -- shop | office | compressor | line | other
  data       jsonb not null default '{}'::jsonb,
  note       text,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists app_layout_plans_idx on public.app_layout_plans (tenant_id, updated_at desc);
alter table public.app_layout_plans enable row level security;

create or replace function public.app_layout_plan_list(p_token uuid)
returns table (id uuid, name text, kind text, items integer, note text, updated_at timestamptz)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query select l.id, l.name, l.kind,
      coalesce(jsonb_array_length(coalesce(l.data->'items','[]'::jsonb)),0)::int, l.note, l.updated_at
    from public.app_layout_plans l where (adm or l.tenant_id = ten) order by l.updated_at desc;
end $$;

create or replace function public.app_layout_plan_get(p_token uuid, p_id uuid)
returns table (id uuid, name text, kind text, data jsonb, note text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  return query select l.id, l.name, l.kind, l.data, l.note
    from public.app_layout_plans l where l.id = p_id and (adm or l.tenant_id = ten);
end $$;

create or replace function public.app_layout_plan_save(p_token uuid, p_id uuid, p_name text, p_kind text, p_data jsonb, p_note text)
returns table (ok boolean, message text, id uuid)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid; uname text; nid uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён',null::uuid; return; end if;
  if not (public.app_can_edit(p_token,'production') or public.app_can_edit(p_token,'registry') or public.app_can_edit(p_token,'docs')) then
    return query select false,'Нет прав на планировки',null::uuid; return; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  select s.ulogin into uname from public.app_session_user(p_token) s;
  if coalesce(trim(p_name),'') = '' then return query select false,'Укажите название планировки',null::uuid; return; end if;
  if p_id is null then
    insert into public.app_layout_plans (tenant_id, name, kind, data, note, created_by)
    values (ten, left(trim(p_name),160), coalesce(nullif(trim(p_kind),''),'shop'), coalesce(p_data,'{}'::jsonb), nullif(trim(p_note),''), uname)
    returning id into nid;
    return query select true,'Планировка создана', nid;
  else
    update public.app_layout_plans set name=left(trim(p_name),160), kind=coalesce(nullif(trim(p_kind),''),kind),
      data=coalesce(p_data,data), note=nullif(trim(p_note),''), updated_at=now()
     where id=p_id and (adm or tenant_id=ten) returning id into nid;
    if nid is null then return query select false,'Планировка не найдена',null::uuid; return; end if;
    return query select true,'Планировка сохранена', nid;
  end if;
end $$;

create or replace function public.app_layout_plan_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare adm boolean; ten uuid;
begin
  if not public.app_production_allowed(p_token) then return query select false,'Доступ запрещён'; return; end if;
  if not (public.app_can_edit(p_token,'production') or public.app_can_edit(p_token,'registry')) then return query select false,'Нет прав'; return; end if;
  adm := public.app_is_platform_admin(p_token); ten := public.app_my_tenant(p_token);
  delete from public.app_layout_plans where id=p_id and (adm or tenant_id=ten);
  return query select true,'Планировка удалена';
end $$;

grant execute on function public.app_layout_plan_list(uuid) to anon, authenticated;
grant execute on function public.app_layout_plan_get(uuid,uuid) to anon, authenticated;
grant execute on function public.app_layout_plan_save(uuid,uuid,text,text,jsonb,text) to anon, authenticated;
grant execute on function public.app_layout_plan_delete(uuid,uuid) to anon, authenticated;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select null, v.category, v.question, v.answer, v.tags
from (values
  ('Производство','Модуль «Планировки»: расстановка оборудования и цехов',
   'Конструктор планировок (аналог онлайн-конструктора роботизированной линии): перетаскивание элементов из палитры (станки, роботы/манипуляторы, конвейеры, хранение, инфраструктура, офисная мебель, зоны), размеры в мм, сетка и привязка, поворот и изменение размера, стадии (действующее/новое/будущее) с цветовой легендой, панорама/зум, экспорт/импорт JSON и печать. Проекты сохраняются в app_layout_plans (jsonb). Для цеха, офиса, компрессорной, участка и компоновки автоматических линий. RPC: app_layout_plan_list/get/save/delete.',
   'планировка расстановка оборудования цех офис компрессорная линия конструктор layout app_layout_plans')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge k where k.question=v.question);
