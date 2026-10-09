# RUNBOOK — эксплуатация 3DMP Service

> Актуально на план **v3** (W29–W37). Краткие операционные процедуры.

## 1. Состояние и проверки
- Локальный аудит: `powershell -NoProfile -ExecutionPolicy Bypass -File tools\audit.ps1` (каталог/версии/shell/синтаксис; Node обязателен).
- Смоук БД: `powershell -NoProfile -ExecutionPolicy Bypass -File tools\db-smoke.ps1 -Token sbp_...`
  - ожидается: `app_smoke_test` 10/10, `app_smoke_test_ext` 14/14, волновые RPC 44/44, перегрузки 0.
- Регулярный прогон (W33): `powershell -ExecutionPolicy Bypass -File tools\run-checks.ps1 -Token sbp_...` по расписанию (Task Scheduler/CI `.github/workflows/checks.yml`); лог — `dist/checks/checks-<stamp>.log`, код 0/1.

## 2. Мониторинг доступности
- Прогон проверок: `select * from public.app_health_scan('<session_token>');` (пишет в `app_health_checks`, проверяет «свежесть данных» и пинги, открывает/закрывает алерты, уведомляет админов).
- Срез: `app_health_board('<token>')`, история: `app_health_list('<token>', 50)`, тренд: `app_health_trend('<token>', 14)`.
- Алерты: `app_health_alerts_list('<token>','open')`, закрытие — `app_health_alert_resolve('<token>', <id>);` (дедуп по `kind:name`, таблица `app_health_alerts`).
- Внешний uptime: `select * from public.app_health_ping('<api_key>');` (таблица `app_health_pings`).
- UI: «Диагностика» → блок «Мониторинг доступности» (KPI, тренд за 14 дней, открытые алерты).

## 3. Деплой релиза
1. Сборка: `tools\build-release.ps1` → `dist\saas-<дата>.zip`.
2. Залить в `sapfir.eu\saas` содержимое (index.html, apps/, assets/, eco/, web.config, manifest.webmanifest, sw.js).
3. Ctrl+F5. Проверить вход и 2–3 модуля.

## 4. Применение миграций
1. Взять `supabase/apply_all.sql` (или нужный `NNNN_*.sql`).
2. Supabase → SQL Editor → вставить → **Run** (либо Management API, тело **UTF-8**).
3. Прогнать `tools\db-smoke.ps1`; убедиться в отсутствии перегрузок.
4. Пересобрать `apply_all.sql` при добавлении миграции (маркеры `-- >>>>>>>>>> NNNN / <<<<<<<<<<`).

## 5. Инциденты (типовые)
| Симптом | Действие |
|---|---|
| «Ошибка RPC» в модуле | Проверить вход (сессия), права/`data-cap`, затем функцию в SQL (аргументы/имя), сверить с последней миграцией |
| Пусто в списке | Проверить RLS/тенант, `app_production_allowed`, наличие данных; смоук БД |
| Смоук упал | Смотреть сообщение SQL; частая причина — рассинхрон `apply_all.sql`/миграций или перегрузка функций |
| Каталог/версии битые | `tools\audit.ps1`: дубли id, невалидные `connects`, несоответствие `?v=N`/`CATALOG_V` |
| Регресс после обновления | Откат: восстановить предыдущий `dist` и (при необходимости) БД из бэкапа Supabase |

## 6. Откат/восстановление
- Статика: вернуть предыдущий `dist`-билд на FTP.
- БД: восстановление из резервной копии Supabase; миграции идемпотентны — повторный `apply_all.sql` безопасен.
- Токены: при компрометации — отозвать Management/API-ключи, перегенерировать.

## 7. Расширения (W35)
- Установка/включение: `app_ext_install` / `app_ext_toggle` (админ/владелец тенанта) или «Маркетплейс» → «Расширения». Проверить, что включение коннектора создало точку в `app_integrations`; откат — `app_ext_uninstall`.

## 8. Контакты/регламент
- Расписание проверок: ежедневно (CI 03:00 UTC) и/или Task Scheduler.
- Ответственные: администратор платформы.
- Канал алертов: уведомления администраторам платформы (`app_notif_roles_t`), далее — e-mail/Telegram через `app_integrations`.
