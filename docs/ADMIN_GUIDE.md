# ADMIN_GUIDE — руководство администратора 3DMP Service

> Черновик. Полное наполнение — волна **W37**. Секреты (service_role/sb_secret/Management-токен) — **не** в клиенте и **не** в git.

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

## 6. Эксплуатация и мониторинг
- Проверки БД: `app_smoke_test` (10), `app_smoke_test_ext` (14); волновые RPC и перегрузки — `tools/db-smoke.ps1`.
- Доступность: `app_health_scan` → `app_health_checks`; срез — `app_health_board`. UI — «Диагностика»/«Биллинг».
- Регулярный прогон и алерты — волна **W33** (`tools/run-checks.ps1`, Task Scheduler/CI, `docs/RUNBOOK.md`).

## 7. Деплой
- Сборка: `powershell -NoProfile -ExecutionPolicy Bypass -File tools\build-release.ps1` → `dist\saas-<дата>.zip`.
- Заливается в `sapfir.eu\saas` (строчными): `index.html`, `apps/`, `assets/`, `eco/`, `web.config`, `manifest.webmanifest`, `sw.js`.
- **Не льётся:** `supabase/`, `docs/`, `tools/`, `dist/`, `.git`, `README.md`, `AGENTS.md`.
- После заливки — **Ctrl+F5** (кэш статики отключён `web.config`).

## 8. Безопасность и резервы
- RLS включён на таблицах; доступ — через RPC с проверкой сессии/`app_production_allowed`.
- Бэкапы БД — средствами Supabase; секреты — в vault/CI, ротация токенов.
- Аудит действий — `app_audit_ext` (`apps/access` → «Аудит»).
