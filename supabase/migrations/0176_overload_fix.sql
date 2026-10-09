-- ============================================================
-- 3DMP Service · 0176_overload_fix.sql  (финальная приёмка волн v2)
-- Устранение перегрузок: удаляем конфликтующие сигнатуры, оставшиеся от ранних применений.
-- Функции переименованы: app_doc_list → app_doc_flow_list, app_doc_set_status → app_doc_flow_set_status,
-- app_kb_list → app_kb_search (создаются в 0163/0164). Идемпотентно. Зависит от 0001..0175.
-- ============================================================

drop function if exists public.app_doc_list(uuid, text, text, text);
drop function if exists public.app_doc_set_status(uuid, uuid, text, text);
drop function if exists public.app_kb_list(uuid, text, text);
drop function if exists public.app_kb_search(uuid, text, text);
