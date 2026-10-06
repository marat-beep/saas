-- ============================================================
-- 3DMP Service · 0091_guard_rest.sql  (v69 — P8 шаг 2: остаточный rollout)
-- Внедрение app_guard в оставшиеся мутирующие RPC (автоинъекция через
-- pg_get_functiondef; после BEGIN). Идемпотентно. Зависит от 0001..0090.
-- ============================================================

do $$
declare
  v record; r record; def text; n_fixed int := 0;
begin
  for v in
    select * from (values
      ('app_bom_save','bom'),
      ('app_material_save','registry'),
      ('app_operation_save','registry'),
      ('app_process_create','registry'),
      ('app_route_set_status','registry'),
      ('app_ref_material_save','registry'),
      ('app_customer_save','crm'),
      ('app_deal_save','crm'),
      ('app_tkp_save','tkp'),
      ('app_tkp_set_status','tkp'),
      ('app_doc_create','docs'),
      ('app_doc_update','docs'),
      ('app_doc_set_status','docs'),
      ('app_doc_template_save','templates'),
      ('app_tender_create','procurement'),
      ('app_tender_set_status','procurement'),
      ('app_supplier_profile_save','supplier'),
      ('app_suppliers_set_status','suppliers'),
      ('app_naryad_create','production'),
      ('app_naryad_update','production'),
      ('app_naryad_close','production'),
      ('app_mes_create','mes'),
      ('app_mes_delete','mes'),
      ('app_mes_set_status','mes'),
      ('app_mes_ops_set_status','mes'),
      ('app_shift_add','planning'),
      ('app_shift_delete','planning'),
      ('app_stock_move','warehouse'),
      ('app_mnt_plan_save','maintenance'),
      ('app_mnt_register','maintenance'),
      ('app_tool_save','tooling'),
      ('app_tool_delete','tooling'),
      ('app_tool_life_save','tooling'),
      ('app_oee_save','oee'),
      ('app_issue_save','issues'),
      ('app_issue_set_status','issues'),
      ('app_escalation_scan','issues'),
      ('app_service_save','service'),
      ('app_service_set_status','service'),
      ('app_calendar_save','calendar'),
      ('app_calendar_delete','calendar'),
      ('app_nc_save','nc'),
      ('app_nc_set_status','nc'),
      ('app_qc_create','qc'),
      ('app_qc_set_status','qc'),
      ('app_defect_add','qc'),
      ('app_passport_create','passport'),
      ('app_trace_add','quality'),
      ('app_invoice_create','finance'),
      ('app_invoice_set_status','finance'),
      ('app_payment_add','finance'),
      ('app_employee_save','hr'),
      ('app_training_add','staff'),
      ('app_training_set_status','staff'),
      ('app_kb_add','assistant'),
      ('app_industry_benchmark_save','industry'),
      ('app_api_key_create','api'),
      ('app_webhook_add','api'),
      ('app_webhook_delete','api'),
      ('app_platform_tenant_create','platform'),
      ('app_platform_tenant_update','platform'),
      ('app_tenant_user_create','admin'),
      ('app_tenant_user_update','admin'),
      ('app_tenant_user_reset','admin'),
      ('app_role_perm_set','roles'),
      ('app_calc_save','calc'),
      ('app_calc_delete','calc'),
      ('app_attachment_add','files'),
      ('app_attachment_delete','files'),
      ('app_analog_delete','norms'),
      ('app_norms_k_delete','norms'),
      ('app_config_option_delete','config'),
      ('app_department_delete','departments'),
      ('app_dict_delete','dicts'),
      ('app_dict_item_delete','dicts'),
      ('app_entity_field_delete','builder'),
      ('app_entity_record_delete','builder'),
      ('app_equipment_delete','equipment'),
      ('app_label_delete','labels'),
      ('app_package_delete','labels'),
      ('app_lean_delete','lean'),
      ('app_partner_set_status','partners'),
      ('app_partner_deal_set_status','partners'),
      ('app_engraving_set_status','engraving'),
      ('app_setup_delete','setup'),
      ('app_slot_delete','slots'),
      ('app_teo_set_status','teo'),
      ('app_teo_line_delete','teo')
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
  raise notice 'app_guard внедрён ещё в % функций', n_fixed;
end $$;

insert into public.app_knowledge (tenant_id, category, question, answer, tags)
select 'aaaaaaaa-0000-0000-0000-000000000001', v.category, v.question, v.answer, v.tags
from (values
  ('Платформа','Серверная проверка прав — полный охват RPC (P8 шаг 2)',
   'Серверная проверка app_guard охватывает практически все мутирующие RPC сервиса: заявки, КТПП, производство, качество, экономику, финансы, персонал, документы, платформу и прикладные модули. Права — из матрицы app_role_permissions. Платформенные операции (admin/platform/roles/api) доступны только администратору/владельцу.',
   'права app_guard полный охват RPC матрица P8 безопасность')
) as v(category,question,answer,tags)
where not exists (select 1 from public.app_knowledge where tenant_id='aaaaaaaa-0000-0000-0000-000000000001' and question='Серверная проверка прав — полный охват RPC (P8 шаг 2)');
