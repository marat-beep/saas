-- ============================================================
-- 3DMP Service · 0148_oee_kb.sql  (M7 — OEE: БЗ и связи)
-- Документирование отчёта/связей модуля OEE. Идемпотентно. Зависит от 0001..0147.
-- ============================================================

insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('OEE','Эффективность оборудования: смены, простои, отчёт',
   'OEE-монитор (app_oee_log_list): смена (план/работа/простой, годные/всего), автоматический расчёт доступности, качества и OEE; причины простоев; рейтинг оборудования (app_oee_by_equipment); KPI (app_oee_kpi: средний OEE/доступность/качество/простои). Отчёт OEE — кнопка «📄 Отчёт PDF». Связи: MES, ТОиР, инструмент, Производство, IIoT (телеметрия → наработка), BI.',
   'OEE доступность качество простои смены отчёт оборудование')
) as v(category,question,answer,tags)
where not exists (
  select 1 from public.app_knowledge
   where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001' and question = 'Эффективность оборудования: смены, простои, отчёт'
);
