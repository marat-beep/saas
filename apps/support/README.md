# Модуль «Служба поддержки» (Support Desk)

Документ модуля (dev-заметка). Данные — Supabase, только через SECURITY DEFINER RPC.
Каталог: `id = support`, группа `platform`, аудитория `user`. См. `assets/js/catalog.js` и `docs/MODULE_STANDARD.md`.

## Назначение
Приём и обработка обращений пользователей и клиентов: тикеты, переписка и внутренние заметки,
SLA и эскалация, назначение исполнителя, CSAT, база знаний, вложения, аналитика.

## Файлы
- `index.html` — разметка (KPI, новый тикет, список, карточка, аналитика, база знаний).
- `support.js` — логика: guard → RPC → рендер → действия.
- Виджет `🎧` — `assets/js/support-widget.js` (быстрый доступ с любой страницы).

## Данные и RPC (миграции)
- `0100_support.sql` — таблицы `app_support_tickets`, `app_support_messages`, `app_support_sla`, `app_support_kb`
  и базовые RPC (create/list/get/reply/set_status/assign/escalate/csat/delete/kpi/kb/sla_due/escalate_scan).
- `0101_support_role.sql` — матрица прав роли `support` + включение модуля у тенанта A.
- `0102_support_analytics.sql` — `app_support_analytics` (срезы: статус/категория/модуль/scope).
- `0103_support_issues.sql` — связка с реестром «Проблемы и эскалация» (`app_issues`):
  - колонка `app_support_tickets.issue_id`;
  - `app_support_ticket_link_issue(tenant, ticket, login)` — создать/связать проблему;
  - `app_support_ticket_escalate` — при эскалации создаёт проблему (источник `support`, приоритет `critical`);
  - `app_support_escalate_scan` — сканер SLA создаёт проблемы для эскалированных тикетов;
  - `app_support_ticket_set_status` — синхронизирует статус проблемы (`resolved`/`closed`);
  - `app_support_ticket_get` — отдаёт `issue_id`, `issue_title`.

## Роли и доступ
- Заявитель (`client`, сотрудники) — видит только свои тикеты (`requester_login`).
- Агенты (`admin`, `owner`, `manager`, `director`, `support`) — тикеты своего тенанта; `admin` — все.
- Внутренние заметки (`is_internal=true`) видны только агентам.
- Матрица прав: `app_role_permissions` (роль `support`: support/issues/files/remarks).

## Ключевые правила
- Tenant-изоляция во всех выборках (`app_my_tenant`), проверки ролей — по `app_session_user`.
- SLA: `app_support_sla_due(priority)` (critical 30/240, high 120/1440, normal 240/2880, low 480/7200 мин).
- Вложения — через `app_files` (`entity_type = support_ticket`), файлы в Storage bucket `saas-files`.
- Значимые события — `app_notif_roles_t`; действия — `window.Auth.log(...)`.

## Проверка
- Баланс скобок JS, соответствие `id` HTML/JS, версии ассетов (`support.js?v=3`).
- После изменений — пересобрать `supabase/apply_all.sql`, применить идемпотентно, `app_smoke_test`.
