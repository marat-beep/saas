# ECOSYSTEM — экосистема 3DMP Service

> Актуально на план **v3** (волны W29–W37, `PLAN_UPDATE_V3.md`). Источник плана — `BACKLOG.md`. Встроенная справка — база знаний (категории «Справка»/«Администрирование») и «Гид по системе».

## 1. Что это
**3DMP Service** — облачный веб-сервис для производственной компании: заявки/КП, производство (MES/APS), качество/СМК, ТОиР/EAM, склад/WMS, снабжение, экономика/финансы, документооборот (ЭДО/КЭДО), ИИ, аналитика (BI), платформа и администрирование. Весь сервис — внутри папки **`SAAS/`** → **https://sapfir.eu/saas/**.

## 2. Стек
- Клиент: **vanilla HTML/CSS/JS** (без сборки и фреймворков), PWA (`manifest.webmanifest`, `sw.js`, `offline-queue.js`).
- Бэкенд: **Supabase** (PostgreSQL + RLS), доступ к данным — только через **RPC**.
- Аутентификация: **собственная** — логин/пароль (bcrypt в Postgres), сессионные токены (`app_login`, `app_session_user`), **не** Supabase Auth.
- Ассеты: `assets/css/app.css`, `assets/js/{config,supabase-client,api,ui,auth,notify,shell,nav,export,module-report,module-info,realtime,offline-queue,support-widget,wizard,wizards,mobile}.js`.
- Деплой: FTP в `sapfir.eu\saas` (строчными). БД: Management API (UTF-8) или SQL Editor (`apply_all.sql`).

## 3. Структура
```
SAAS/
  index.html            # хаб (каталог модулей)
  apps/                 # модули (каждый — index.html + <module>.js)
  assets/               # css/js
  eco/                  # прототипы экосистемы (72 приложения, демо)
  supabase/migrations/  # миграции 0001… (не льётся)
  docs/                 # документация (не льётся)
  tools/                # build-release.ps1, audit.ps1, db-smoke.ps1 (не льётся)
  web.config, manifest.webmanifest, sw.js
```

## 4. Группы модулей (каталог `assets/js/catalog.js`, v10.31)
Каталог — единый источник модулей; содержит id, иконку, название, `href`, `roles`, `group`, `audience`, `connects` (валидные id), `features`, `purpose`.

| Группа | Кол-во | Назначение |
|---|---|---|
| **core** | 7 | вход, кабинет, панель, гид, замечания, карта внедрения, «Модули и функции» |
| **production** | 22 | заявки→производство: MES, APS, слоты, терминал, склад, IIoT/OEE, ТОиР/EAM, инструмент, НСИ, PLM, TMS, PMO, ИИ |
| **quality** | 4 | ОТК, качество/СМК, паспорта, претензии/CAPA |
| **sales** | 14 | заявки, КП, закупки, поставщики, документы, CRM, маркетплейс, партнёры, маркетинг/метки |
| **ktpp** | 8 | ТПП: НСИ/справочники, BOM, УП/NC, нормы, калькуляторы, реверс, ИИ-помощник, конфигуратор |
| **economics** | 8 | экономика, финансы, BI, отчёты, ТЭО, эскроу, бюджеты проектов, бухгалтерия |
| **platform** | 25 | биллинг, права/аудит, workflow, задачи, ЭДО, КЭДО, EHS, ITSM, e-Learning, холдинг, интеграции, API, диагностика, админ, роли, брендирование и т.д. |
| **staff** | 5 | кадры, компетенции, подразделения, CRM сотрудников, админ-панель клиента |
| **refs** | 2 | справочники (настраиваемые), прототипы экосистемы |

Полный перечень приложений — см. `MODULE_REFERENCE.md`.

## 5. Роли и доступ
- Роли: `admin`, `owner`, `manager`, `director`, `chief`, `master`, `technologist`, `operator`, `supply`, `qc`, `economist`, `support`, `supplier`, `client`.
- Видимость модуля ограничивается `roles` в каталоге; внутри модуля — `data-cap` + карта `CAPS` (client/supplier/guest скрывают редактирование).
- Гибкие права (W10): наборы прав на роль/пользователя/подразделение, делегирование, `app_can`.

## 6. Данные и интеграции
- Обмен с внешними системами (1С/ERP, PLM, ЭДО-операторы, СМС/Telegram, CV/LLM) — через очередь **`app_integrations`** (+ воркер `backend-example`).
- НСИ/MDM (W18b): единый справочник + внешние коды, импорт, дубли/слияние.
- Мониторинг: `app_health_*` (W7) — проверки БД/таблиц/функций/Realtime/интеграций/счетов.

## 7. Эксплуатация (кратко)
- Сборка: `powershell -File tools/build-release.ps1` → `dist/saas-<дата>.zip`.
- Автотесты: `tools/audit.ps1` (локально), `tools/db-smoke.ps1 -Token sbp_...` (БД), регулярно — `tools/run-checks.ps1` (W33).
- Мониторинг доступности/алерты/тренд (W33): `app_health_scan/ping/alerts_list/trend`; UI — «Диагностика».
- Расширения (W35): «Маркетплейс» → «Расширения». Детали: `RUNBOOK.md`, `RELEASE.md`.

## 8. План v3 (сделано)
- **П1:** W29 хаб/каталог, W30 навигация/возврат, W33 эксплуатация/мониторинг.
- **П2:** W34 отчёты/BI, W32 мастера, W31 мини-мобильные приложения.
- **П3:** W35 маркетплейс-расширения, W37 документация/справка, W36 мобильный офлайн (расширенный).

## 8. Демо-доступ (логин/пароль)
admin/admin · owner/owner · manager/manager · master/master · qc/otk · supply/supply · support/support · client2/client2.
