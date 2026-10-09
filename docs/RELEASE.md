# RELEASE — подготовка релиза для загрузки (FTP) и дальнейшей разработки

## 1. Сборка
```
powershell -NoProfile -ExecutionPolicy Bypass -File tools\build-release.ps1
```
Результат: `dist\saas-<yyyyMMdd-HHmm>.zip` (деплой-артефакты). `dist/` в `.gitignore`.

**Льётся** (в серверную папку `sapfir.eu\saas`, строчными): `index.html`, `apps/`, `assets/`, `eco/`, `web.config`, `manifest.webmanifest`, `sw.js`.
**Не льётся:** `supabase/`, `docs/`, `tools/`, `dist/`, `.git`, `README.md`, `AGENTS.md`.

## 2. База данных
- Миграции `supabase/migrations/0001…0184` + пересобранный `supabase/apply_all.sql`.
- Инструменты: `tools/build-release.ps1` (сборка dist), `tools/audit.ps1` (локальный автотест), `tools/db-smoke.ps1` (смоук БД через Management API), `tools/run-checks.ps1` (обёртка audit+db-smoke, лог в `dist/checks/`, код возврата).
- Применение — Supabase → SQL Editor → вставить `apply_all.sql` → Run (либо Management API, UTF-8).
- Смоук: `select * from app_smoke_test(:token);` (10/10) и `app_smoke_test_ext(:token)` (14/14).

### 2a. Эксплуатация и мониторинг (W33)
- **Плановые проверки:** `powershell -ExecutionPolicy Bypass -File tools\run-checks.ps1 -Token sbp_...` (без токена — только локальный аудит; `-SkipDb` — пропустить БД). Лог — `dist\checks\checks-<stamp>.log`; код 0 — ок, 1 — есть проблемы.
- **Расписание:** Windows Task Scheduler → `powershell -NoProfile -ExecutionPolicy Bypass -File <SAAS>\tools\run-checks.ps1 -Token <…>`; либо CI `.github/workflows/checks.yml` (ежедневно 03:00 UTC; секрет `SUPABASE_ACCESS_TOKEN`).
- **Внешний uptime-мониторинг:** `select * from public.app_health_ping('<api_key>');` — по API-ключу организации (пишет `app_health_pings`, обновляет `last_used_at`).
- **Алерты (дедуп):** `app_health_scan` проверяет «свежесть данных» и пинги, открывает записи в `app_health_alerts` (дедуп по `kind:name`) и уведомляет администраторов платформы при сбое; при возврате в норму — закрывает. Список/закрытие: `app_health_alerts_list`, `app_health_alert_resolve`.
- **Тренд доступности:** `app_health_trend(:token, :days)`; дашборд — модуль **`apps/diagnostics`** (блок «Мониторинг доступности»).

