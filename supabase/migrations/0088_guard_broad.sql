-- ============================================================
-- 3DMP Service · 0088_guard_broad.sql  (v66 — P8 шаг 2, широкий rollout)
-- Внедрение серверной проверки app_guard в мутирующие RPC по списку функций.
-- Для каждой функции тело берётся из pg_get_functiondef и в начало блока
-- (после BEGIN) добавляется `perform public.app_guard(p_token,'<module>','edit')`.
-- Идемпотентно: функции, где уже есть app_guard/app_can, пропускаются.
-- Зависит от 0001..0087.
-- ============================================================

do $$
declare
  v record;
  r record;
  def text;
  n_fixed int := 0;
begin
  for v in
    select * from (values
      ('app_norms_op_save','norms'),
      ('app_norms_rate_save','norms'),
      ('app_norms_rate_delete','norms'),
      ('app_norms_k_save','norms'),
      ('app_norms_serial_save','norms'),
      ('app_analog_save','norms'),
      ('app_slot_save','slots'),
      ('app_slot_book','slots'),
      ('app_sla_save','slots'),
      ('app_setup_save','setup'),
      ('app_setup_set_status','setup'),
      ('app_lean_save','lean'),
      ('app_lean_set_status','lean'),
      ('app_partner_save','partners'),
      ('app_partner_deal_save','partners'),
      ('app_equipment_save','equipment'),
      ('app_staff_save','staff'),
      ('app_staff_event_add','staff'),
      ('app_config_option_save','config'),
      ('app_reverse_save','reverse'),
      ('app_reverse_set_status','reverse'),
      ('app_dict_save','dicts'),
      ('app_dict_item_save','dicts'),
      ('app_teo_save','teo'),
      ('app_teo_line_save','teo'),
      ('app_engraving_save','engraving'),
      ('app_package_save','labels'),
      ('app_label_save','labels'),
      ('app_suppliers_save','suppliers'),
      ('app_file_register','files'),
      ('app_file_delete','files'),
      ('app_entity_save','builder'),
      ('app_entity_field_save','builder'),
      ('app_entity_record_save','builder'),
      ('app_department_save','departments'),
      ('app_whitelabel_save','whitelabel'),
      ('app_market_listing_set_status','marketplace'),
      ('app_market_request_set_status','marketplace'),
      ('app_escrow_save','escrow'),
      ('app_escrow_set_status','escrow')
    ) as t(fname, mod)
  loop
    for r in
      select pg_get_functiondef(p.oid) as d
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname='public' and p.proname = v.fname
         and p.prolang = (select oid from pg_language where lanname='plpgsql')
    loop
      def := r.d;
      if position('app_guard(' in def) = 0 and position('app_can(' in def) = 0 then
        def := regexp_replace(
          def,
          '(?i)' || chr(10) || 'begin',
          chr(10) || 'begin' || chr(10) || '  perform public.app_guard(p_token, ''' || v.mod || ''', ''edit'');'
        );
        execute def;
        n_fixed := n_fixed + 1;
      end if;
    end loop;
  end loop;
  raise notice 'app_guard внедрён в % функций', n_fixed;
end $$;

-- ---------- База знаний ----------
insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Платформа','Серверная проверка прав — широкий rollout (P8 шаг 2)',
   'Все ключевые мутирующие RPC проверяют права на сервере через app_guard(token, module, edit) по матрице app_role_permissions. Покрыты модули: нормирование, слоты, наладка, lean, партнёры, оборудование, кадры, конфигуратор, реверс, справочники, ТЭО, гравирование, маркировка, поставщики, файлы, конструктор, подразделения, брендирование, маркетплейс, эскроу. admin/owner — всегда; остальные — по назначенным правам.',
   'права app_guard серверная проверка rollout матрица P8 безопасность')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Серверная проверка прав — широкий rollout (P8 шаг 2)');
