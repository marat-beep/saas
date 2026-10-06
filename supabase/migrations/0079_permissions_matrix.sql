-- ============================================================
-- 3DMP Service · 0079_permissions_matrix.sql  (v57 — P8 шаг 1)
-- Покрытие матрицы прав (app_role_permissions) новыми модулями + helper app_guard
-- для серверной проверки в мутирующих RPC. admin/owner — всегда полный доступ.
-- Идемпотентно. Зависит от 0001..0078.
-- ============================================================

create or replace function public.app_guard(p_token uuid, p_module text, p_action text default 'view')
returns void
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
begin
  if not public.app_can(p_token, p_module, coalesce(nullif(p_action,''),'view')) then
    raise exception 'Нет прав: % (%)', p_module, coalesce(nullif(p_action,''),'view');
  end if;
end $$;

grant execute on function public.app_guard(uuid,text,text) to anon, authenticated;

-- ---------- Матрица: назначить право правки по ролям (view=true всегда для этих строк) ----------
insert into public.app_role_permissions (id, tenant_id, role, module_id, can_view, can_edit)
select gen_random_uuid(), null, v.role, v.module, true, v.edit
from (values
  ('technologist','norms',true),('technologist','calc',true),('technologist','nc',true),('technologist','registry',true),
  ('technologist','bom',true),('technologist','assistant',true),('technologist','setup',true),('technologist','slots',true),
  ('technologist','forecast',false),('technologist','files',true),
  ('manager','crm',true),('manager','tkp',true),('manager','orders',true),('manager','suppliers',true),('manager','teo',true),
  ('manager','marketplace',true),('manager','escrow',true),('manager','labels',true),('manager','engraving',true),
  ('manager','files',true),('manager','builder',true),('manager','forecast',false),
  ('master','production',true),('master','setup',true),('master','slots',true),('master','mes',true),('master','tooling',true),
  ('master','forecast',false),('master','terminal',true),('master','lean',true),
  ('chief','production',true),('chief','planning',true),('chief','slots',true),('chief','forecast',true),('chief','setup',true),
  ('chief','issues',true),('chief','lean',true),
  ('economist','economics',true),('economist','teo',true),('economist','escrow',true),('economist','industry',true),('economist','calc',true),
  ('supply','procurement',true),('supply','suppliers',true),('supply','warehouse',true),('supply','marketplace',true),
  ('operator','terminal',true),('operator','mes',true),('operator','setup',false),
  ('qc','qc',true),('qc','quality',true),('qc','passport',true),('qc','files',false)
) as v(role, module, edit)
where not exists (
  select 1 from public.app_role_permissions p
  where p.tenant_id is null and p.role = v.role and p.module_id = v.module
);

-- ---------- Просмотр новых модулей для офисных ролей (view=true, edit=false) ----------
insert into public.app_role_permissions (id, tenant_id, role, module_id, can_view, can_edit)
select gen_random_uuid(), null, v.role, v.module, true, false
from (values
  ('director','norms'),('director','forecast'),('director','setup'),('director','lean'),('director','files'),('director','marketplace'),
  ('manager','norms'),('manager','setup'),('manager','slots'),('manager','lean'),
  ('master','norms'),('master','files'),
  ('chief','files'),('chief','norms'),
  ('economist','norms'),('economist','files'),
  ('supply','forecast'),('supply','files'),
  ('qc','files')
) as v(role, module)
where not exists (
  select 1 from public.app_role_permissions p
  where p.tenant_id is null and p.role = v.role and p.module_id = v.module
);

-- ---------- Сводка матрицы (для админа/аудита) ----------
create or replace function public.app_permissions_overview(p_token uuid)
returns table (module_id text, roles_total bigint, editors text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare urole text;
begin
  if not public.app_production_allowed(p_token) then raise exception 'Доступ запрещён'; end if;
  select s.urole into urole from public.app_session_user(p_token) s;
  if urole not in ('admin','owner') then raise exception 'Только администратор/владелец'; end if;
  return query
    select p.module_id, count(*),
      string_agg(p.role, ', ' order by p.role) filter (where p.can_edit)
    from public.app_role_permissions p
    where p.tenant_id is null
    group by p.module_id
    order by p.module_id;
end $$;

grant execute on function public.app_permissions_overview(uuid) to anon, authenticated;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Платформа','Права доступа и матрица ролей (P8)',
   'Права: admin/owner — полный доступ всегда; остальные роли — по матрице app_role_permissions (role × module × view/edit). Если строки нет — просмотр разрешён, редактирование запрещено (безопасный дефолт). Новые модули (нормирование, слоты, прогноз, наладка, lean, файлы, эскроу, маркетплейс, ТЭО, UI-справочники) добавлены в матрицу. Серверная проверка — helper app_guard(token, module, action) → возбуждает исключение при отсутствии права.',
   'права роли матрица app_can app_guard доступ P8 permissions')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Права доступа и матрица ролей (P8)');
