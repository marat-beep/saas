-- ============================================================
-- 3DMP Service · 0089_permissions_more.sql  (v67 — P8: матрица для новых модулей)
-- Назначение прав (view/edit) для модулей, добавленных после 0079: dicts, staff,
-- partners, equipment, config, reverse, departments, files. Идемпотентно.
-- admin/owner — уже всегда полный доступ. Зависит от 0001..0088.
-- ============================================================

insert into public.app_role_permissions (id, tenant_id, role, module_id, can_view, can_edit)
select gen_random_uuid(), null, v.role, v.module, true, v.edit
from (values
  ('manager','dicts',true),('technologist','dicts',true),('director','dicts',true),
  ('manager','staff',true),('director','staff',true),('chief','staff',true),
  ('manager','partners',true),('director','partners',true),
  ('manager','equipment',true),('technologist','equipment',true),
  ('technologist','config',true),('manager','config',true),
  ('manager','reverse',true),('technologist','reverse',true),('master','reverse',true),
  ('manager','departments',true),('chief','departments',true),('director','departments',true),
  ('manager','files',true),('technologist','files',true),
  ('economist','config',false),('economist','reverse',false),('chief','reverse',false),
  ('operator','reverse',false),('qc','dicts',false)
) as v(role, module, edit)
where not exists (
  select 1 from public.app_role_permissions p
  where p.tenant_id is null and p.role = v.role and p.module_id = v.module
);

insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Платформа','Права на новые модули',
   'Для модулей dicts (справочники), staff (кадры), partners, equipment, config, reverse, departments, files назначены права правки по ролям (менеджер, технолог, директор, начальник цеха, мастер). Администратор и владелец имеют полный доступ всегда. Матрица — app_role_permissions; проверка — app_can/app_guard.',
   'права матрица новые модули dicts staff partners equipment config reverse departments P8')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Права на новые модули');
