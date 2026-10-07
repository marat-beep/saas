-- ============================================================
-- 3DMP Service · 0143_warehouse_kb.sql  (M6 — Склад: БЗ и связи)
-- Документирование отчёта/связей модуля склада. Идемпотентно. Зависит от 0001..0142.
-- ============================================================

insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Склад','Остатки, движения, WMS и отчёт',
   'ТМЦ: остатки материалов (app_material_list), приход/расход (app_material_move), история движений, контроль минимума (app_stock_low) с автопотребностью на закупку. WMS: адреса (app_wh_address_list), партии (app_material_lot_list), остатки по адресам (app_wh_stock_list), размещение/перемещение/списание (app_wh_place/move/stock_out), KPI (app_wh_kpi). Отчёт по складу — кнопка «📄 Отчёт PDF» (остатки, минимум, стоимость, нехватка). Связи: Закупки, Сервис (запчасти под заявку/резерв), Производство, Экономика.',
   'склад остатки движения WMS адреса партии нехватка отчёт закупки сервис')
) as v(category,question,answer,tags)
where not exists (
  select 1 from public.app_knowledge
   where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001' and question = 'Остатки, движения, WMS и отчёт'
);