## 3. Типовой инструментарий (применён во всех модулях `apps/`)
- Общий CSS (`assets/css/app.css`): `.sv-actions`, `.tabs2`, `.act`, `.screen`/`.screen.active`.
- `shell.js` — сайдбар + **системный поиск** + ролевой fallback (client/supplier/guest скрывают `[data-cap="edit"]`).
- `export.js` — единые отчёты PDF/DOC/CSV (`AppExport.reportDocument`).
- `module-report.js` + `app_module_report(token, module)` — универсальный отчёт по модулю (кнопка `data-report`).
- Роли — `data-cap` + карта `CAPS` в JS модуля.
- `wizard.js` + `wizards.js` — пошаговые мастера (W32): кнопка `data-wizard`/авто-подстановка; черновик в localStorage.
- `mobile.js` — мини-мобильный режим (W31): нижняя панель быстрых действий из `AppCatalog.quick`, `?mobile=1`, офлайн-действия (`AppOffline`), PWA-установка.
- `offline-queue.js` (v2, идемпотентность) + `offline-cache.js` (IndexedDB-кэш чтения) + `scan.js` (QR/ШК, фото, геометка) — офлайн (W36); `sw.js` v3 — кэш-стратегии по маршрутам.

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
- **v250 (миграция `0184`)** — W42 аналитика производства: APS-очередь, предиктив ТОиР, SPC-сигналы; вкладка «Аналитика» в apps/planning.
- **v249 (миграция `0183`)** — W41 отчётность/BI 2.0: дашборд KPI по контурам, расписание рассылки (очередь интеграций), XLS(X) экспорт; UI `apps/reports` v5.
- **v248 (миграция `0182`)** — W40 расширения 2.0: приватные (`tenant_id`), проверка зависимостей, `app_ext_detail`/`app_ext_save`(область)/`app_my_tenant_id`; редактор манифеста в `apps/marketplace`.
- **v247 (миграция `0181`)** — W39 безопасность/аудит 2.0: политики (`app_security_policies`), смена пароля, «мои устройства/сессии», журнал доступа, TTL сессии/срок пароля в `app_login`; вкладка «Безопасность» в `apps/org`.
- **v246** — W38 UI/UX-консистентность (план v4): единые адаптивные сетки.
- **v243** — W36 мобильный офлайн (план v3 закрыт): `offline-queue.js` v2 (идемпотентность), `offline-cache.js` (IndexedDB-кэш чтения), `scan.js` (QR/ШК/фото/геометка), `sw.js` v3 (кэш по маршрутам); офлайн-склад, скан в моб. панели. Каталог v10.32, shell v73, CATALOG_V 108.
- **v242 (миграция `0180`)** — W37 документация/мануалы: актуализированы USER/ADMIN/RUNBOOK/ECOSYSTEM/MODULE_REFERENCE; паки БЗ «Справка»/«Администрирование»; раздел «Справка и мануалы» в `apps/guide` v4.
- **v241 (миграция `0179`)** — W35 маркетплейс-расширения: `app_extensions`/`app_extension_installs` + RPC (каталог/установка/включение/удаление/манифест), включение коннектора подтягивает `app_integrations`, аудит; вкладка «Расширения» в `apps/marketplace`.
- **v240** — W31 мини-мобильные приложения модулей: `assets/js/mobile.js` (нижняя панель быстрых действий, `?mobile=1`, PWA-установка) + `quick` в `catalog.js` (15 модулей; переходы/мастера/RPC с офлайн-очередью). Каталог v10.31, shell v72, CATALOG_V 107. Пакет П2 закрыт.
- **v239** — W32 мастера (wizards): движок `assets/js/wizard.js` + `assets/js/wizards.js` (6 пилотов: НСИ, инструмент, приёмка, процесс, КЭДО, перевозка), авто-кнопка в 6 модулях.
- **v238 (миграция `0178`)** — W34 отчёты/BI на новые модули: `app_module_report` +16 веток, `module-report.js` v2 (авто-кнопка отчёта) в 15 модулях, `reports.js` — 16 наборов данных + дашборд новых модулей.
- **v237 (миграция `0177`)** — W33 эксплуатация/мониторинг: `app_health_ping` (uptime по API-ключу), `app_health_alerts`+`app_health_pings`, алерты с дедупом и уведомлением в `app_health_scan` (+«свежесть данных»), `app_health_alerts_list`/`app_health_alert_resolve`, `app_health_trend`; дашборд в `apps/diagnostics`; `tools/run-checks.ps1` + CI `.github/workflows/checks.yml`. Каталог v10.30, nav v108/shell v71.
- **v236–v235** — пакет П1 плана v3: W29 хаб/каталог (читаемые группы без «ещё N»), W30 навигация/возврат (кнопка «Назад» + крошки).
- **v233 (миграция `0176`)** — приёмка волн v2: устранены перегрузки (переименования), `db-smoke` 44/44 + перегрузки 0; релиз `dist/saas-20261009-1301.zip`.
- **v232 (миграция `0175`)** — W27 бухгалтерия (задел): план счетов, проводки, ОСВ; модуль `apps/accounting`; каталог v10.29, nav v108/shell v70. План обновления v2 (0158–0175) закрыт.
- **v231 (миграция `0174`)** — W26 e-Learning: курсы, назначения, тесты; модуль `apps/elearning`; каталог v10.28, nav v107/shell v69.
- **v230 (миграция `0173`)** — W24 ITSM/ITIL: каталог услуг, заявки со SLA; модуль `apps/itsm`; каталог v10.27, nav v106/shell v68.
- **v229 (миграция `0172`)** — W23 TMS/логистика: перевозчики, рейсы, KPI; модуль `apps/logistics`; каталог v10.26, nav v105/shell v67. Пакет 5 закрыт.
- **v228 (миграция `0171`)** — W25 PMO: портфели, вехи, риски; модуль `apps/pmo`; каталог v10.25, nav v104/shell v66.
- **v227 (миграция `0170`)** — W28 бюджет проектов: смета, план-факт, освоение EVM; модуль `apps/projbudget`; каталог v10.24, nav v103/shell v65.
- **v226 (миграция `0169`)** — W22 холдинг/CPM: площадки, снимки KPI, консолидация с долей; модуль `apps/holding`; каталог v10.23, nav v102/shell v64. Пакет 4 закрыт.
- **v225 (миграция `0168`)** — W21 охрана труда/EHS: инструктажи, допуски, СИЗ, медосмотры, инциденты; модуль `apps/safety`; каталог v10.22, nav v101/shell v63.
- **v224 (миграция `0167`)** — W17 экосистема: лог API, подписи (ПЭП/УНЭП/УКЭП/Госключ), проверка контрагентов; reuse ключей/webhooks; UI `apps/api`; каталог v10.21, nav v100/shell v62.
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
