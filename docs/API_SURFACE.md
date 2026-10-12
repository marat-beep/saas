# API-поверхность RPC (U4)

_Автогенерация `tools/api-surface.ps1`. Всего функций в миграциях: **1082**; вызываются из UI: **963**; только backend/API: **119**._

«Только backend/API» — функции, не встречающиеся в `apps/` и `assets/js/`. Это внутренние хелперы, триггерные/служебные функции и кандидаты внешнего API (вызов по токену). Их не обязательно выводить в UI; их назначение — API/внутренняя логика.

## Backend/API-функции

| Функция | Примечание |
|---|---|
| `api_tenant_of` |  |
| `api_touch` |  |
| `app_ai_job_update` |  |
| `app_announcements_scan` |  |
| `app_api_log_write` | внешний API/вебхуки |
| `app_aps_build` |  |
| `app_attach_list` |  |
| `app_audit_write` |  |
| `app_base32_decode` |  |
| `app_base32_encode` |  |
| `app_billing_mark_paid` |  |
| `app_briefing_delete` |  |
| `app_calc_get` | движок расчёта |
| `app_can_view` | хелпер авторизации/прав |
| `app_capacity_list` |  |
| `app_cert_save` |  |
| `app_claim_delete` |  |
| `app_config_option_delete` |  |
| `app_cost_fact` |  |
| `app_crm_contact_send` |  |
| `app_daily_job_set_status` |  |
| `app_dealer_request_set_status` |  |
| `app_dept_ok` | хелпер авторизации/прав |
| `app_dept_scope_apply` |  |
| `app_dict_delete` |  |
| `app_doc_delete` |  |
| `app_doc_folder_list` |  |
| `app_doc_folder_save` |  |
| `app_doc_formula_eval` |  |
| `app_doc_print_template_save` |  |
| `app_doc_resolution_set_sla` |  |
| `app_doc_route_act` |  |
| `app_doc_route_start` |  |
| `app_employee_link_user` |  |
| `app_ext_installs_list` |  |
| `app_file_url` |  |
| `app_forecast_slots` |  |
| `app_guard` | хелпер авторизации/прав |
| `app_health_ping` | мониторинг/эксплуатация |
| `app_help_stats` |  |
| `app_hr_kpi` |  |
| `app_iiot_readings_recent` |  |
| `app_industry_benchmark_save` |  |
| `app_is_owner` | хелпер авторизации/прав |
| `app_is_platform_admin` | хелпер авторизации/прав |
| `app_kb_articles` |  |
| `app_kb_sections` |  |
| `app_link_add` |  |
| `app_link_delete` |  |
| `app_links_list` |  |
| `app_lot_genealogy_by_passport` |  |
| `app_lot_trace_add` |  |
| `app_mes_alerts` |  |
| `app_mes_create` |  |
| `app_mes_delete` |  |
| `app_mes_kpi` |  |
| `app_mes_set_status` |  |
| `app_module_enabled` |  |
| `app_my_permissions` | хелпер авторизации/прав |
| `app_naryad_op_tools` |  |
| `app_norms_list` |  |
| `app_notif_send` |  |
| `app_offline_list` |  |
| `app_order_flow_list` |  |
| `app_order_kpi_ext` |  |
| `app_order_routes_cost` |  |
| `app_order_update` |  |
| `app_orders_quota_trg` |  |
| `app_org_role_coverage` |  |
| `app_partner_deal_commission` |  |
| `app_partner_referral` |  |
| `app_payment_link_create` |  |
| `app_payment_links_list` |  |
| `app_payment_settle` |  |
| `app_permissions_overview` |  |
| `app_permit_to_task` |  |
| `app_plan_gantt` |  |
| `app_ppe_delete` |  |
| `app_ppe_issue` |  |
| `app_process_get` |  |
| `app_production_allowed` | хелпер авторизации/прав |
| `app_purchase_request_save` |  |
| `app_purchase_request_set_status` |  |
| `app_qc_measures_list` |  |
| `app_quota_limit` |  |
| `app_quota_used` |  |
| `app_ref_material_save` |  |
| `app_report_def_get` |  |
| `app_review_kpi` |  |
| `app_review_save` |  |
| `app_role_actions_get` |  |
| `app_role_is_staff` |  |
| `app_role_matrix` |  |
| `app_role_perm_set` |  |
| `app_schema_delete` |  |
| `app_schema_field_delete` |  |
| `app_schema_field_save` |  |
| `app_schema_save` |  |
| `app_schemas_list` |  |
| `app_service_act_to_edo` |  |
| `app_service_contract_bill` |  |
| `app_service_my_visits` |  |
| `app_service_route_save` |  |
| `app_service_sla_minutes` |  |
| `app_session_touch` | хелпер авторизации/прав |
| `app_setting_get` |  |
| `app_setup_steps_list` |  |
| `app_staff_roles` |  |
| `app_support_ticket_delete` |  |
| `app_task_board` |  |
| `app_task_delete` |  |
| `app_teo_total` |  |
| `app_test_attempts_list` |  |
| `app_totp_code` |  |
| `app_totp_verify` |  |
| `app_vibro_limit_save` |  |
| `current_tenant_ids` |  |
| `handle_new_user` |  |
| `is_admin` |  |

