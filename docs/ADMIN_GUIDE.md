# ADMIN_GUIDE — руководство администратора 3DMP Service

> Актуально на план **v3** (W29–W37). Секреты (service_role/sb_secret/Management-токен) — **не** в клиенте и **не** в git.

## 1. Роли и доступ
- **admin** (платформенный) — все организации, тарифы/биллинг, админка, аудит.
- **owner** — организация: пользователи, роли, модули, бренд, подписка.
- **manager** и др. — по матрице ролей + `data-cap`.
- Гибкие права: модуль «Права и согласования» (`apps/access`) — наборы прав на роль/пользователя/подразделение, делегирование; `app_can` учитывает это.
- Гейтинг по подразделению: `apps/org` → переключатель (R4).

## 2. Пользователи и организации
- Организации (SaaS) — `apps/platform` (тенанты, план, статус).
- Админ-панель клиента — `apps/org` (пользователи, роли, модули, тариф, бренд).
- Сброс пароля: `update public.app_users set password_hash = extensions.crypt('Новый', extensions.gen_salt('bf')) where login='…';` (SQL Editor).

## 3. Тарифы, модули, подписки
- Тарифы: `app_plans` (лимиты — jsonb), подписки — `app_subscriptions`, счета — `app_platform_invoices`. UI — «Биллинг и подписки» (`apps/billing`).
- Модули организации включаются флагами (features); доступность — `roles` в каталоге.

## 4. Данные и НСИ
- НСИ/MDM — `apps/mdm`: единый справочник, внешние коды (1С/PLM), дубли/слияние, импорт.
- Миграции БД — `supabase/migrations/NNNN_*.sql`; применять через Management API (UTF-8) или SQL Editor, вставляя `apply_all.sql`. **Идемпотентно.**
- После миграций: пересобрать `apply_all.sql`, отметить в docs, поднять `?v=N`/`CATALOG_V`.

## 5. Интеграции и API
- «Интеграции» (`apps/integrations`) — каналы e-mail/Telegram/SMS/ЭДО/webhook; очередь `app_integrations`, воркер `backend-example`.
- «API и интеграции» (`apps/api`) — API-ключи, вебхуки, лог вызовов, подписи, проверка контрагентов.

## 6. Эксплуатация и мониторинг (W33)
- Проверки БД: `app_smoke_test` (10), `app_smoke_test_ext` (14); волновые RPC и перегрузки — `tools/db-smoke.ps1`.
- Регулярный прогон: `tools/run-checks.ps1` (audit+db-smoke, лог `dist/checks/`, exit-код) по расписанию — Task Scheduler или CI `.github/workflows/checks.yml`.
- Доступность: `app_health_scan` (пишет `app_health_checks`, проверяет «свежесть данных» и пинги, открывает алерты `app_health_alerts` с дедупом и уведомлением админов), срез — `app_health_board`, тренд — `app_health_trend`. Внешний uptime — `app_health_ping(API-ключ)`. UI — «Диагностика» (блок «Мониторинг доступности»).

## 6a. Расширения (W35)
- «Маркетплейс» → «Расширения»: каталог манифестов (`app_extensions`), установка по тенанту (`app_extension_installs`). Установка/включение/удаление — администратор/владелец организации; включение коннектора подтягивает точку интеграции в `app_integrations`. Правка манифеста — администратор платформы. Все действия — в журнале.

## 7. Деплой
- Сборка: `powershell -NoProfile -ExecutionPolicy Bypass -File tools\build-release.ps1` → `dist\saas-<дата>.zip`.
- Заливается в `sapfir.eu\saas` (строчными): `index.html`, `apps/`, `assets/`, `eco/`, `web.config`, `manifest.webmanifest`, `sw.js`.
- **Не льётся:** `supabase/`, `docs/`, `tools/`, `dist/`, `.git`, `README.md`, `AGENTS.md`.
- После заливки — **Ctrl+F5** (кэш статики отключён `web.config`).

## 8. Безопасность и резервы
- RLS включён на таблицах; доступ — через RPC с проверкой сессии/`app_production_allowed`.
- Бэкапы БД — средствами Supabase; секреты — в vault/CI, ротация токенов.
- Аудит действий — `app_audit_ext` (`apps/access` → «Аудит»).
