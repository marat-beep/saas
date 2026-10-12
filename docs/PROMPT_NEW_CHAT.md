# Промт для новой сессии (копировать целиком)

```
Проект 3DMP Service — рабочий веб-сервис (vanilla HTML/CSS/JS + Supabase, без сборки).
Папка SAAS/ → деплой по FTP в sapfir.eu\saas (строчными) → https://sapfir.eu/saas/. Репозиторий: github.com/marat-beep/saas (ветка main).
Supabase: проект zfkbzzmtbrueaksfaqbf; вход собственный (логин/пароль bcrypt, сессии-токены), данные через RPC (НЕ Supabase Auth/email). SQL применять только UTF-8 (Management API; токен sbp_… вводится вручную и после работы отзывается). Применение: powershell -File tools\apply-migration.ps1 -File supabase\migrations\NNNN_*.sql -Token sbp_…

СНАЧАЛА ПРОЧИТАЙ (по порядку):
1) AGENTS.md, README.md — правила и границы проекта.
2) SAAS/docs/BACKLOG.md — единый план: §3g (план v5), §5 (журнал v270–v301), §6 (этот промт), §7 «Улучшения U1–U8».
3) SAAS/docs/PLAN_UPDATE_V5.md — план X1–X20 (закрыт).
4) SAAS/docs/MODULE_BLUEPRINT.md (§1–8) и MODULE_STANDARD.md (§6 «Сверка с ТЗ», §7 «Приёмы и грабли»).
5) modules.html в КОРНЕ проекта (над SAAS/) — справочник 99 модулей (источник: tools/modules-analysis.js; генератор: node tools/gen-modules-page.js).
6) SAAS/docs/MODULES_CATALOG.md; программа аудита — SAAS/docs/AUDIT_PLAN.md, tools/audit-run.ps1.

СОСТОЯНИЕ (проверено): миграции 0001…0222 (apply_all.sql собран, 222 маркера); catalog.js v10.47 (CATALOG_APPS 99, CATALOG_V 123); app.css v36, nav.js v108, shell.js v75, auth.js v7, setup-wizard.js v5, onboarding.js v7, registry.js v9, assistant.js v3; смоук 10/10 + 14/14, волновые 44/44, перегрузок 0, аудит 100% green.
Закрыты: план v2–v4, M1–M7, R1–R4, сервис ЧПУ W-S, план v5 (X1–X20). Дополнительно: мастер настройки + демо-данные (0207), настройки модулей и доступность (0208), применение настроек в RPC (0209/0210), профили организации (0211/0212), импорт пользователей CSV + лента активности (0213), промышленные справочники (0214–0221), ЕСТД + типовые маршруты/ЭЭО/оснастка + ЕСТД-шаблоны (0218), двуязычный ИИ-помощник + автонаполнение правил (0217/0219), маршрут из типового + печать МК (0222).

ЗАДАЧА НОВОЙ СЕССИИ — продолжить наполнение и улучшения. Приоритеты:
A. Печать ОК/ВО по ЕСТД (операционная карта, ведомость оснастки) из карточки маршрута — по аналогии с МК (app_route_mk).
B. U1 — расширение справочников: литьё/ковка/сварка; полный ГОСТ-ряд посадок и крепежа; в режимы добавить зубообработку/хонингование/протягивание.
C. U2 — ИИ-помощник: LLM-поиск/обратная связь; кнопка «открыть режимы» из ответа (связь с app_ref_cutting).
D. U3 — единообразие UX по модулям (поиск/пустые состояния во всех списках).
E. U4 — 172 frontend-only RPC: вывести в UI или задокументировать как API.
F. U5 — односторонние connects каталога.
G. U7 — настройки нумерации документов и SLA (согласованная волна).
H. Остатки волн: X8 (формулы в конструкторе), X12 (сценарии/переналадки), X13 (авто-списание инструмента), X15 (вебхук провайдера/ТКП), X17 (единый сервис-склад), X5 (гейтинг qc/docs/deals).
I. Перенос данных из «Нормирование PRO» — ТОЛЬКО ЧТЕНИЕ (вики norms-wiki.js, прочее); чужой проект не изменять.

ОБЯЗАТЕЛЬНО ЛОКАЛЬНО (вносить в каждой волне, если менялись catalog.js/modules-analysis.js):
- Правь tools/modules-analysis.js: отметки done/partial, поля add/plan/why по модулям (что сделано/осталось).
- Пересобирай справочную страницу: node tools/gen-modules-page.js (пишет modules.html в корень проекта, над SAAS/) и node tools/gen-modules.js (docs/MODULES_CATALOG.md).
- modules.html — ТОЛЬКО ЛОКАЛЬНО: он вне git-репозитория и НЕ льётся на FTP (не входит в dist/saas).
- Бейдж «✅ реализовано» показывается при wave без partial или при done:true; «◐ частично» — при partial:true. Снимай partial, когда остаток волны закрыт.

ФОРМАТ РАБОТЫ: одна волна за шаг: миграция supabase/migrations/NNNN_*.sql (идемпотентно) + пересборка apply_all.sql (маркеры) + UI/версии (?v=N, CATALOG_V) + функц. тест RPC с очисткой + смоук/аудит (tools/audit.ps1, db-smoke.ps1, при токене audit-run.ps1) + отметки BACKLOG (§5 журнал, §7) + локальная пересборка modules.html + коммит/пуш main.

ГРАНИЦЫ: всё на русском; светлая палитра, акцент #10b981 (не менять); работать только внутри SAAS/; НЕ трогать НОРМ_РАЗРАБ\ (только чтение по запросу) и чужие схемы (gravirovka, norms_*, public.orders, role_passwords), чужие ключи/URL; секреты (service_role/sb_secret_*/DB-пароль) не логировать и не коммитить; коммит/пуш — по DoD волны.
Демо-доступы: admin/admin, owner/owner, manager/manager, master/master, qc/otk, supply/supply, supplier/supplier, support/support, client2/client2.

ЗАЛИВКА НА FTP (по явной просьбе): из dist/saas/ (index.html, apps/, assets/, eco/, web.config, manifest.webmanifest, sw.js) → sapfir.eu\saas; затем Ctrl+F5. Перед заливкой применить на сервере миграции 0207…0222.
```
