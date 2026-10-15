# API-поверхность RPC (U4/PROP-05)

_Автогенерация `tools/api-surface.ps1`. Всего функций в миграциях: **1134**; вызываются из UI (apps + assets/js): **1010**; только backend/API: **124**._

«Только backend/API» — функции, не встречающиеся в `apps/` и `assets/js/` (сопоставление по границам слова, чтобы не путать похожие имена). Это внутренние хелперы/RLS, триггеры, служебные операции и кандидаты внешнего API (вызов по токену). Их не обязательно выводить в UI.

## Сводка по категориям backend/API

| Категория | Кол-во |
|---|---|
| batch | 2 |
| аналитика | 25 |
| внешний API | 1 |
| мониторинг | 1 |
| офлайн | 1 |
| права | 15 |
| прочее | 39 |
| расчёт | 1 |
| служебная | 33 |
| триггер | 1 |
| утилита | 5 |

## Backend/API-функции

| Функция | Категория | Примечание |
|---|---|---|
| `app_announcements_scan` | batch | пакетная/служебная операция |
| `app_aps_build` | batch | пакетная/служебная операция |
| `app_attach_list` | аналитика | набор/отчёт (backend/аналитика) |
| `app_capacity_list` | аналитика | набор/отчёт (backend/аналитика) |
| `app_doc_folder_list` | аналитика | набор/отчёт (backend/аналитика) |
| `app_ext_installs_list` | аналитика | набор/отчёт (backend/аналитика) |
| `app_help_stats` | аналитика | набор/отчёт (backend/аналитика) |
| `app_hr_kpi` | аналитика | набор/отчёт (backend/аналитика) |
| `app_links_list` | аналитика | набор/отчёт (backend/аналитика) |
| `app_mes_kpi` | аналитика | набор/отчёт (backend/аналитика) |
| `app_norms_list` | аналитика | набор/отчёт (backend/аналитика) |
| `app_order_audit_list` | аналитика | набор/отчёт (backend/аналитика) |
| `app_order_flow_list` | аналитика | набор/отчёт (backend/аналитика) |
| `app_org_role_coverage` | аналитика | набор/отчёт (backend/аналитика) |
| `app_payment_links_list` | аналитика | набор/отчёт (backend/аналитика) |
| `app_permissions_overview` | аналитика | набор/отчёт (backend/аналитика) |
| `app_plan_gantt` | аналитика | набор/отчёт (backend/аналитика) |
| `app_process_get` | аналитика | набор/отчёт (backend/аналитика) |
| `app_qc_measures_list` | аналитика | набор/отчёт (backend/аналитика) |
| `app_report_def_get` | аналитика | набор/отчёт (backend/аналитика) |
| `app_review_kpi` | аналитика | набор/отчёт (backend/аналитика) |
| `app_role_matrix` | аналитика | набор/отчёт (backend/аналитика) |
| `app_schemas_list` | аналитика | набор/отчёт (backend/аналитика) |
| `app_setting_get` | аналитика | набор/отчёт (backend/аналитика) |
| `app_setup_steps_list` | аналитика | набор/отчёт (backend/аналитика) |
| `app_task_board` | аналитика | набор/отчёт (backend/аналитика) |
| `app_test_attempts_list` | аналитика | набор/отчёт (backend/аналитика) |
| `app_api_log_write` | внешний API | внешний API/вебхуки |
| `app_health_ping` | мониторинг | мониторинг/эксплуатация |
| `app_offline_list` | офлайн | офлайн/PWA |
| `app_can_edit` | права | хелпер авторизации/прав (RLS) |
| `app_can_view` | права | хелпер авторизации/прав (RLS) |
| `app_dept_ok` | права | хелпер авторизации/прав (RLS) |
| `app_guard` | права | хелпер авторизации/прав (RLS) |
| `app_is_owner` | права | хелпер авторизации/прав (RLS) |
| `app_is_platform_admin` | права | хелпер авторизации/прав (RLS) |
| `app_module_enabled` | права | хелпер авторизации/прав (RLS) |
| `app_my_permissions` | права | хелпер авторизации/прав (RLS) |
| `app_production_allowed` | права | хелпер авторизации/прав (RLS) |
| `app_role_actions_get` | права | хелпер авторизации/прав (RLS) |
| `app_role_is_staff` | права | хелпер авторизации/прав (RLS) |
| `app_session_touch` | права | хелпер авторизации/прав (RLS) |
| `current_tenant_ids` | права | хелпер авторизации/прав (RLS) |
| `handle_new_user` | права | хелпер авторизации/прав (RLS) |
| `is_admin` | права | хелпер авторизации/прав (RLS) |
| `api_tenant_of` | прочее |  |
| `api_touch` | прочее |  |
| `app_audit_write` | прочее |  |
| `app_billing_mark_paid` | прочее |  |
| `app_changeover_minutes` | прочее |  |
| `app_cost_fact` | прочее |  |
| `app_crm_contact_send` | прочее |  |
| `app_dept_scope_apply` | прочее |  |
| `app_doc_resolution_set_sla` | прочее |  |
| `app_employee_link_user` | прочее |  |
| `app_forecast_slots` | прочее |  |
| `app_iiot_readings_recent` | прочее |  |
| `app_kb_articles` | прочее |  |
| `app_kb_sections` | прочее |  |
| `app_lot_genealogy_by_passport` | прочее |  |
| `app_mes_alerts` | прочее |  |
| `app_mes_create` | прочее |  |
| `app_naryad_op_tools` | прочее |  |
| `app_notif_roles` | прочее |  |
| `app_notif_send` | прочее |  |
| `app_order_kpi_ext` | прочее |  |
| `app_order_routes_cost` | прочее |  |
| `app_orders_audit` | прочее |  |
| `app_partner_deal_commission` | прочее |  |
| `app_partner_referral` | прочее |  |
| `app_payment_link_create` | прочее |  |
| `app_payment_settle` | прочее |  |
| `app_permit_to_task` | прочее |  |
| `app_quota_limit` | прочее |  |
| `app_quota_used` | прочее |  |
| `app_role_perm_set` | прочее |  |
| `app_service_act_to_edo` | прочее |  |
| `app_service_contract_bill` | прочее |  |
| `app_service_my_visits` | прочее |  |
| `app_service_sla_minutes` | прочее |  |
| `app_staff_roles` | прочее |  |
| `app_tenant_modules` | прочее |  |
| `app_teo_total` | прочее |  |
| `app_tkp_link_deal` | прочее |  |
| `app_calc_get` | расчёт | движок расчёта |
| `app_ai_job_update` | служебная | служебная (вызывается из других RPC/триггеров) |
| `app_briefing_delete` | служебная | служебная (вызывается из других RPC/триггеров) |
| `app_cert_save` | служебная | служебная (вызывается из других RPC/триггеров) |
| `app_claim_delete` | служебная | служебная (вызывается из других RPC/триггеров) |
| `app_config_option_delete` | служебная | служебная (вызывается из других RPC/триггеров) |
| `app_daily_job_set_status` | служебная | служебная (вызывается из других RPC/триггеров) |
| `app_dealer_request_set_status` | служебная | служебная (вызывается из других RPC/триггеров) |
| `app_dict_delete` | служебная | служебная (вызывается из других RPC/триггеров) |
| `app_doc_delete` | служебная | служебная (вызывается из других RPC/триггеров) |
| `app_doc_folder_save` | служебная | служебная (вызывается из других RPC/триггеров) |
| `app_doc_print_template_save` | служебная | служебная (вызывается из других RPC/триггеров) |
| `app_doc_route_act` | служебная | служебная (вызывается из других RPC/триггеров) |
| `app_doc_route_start` | служебная | служебная (вызывается из других RPC/триггеров) |
| `app_industry_benchmark_save` | служебная | служебная (вызывается из других RPC/триггеров) |
| `app_link_add` | служебная | служебная (вызывается из других RPC/триггеров) |
| `app_link_delete` | служебная | служебная (вызывается из других RPC/триггеров) |
| `app_lot_trace_add` | служебная | служебная (вызывается из других RPC/триггеров) |
| `app_mes_delete` | служебная | служебная (вызывается из других RPC/триггеров) |
| `app_mes_set_status` | служебная | служебная (вызывается из других RPC/триггеров) |
| `app_order_update` | служебная | служебная (вызывается из других RPC/триггеров) |
| `app_ppe_delete` | служебная | служебная (вызывается из других RPC/триггеров) |
| `app_ppe_issue` | служебная | служебная (вызывается из других RPC/триггеров) |
| `app_purchase_request_set_status` | служебная | служебная (вызывается из других RPC/триггеров) |
| `app_ref_material_save` | служебная | служебная (вызывается из других RPC/триггеров) |
| `app_review_save` | служебная | служебная (вызывается из других RPC/триггеров) |
| `app_schema_delete` | служебная | служебная (вызывается из других RPC/триггеров) |
| `app_schema_field_delete` | служебная | служебная (вызывается из других RPC/триггеров) |
| `app_schema_field_save` | служебная | служебная (вызывается из других RPC/триггеров) |
| `app_schema_save` | служебная | служебная (вызывается из других RPC/триггеров) |
| `app_service_route_save` | служебная | служебная (вызывается из других RPC/триггеров) |
| `app_support_ticket_delete` | служебная | служебная (вызывается из других RPC/триггеров) |
| `app_task_delete` | служебная | служебная (вызывается из других RPC/триггеров) |
| `app_vibro_limit_save` | служебная | служебная (вызывается из других RPC/триггеров) |
| `app_orders_quota_trg` | триггер | триггерная функция |
| `app_base32_decode` | утилита | утилита (2FA/кодирование) |
| `app_base32_encode` | утилита | утилита (2FA/кодирование) |
| `app_file_url` | утилита | утилита |
| `app_totp_code` | утилита | утилита (2FA/кодирование) |
| `app_totp_verify` | утилита | утилита (2FA/кодирование) |

---

**Классификация (PROP-05):** функции внешнего API и часть служебных сохраняют `grant execute` для `anon/authenticated` (нужны внешним вызовам и реализациям, работающим от имени пользователя). Чисто внутренние хелперы/RLS/триггеры недоступны пользователю напрямую (не вызываются из клиента) и защищены проверками прав. Харденинг грантов — отдельная задача (PROP-03).
