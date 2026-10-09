# RELEASE — подготовка релиза для загрузки (FTP) и дальнейшей разработки

## 1. Сборка
```
powershell -NoProfile -ExecutionPolicy Bypass -File tools\build-release.ps1
```
Результат: `dist\saas-<yyyyMMdd-HHmm>.zip` (деплой-артефакты). `dist/` в `.gitignore`.

**Льётся** (в серверную папку `sapfir.eu\saas`, строчными): `index.html`, `apps/`, `assets/`, `eco/`, `web.config`, `manifest.webmanifest`, `sw.js`.
**Не льётся:** `supabase/`, `docs/`, `tools/`, `dist/`, `.git`, `README.md`, `AGENTS.md`.

## 2. База данных
- Миграции `supabase/migrations/0001…0166` + пересобранный `supabase/apply_all.sql`.
- Инструменты: `tools/build-release.ps1` (сборка dist), `tools/audit.ps1` (локальный автотест), `tools/db-smoke.ps1` (смоук БД через Management API).
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
- **v223 (миграция `0166`)** — W14 CMMS/EAM 2.0: вибро(+авто-наряд), энерго, простои, версии УП, карта цеха; модуль `apps/eam`; каталог v10.20, nav v99/shell v61. Пакет 3 закрыт.
- **v222 (миграция `0165`)** — W20 КЭДО: кадровые документы/ознакомления/подпись, шаблоны, ЛК, МЧД; модуль `apps/kedo`; каталог v10.19, nav v98/shell v60.
- **v221 (миграция `0164`)** — W16 совместная работа: проекты/задачи/канбан, время, обсуждения, inbox, БЗ 2.0; модуль `apps/tasks`; каталог v10.18, nav v97/shell v59.
- **v220 (миграция `0163`)** — W19 ЭДО/СЭД: реестр документов, регистрация, поручения, связи, номенклатура дел/архив; модуль `apps/edo`; каталог v10.17, nav v96/shell v58. Пакет 2 плана v2 закрыт.
- **v219 (миграция `0162`)** — W18c PDM/PLM: изделия/состав/документы/ECN; модуль `apps/plm`; каталог v10.16, nav v95/shell v57.
- **v218 (миграция `0161`)** — W18b НСИ/MDM: единый справочник, версии, внешние коды, дубли/слияние, импорт; модуль `apps/mdm`; каталог v10.15, nav v94/shell v56.
- **v217 (миграция `0160`)** — W18a финансы/FRP: бюджеты/ЦФО и план-факт, платёжный календарь, KPI, себестоимость; UI `finance`; каталог v10.14 (🆕), nav v93/shell v55. Пакет 1 плана v2 закрыт.
- **v216 (миграция `0159`)** — W15 low-code workflow: процессы/задачи/SLA, правила-триггеры, формы; модуль `apps/workflow`; каталог v10.13, nav v92/shell v54.
- **v215 (миграция `0158`)** — W13 инструментальное хозяйство 2.0: экземпляры/история, каталог+аналоги, инвентаризация, оснащение техкарт; UI `tooling`; каталог v10.12, nav v91/shell v53.
- **v214** — план обновления v2 (W13–W27, миграции `0158…0174`): ЭДО/СЭД, КЭДО, инструмент 2.0, CMMS/EAM 2.0, low-code workflow, ERP-контур (FRP/MDM/PDM), EHS, холдинг. Детали `PLAN_UPDATE_V2.md`.
- **v213** — P0 закрыт (приёмка панели залита); `tools/db-smoke.ps1` дополнен дымовыми проверками волн W7–R4 (17/17).
- **v212 (миграция `0157`)** — R1+R3+R4: CRM-напоминания, генеалогия партий, гейтинг по подразделению; каталог v10.11, nav v90/shell v52. (R2 онлайн-оплата — пропущено.)
- **v211 (ревизия контуров)** — сверка `AUDIT_BACKLOG §3` с волнами (закрыто W2–W12), остаток R1–R4 (CRM-напоминания, онлайн-оплата клиента, генеалогия партий, гейтинг по подразделению).
- **v210 (M7 остаток)** — апгрейд `iiot`/`crm`/`client`/`org`: отчёты, роли `data-cap`, переходы, KB. M7 закрыт.
- **v209 (S1)** — малые доработки UI: автотесты `tools/audit.ps1` (+дубли id/версия notify) и `tools/db-smoke.ps1` (+проверка кодировки); проверка панели/drawer/версий.
- **v208 (W12)** — продуктивность и эксплуатация: единый API-слой `assets/js/api.js`; автотесты `tools/audit.ps1` (audit ✅) и `tools/db-smoke.ps1` (10/10+14/14); ревизия доков (MODULE_STANDARD §8).
- **v207 (миграция `0156`)** — W11 ИИ: авто-нормирование, CV-ОТК, цифровой двойник, помощник по БЗ, журнал задач; модуль `apps/ai`; каталог v10.10, nav v89/shell v51.
- **v206 (миграция `0155`)** — W10 enterprise-права и аудит: наборы прав, делегирование, согласования, расширенный аудит; модуль `apps/access`; каталог v10.9, nav v88/shell v50.
- **v205 (миграция `0154`)** — W9 MES/APS/IIoT: APS-автоплан, коннекторы OPC UA/MTConnect, приём телеметрии, OEE онлайн, износ инструмента; `apps/planning`+`apps/iiot`; каталог v10.8, nav v87/shell v49.
- **v204 (миграция `0153`)** — W8 аналитика L4: конструктор отчётов, прогноз спроса/рисков, предиктив ТОиР; `apps/reports`+`apps/forecast`; каталог v10.7, nav v86/shell v48.
- **v203 (миграция `0152`)** — W7 биллинг/подписки и SLA платформы: тарифы+лимиты, подписки, счета платформы, статус-борд доступности, контроль квот; модуль `apps/billing`; каталог v10.6, nav v85/shell v47.
- **v201 (миграция `0151`)** — отчёты: ветка `users` + подключение к admin/slots/planning/quality.
- **v199–200** — универсальный `app_module_report` (16 модулей) + ролевой fallback в `shell.js` + оборудование.
- **v190–194** — M6 (production/procurement/warehouse/docs/finance).
- **v195–197** — M7 (tooling/nc/oee).
