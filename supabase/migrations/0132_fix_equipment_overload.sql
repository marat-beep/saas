-- ============================================================
-- 3DMP Service · 0132_fix_equipment_overload.sql  (fix: конфликт перегрузки app_equipment_list/save)
-- Две разные функции с одинаковым именем делали вызов app_equipment_list(p_token)
-- неоднозначным (многие модули получали пустой список оборудования). Каталожный
-- вариант переименован в app_equipment_catalog_*. Идемпотентно. Зависит от 0001..0131.
-- ============================================================

do $$
begin
  if exists (
    select 1 from pg_proc
     where pronamespace = 'public'::regnamespace and proname = 'app_equipment_list'
       and pg_get_function_identity_arguments(oid) = 'p_token uuid, p_category text, p_q text'
  ) then
    alter function public.app_equipment_list(uuid, text, text) rename to app_equipment_catalog_list;
  end if;

  if exists (
    select 1 from pg_proc
     where pronamespace = 'public'::regnamespace and proname = 'app_equipment_save'
       and pg_get_function_identity_arguments(oid) = 'p_token uuid, p_id uuid, p_name text, p_brand text, p_category text, p_axes integer, p_accuracy text, p_price numeric, p_description text, p_active boolean'
  ) then
    alter function public.app_equipment_save(uuid, uuid, text, text, text, integer, text, numeric, text, boolean) rename to app_equipment_catalog_save;
  end if;
end $$;

grant execute on function public.app_equipment_catalog_list(uuid,text,text) to anon, authenticated;
grant execute on function public.app_equipment_catalog_save(uuid,uuid,text,text,text,integer,text,numeric,text,boolean) to anon, authenticated;
