# RELEASE — подготовка релиза для загрузки (FTP) и дальнейшей разработки

## 1. Сборка
```
powershell -NoProfile -ExecutionPolicy Bypass -File tools\build-release.ps1
```
Результат: `dist\saas-<yyyyMMdd-HHmm>.zip` (деплой-артефакты). `dist/` в `.gitignore`.

**Льётся** (в серверную папку `sapfir.eu\saas`, строчными): `index.html`, `apps/`, `assets/`, `eco/`, `web.config`, `manifest.webmanifest`, `sw.js`.
**Не льётся:** `supabase/`, `docs/`, `tools/`, `dist/`, `.git`, `README.md`, `AGENTS.md`.

## 2. База данных
- Миграции `supabase/migrations/0001…0156` + пересобранный `supabase/apply_all.sql`.
- Применение — Supabase → SQL Editor → вставить `apply_all.sql` → Run (либо Management API, UTF-8).
- Смоук: `select * from app_smoke_test(:token);` (10/10) и `app_smoke_test_ext(:token)` (14/14).

## 3. Типовой инструментарий (применён во всех модулях `apps/`)
- Общий CSS (`assets/css/app.css`): `.sv-actions`, `.tabs2`, `.act`, `.screen`/`.screen.active`.
- `shell.js` — сайдбар + **системный поиск** + ролевой fallback (client/supplier/guest скрывают `[data-cap="edit"]`).
- `export.js` — единые отчёты PDF/DOC/CSV (`AppExport.reportDocument`).
- `module-report.js` + `app_module_report(token, module)` — универсальный отчёт по модулю (кнопка `data-report`).
- Роли — `data-cap` + карта `CAPS` в JS модуля.

## 4. Волны апгрейда (сделано)
- **W-S (сервис ЧПУ по ТЗ):** заявки/SLA/гарантии/контракты, выезды, паспорт станка, отчёты, IIoT/ППР, матрица ролей, процесс, печать.
- **M1–M7:** `maintenance, orders, qc/claims, economics, hr, production, procurement, warehouse, docs, finance, tooling, nc, oee` — отчёты, роли, связи, KB.
- **Универсальные отчёты:** `app_module_report` (17 модулей) + кнопки в iiot/client/crm/suppliers/departments/org/guide/registry/mes/equipment/admin/slots/planning/quality/terminal.

## 5. Чек-лист перед заливкой
- [ ] `apply_all.sql` применён; смоук 10/10 и 14/14.
- [ ] Версии ассетов подняты (`?v=N`, `CATALOG_V`, `app.css`, `nav.js`, `shell.js`, `<модуль>.js`).
- [ ] Ссылки каталога валидны; нет перегрузок функций в БД.
- [ ] Собран `dist/saas-<date>.zip`; залит на FTP; **Ctrl+F5** (кэш статики отключён `web.config`).
- [ ] Отметки в `BACKLOG.md`, `PLAN_WAVES.md`, `STATUS.md`, `NOTES.md`, `PROMPTS.md`.

## 6. Журнал релизов (последнее)
- **v207 (миграция `0156`)** — W11 ИИ: авто-нормирование, CV-ОТК, цифровой двойник, помощник по БЗ, журнал задач; модуль `apps/ai`; каталог v10.10, nav v89/shell v51.
- **v206 (миграция `0155`)** — W10 enterprise-права и аудит: наборы прав, делегирование, согласования, расширенный аудит; модуль `apps/access`; каталог v10.9, nav v88/shell v50.
- **v205 (миграция `0154`)** — W9 MES/APS/IIoT: APS-автоплан, коннекторы OPC UA/MTConnect, приём телеметрии, OEE онлайн, износ инструмента; `apps/planning`+`apps/iiot`; каталог v10.8, nav v87/shell v49.
- **v204 (миграция `0153`)** — W8 аналитика L4: конструктор отчётов, прогноз спроса/рисков, предиктив ТОиР; `apps/reports`+`apps/forecast`; каталог v10.7, nav v86/shell v48.
- **v203 (миграция `0152`)** — W7 биллинг/подписки и SLA платформы: тарифы+лимиты, подписки, счета платформы, статус-борд доступности, контроль квот; модуль `apps/billing`; каталог v10.6, nav v85/shell v47.
- **v201 (миграция `0151`)** — отчёты: ветка `users` + подключение к admin/slots/planning/quality.
- **v199–200** — универсальный `app_module_report` (16 модулей) + ролевой fallback в `shell.js` + оборудование.
- **v190–194** — M6 (production/procurement/warehouse/docs/finance).
- **v195–197** — M7 (tooling/nc/oee).
