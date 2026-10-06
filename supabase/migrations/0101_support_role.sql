-- ============================================================
-- 3DMP Service · 0101_support_role.sql  (v81 — права роли 'support')
-- Матрица прав для службы поддержки + включение модуля у тенанта A.
-- Идемпотентно. Зависит от 0001..0100.
-- ============================================================

insert into public.app_role_permissions (id, tenant_id, role, module_id, can_view, can_edit)
select gen_random_uuid(), null, 'support', v.module, true, v.edit
from (values
  ('support', true), ('issues', true), ('files', true), ('docs', false), ('bugbox', false), ('remarks', true), ('dicts', false)
) as v(module, edit)
where not exists (select 1 from public.app_role_permissions p where p.tenant_id is null and p.role='support' and p.module_id=v.module);

insert into public.app_tenant_modules (tenant_id, module, enabled)
select 'aaaaaaaa-0000-0000-0000-000000000001', 'support', true
where not exists (select 1 from public.app_tenant_modules where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and module='support');

insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Поддержка','Роль «Служба поддержки»',
   'Роль support: агент поддержки. Видит тикеты своего тенанта, отвечает, назначает исполнителей, меняет статусы, публикует базу знаний. В auth.js добавлена в STAFF и ROLE_LABELS; права — в матрице app_role_permissions (support/issues/files/remarks).',
   'роль support служба поддержки права матрица агент')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Роль «Служба поддержки»');
