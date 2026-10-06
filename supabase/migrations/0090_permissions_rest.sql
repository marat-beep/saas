-- ============================================================
-- 3DMP Service · 0090_permissions_rest.sql  (v68 — P8: права для остальных модулей)
-- Широкие права правки (view/edit) для бизнес-модулей, чтобы широкий rollout
-- app_guard не сломал рабочие потоки. admin/owner — всегда. Платформенные
-- модули (admin/platform/roles/api/scale) НЕ расширяются (только admin/owner).
-- Идемпотентно. Зависит от 0001..0089.
-- ============================================================

insert into public.app_role_permissions (id, tenant_id, role, module_id, can_view, can_edit)
select gen_random_uuid(), null, r.role, m.module, true, true
from (values ('manager'),('director'),('technologist'),('chief'),('master'),('operator'),('supply'),('qc'),('economist')) as r(role)
cross join (values
  ('orders'),('bom'),('registry'),('calc'),('crm'),('tkp'),('docs'),('templates'),
  ('procurement'),('supplier'),('production'),('mes'),('planning'),('warehouse'),
  ('maintenance'),('tooling'),('oee'),('terminal'),('issues'),('service'),('calendar'),
  ('nc'),('qc'),('passport'),('quality'),('economics'),('finance'),('hr'),('departments'),
  ('staff'),('dicts'),('partners'),('equipment'),('config'),('reverse'),('norms'),('slots'),
  ('setup'),('lean'),('files'),('labels'),('engraving'),('suppliers'),('teo'),('assistant'),
  ('industry'),('builder'),('whitelabel')
) as m(module)
where not exists (
  select 1 from public.app_role_permissions p
  where p.tenant_id is null and p.role = r.role and p.module_id = m.module
);

insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Платформа','Права бизнес-модулей (широкие)',
   'Для бизнес-модулей (заявки, документы, производство, качество, экономика, персонал и др.) право правки назначено офисным/цеховым ролям, чтобы серверная проверка app_guard не блокировала рабочие процессы. Платформенные модули (admin, platform, roles, api, scale) доступны только администратору/владельцу. Централизованно меняется в app_role_permissions.',
   'права бизнес-модули широкие роли app_guard P8 матрица')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Права бизнес-модулей (широкие)');
