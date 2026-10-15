-- ============================================================
-- 3DMP Service · 0272_drop_inbox_dupes.sql
-- Удаляет дубли «инбокса», созданные ошибочно в 0262 (контакт-центр уже есть в 0164).
-- Только DROP IF EXISTS — идемпотентно и безопасно.
-- ============================================================

drop function if exists public.app_inbox_list(uuid);
drop function if exists public.app_inbox_set_status(uuid, uuid, text);
drop function if exists public.app_inbox_add(uuid, text, text, text, text, text, int, text);
