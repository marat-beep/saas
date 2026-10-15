-- ============================================================
-- 3DMP Service · 0261_refdata.sql  (R5 · PROP-35 — отраслевые справочники с атрибутами)
-- Таблицы-справочники: стойки/станки ЧПУ (app_ref_cnc) и инструмент (app_ref_tool)
-- с атрибутами, плюс RPC list/save/delete (tenant-scoped, идемпотентно). UI — apps/refdata.
-- ============================================================

create table if not exists public.app_ref_cnc (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants (id),
  vendor text,
  model text not null,
  cnc_system text,
  axes int,
  max_rpm int,
  postprocessor text,
  note text,
  active boolean not null default true,
  created_at timestamptz not null default now()
);
create index if not exists app_ref_cnc_idx on public.app_ref_cnc (tenant_id, active);

create table if not exists public.app_ref_tool (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants (id),
  kind text,
  name text not null,
  material text,
  diameter_mm numeric,
  corner_radius_mm numeric,
  life_min int,
  resharpen_limit int,
  note text,
  active boolean not null default true,
  created_at timestamptz not null default now()
);
create index if not exists app_ref_tool_idx on public.app_ref_tool (tenant_id, active);

-- ---------- Стойки/станки ЧПУ ----------
create or replace function public.app_ref_cnc_list(p_token uuid)
returns table (id uuid, vendor text, model text, cnc_system text, axes int, max_rpm int, postprocessor text, note text, active boolean)
language plpgsql security definer set search_path = public as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select c.id, c.vendor, c.model, c.cnc_system, c.axes, c.max_rpm, c.postprocessor, c.note, c.active
    from public.app_ref_cnc c where (urole = 'admin' or c.tenant_id = ten) order by c.vendor, c.model;
end $$;
grant execute on function public.app_ref_cnc_list(uuid) to anon, authenticated;

create or replace function public.app_ref_cnc_save(p_token uuid, p_id uuid, p_vendor text, p_model text, p_cnc_system text, p_axes int, p_max_rpm int, p_postprocessor text, p_note text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public as $$
declare urole text; ten uuid; rid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_model), '') = '' then return query select false, 'Укажите модель'; return; end if;
  if p_id is null then
    insert into public.app_ref_cnc (tenant_id, vendor, model, cnc_system, axes, max_rpm, postprocessor, note, active)
    values (ten, p_vendor, p_model, p_cnc_system, p_axes, p_max_rpm, p_postprocessor, p_note, true) returning id into rid;
  else
    update public.app_ref_cnc set vendor = p_vendor, model = p_model, cnc_system = p_cnc_system, axes = p_axes,
      max_rpm = p_max_rpm, postprocessor = p_postprocessor, note = p_note
      where id = p_id and (urole = 'admin' or tenant_id = ten) returning id into rid;
  end if;
  if rid is null then return query select false, 'Не найдено'; return; end if;
  return query select true, 'Сохранено';
end $$;
grant execute on function public.app_ref_cnc_save(uuid,uuid,text,text,text,int,int,text,text) to anon, authenticated;

create or replace function public.app_ref_cnc_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  delete from public.app_ref_cnc where id = p_id and (urole = 'admin' or tenant_id = ten);
  return query select true, 'Удалено';
end $$;
grant execute on function public.app_ref_cnc_delete(uuid,uuid) to anon, authenticated;

-- ---------- Инструмент ----------
create or replace function public.app_ref_tool_list(p_token uuid)
returns table (id uuid, kind text, name text, material text, diameter_mm numeric, corner_radius_mm numeric, life_min int, resharpen_limit int, note text, active boolean)
language plpgsql security definer set search_path = public as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  return query select t.id, t.kind, t.name, t.material, t.diameter_mm, t.corner_radius_mm, t.life_min, t.resharpen_limit, t.note, t.active
    from public.app_ref_tool t where (urole = 'admin' or t.tenant_id = ten) order by t.kind, t.name;
end $$;
grant execute on function public.app_ref_tool_list(uuid) to anon, authenticated;

create or replace function public.app_ref_tool_save(p_token uuid, p_id uuid, p_kind text, p_name text, p_material text, p_diameter numeric, p_radius numeric, p_life int, p_resharpen int, p_note text)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public as $$
declare urole text; ten uuid; rid uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  if coalesce(trim(p_name), '') = '' then return query select false, 'Укажите название'; return; end if;
  if p_id is null then
    insert into public.app_ref_tool (tenant_id, kind, name, material, diameter_mm, corner_radius_mm, life_min, resharpen_limit, note, active)
    values (ten, p_kind, p_name, p_material, p_diameter, p_radius, p_life, p_resharpen, p_note, true) returning id into rid;
  else
    update public.app_ref_tool set kind = p_kind, name = p_name, material = p_material, diameter_mm = p_diameter,
      corner_radius_mm = p_radius, life_min = p_life, resharpen_limit = p_resharpen, note = p_note
      where id = p_id and (urole = 'admin' or tenant_id = ten) returning id into rid;
  end if;
  if rid is null then return query select false, 'Не найдено'; return; end if;
  return query select true, 'Сохранено';
end $$;
grant execute on function public.app_ref_tool_save(uuid,uuid,text,text,text,numeric,numeric,int,int,text) to anon, authenticated;

create or replace function public.app_ref_tool_delete(p_token uuid, p_id uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = public as $$
declare urole text; ten uuid;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  ten := public.app_my_tenant(p_token);
  delete from public.app_ref_tool where id = p_id and (urole = 'admin' or tenant_id = ten);
  return query select true, 'Удалено';
end $$;
grant execute on function public.app_ref_tool_delete(uuid,uuid) to anon, authenticated;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select null, v.category, v.question, v.answer, v.tags
from (values
  ('Справка','Отраслевые справочники: стойки/станки ЧПУ и инструмент',
   'Модуль «Отраслевые справочники» ведёт таблицы с атрибутами: стойки/станки ЧПУ (производитель, модель, система ЧПУ, число осей, макс. обороты, постпроцессор) и инструмент (тип, материал, диаметр, радиус, стойкость, число переточек). Используется для подбора оборудования и оснастки, интеграции с CAM/постпроцессорами.',
   'отраслевые справочники ЧПУ стойки инструмент постпроцессор стойкость')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge k where k.question=v.question);
