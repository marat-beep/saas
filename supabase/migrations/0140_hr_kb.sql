-- ============================================================
-- 3DMP Service · 0140_hr_kb.sql  (M5 — Кадры: БЗ и связи)
-- Документирование отчёта/связей модуля кадров. Идемпотентно. Зависит от 0001..0139.
-- ============================================================

insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Кадры','Персонал: сотрудники, смены, обучение, отчёт',
   'Сотрудники (app_employees_list) связаны с пользователем-логином и ролью; смены/табель (app_shift_add, app_shifts_list), обучение (app_training_add, app_training_set_status). KPI — app_hr_kpi (сотрудники, смены/часы за месяц, обучение план/пройдено). Отчёт по персоналу — кнопка «📄 Отчёт PDF» (список сотрудников и сводка). Связи: реестр сотрудников (apps/staff), подразделения (apps/departments), роли (apps/roles).',
   'кадры персонал сотрудники смены табель обучение отчёт роли подразделения')
) as v(category,question,answer,tags)
where not exists (
  select 1 from public.app_knowledge
   where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001' and question = 'Персонал: сотрудники, смены, обучение, отчёт'
);
